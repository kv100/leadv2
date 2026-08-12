#!/usr/bin/env bash
# leadv2-plan-run.sh — ONE-PATH-PLAN-RUN-01: sole-owner Plan + Diagnose engine.
#
# Mirrors the shipped review engine (leadv2-review-run.sh) in structure:
#   - Self-contained: does NOT source the lane (leadv2-dispatch-product-close.sh /
#     leadv2-dispatch-code.sh) and never calls the lane's journal emit — callable
#     from a bare bash session with no Claude lead, no Workflow tool, no MCP.
#   - Pool resolution via the resolver (leadv2-glm-policy-resolve.py) with
#     --job plan --plan-pool; arm chain via _engine_pool_ok_arms; failure
#     classification via classify_arm_failure.
#   - Bounded-wait watcher subshell (bash 3.2-safe, no GNU timeout).
#
# WRITE-RACE NOTE (R1): this engine writes docs/handoff/<task>/context.yaml via
# .tmp + mv (atomic). The engine writes the skeleton (deterministic fields) FIRST,
# before any arm runs. Arms never write context.yaml — they emit a PLAN_YAML fenced
# block which the engine merges. Engine-owned keys (id, mission, reads, writes,
# lane_writes, acceptance.authored_at) are always restored after merge.
#
# plan-gate.md WRITE ORDER (R2): this engine writes plan-gate.md FIRST via .tmp + mv.
# The EXIT trap only writes when the file is ABSENT (fallback-only writer). Single
# writer, no race.
#
# CRITICAL INVARIANT: this engine issues NO bare `claude -p` anywhere. Model arms
# go through claude-subsession.sh --wait (which owns the flag set — see
# claude-subsession.sh ~line 338-342). Adding a direct `claude -p` to this engine
# is a CRITICAL review finding.
#
# PREPASS NOTE (R9): --mode prepass is built and tested standalone, but its
# consumer (architect_prepass() in leadv2-dispatch-code.sh) is off-limits in this
# lane. The follow-up lane wires it. Do not delete it as dead code.
#
# FLAG: LEADV2_ARCHITECT_GATE=0 disables the engine (kill switch). The lane call
# site and LEADV2_PLAN_RUN rollout flag are off-limits in this lane.
#
# Exit codes (mirroring leadv2-review-run.sh):
#   0 = pass · 2 = usage · 7 = fail (gate written, status: fail) ·
#   9 = blocked (gate written, status: blocked)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-"$0"}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Arg parsing (mirror leadv2-review-run.sh:37-55)
# ---------------------------------------------------------------------------
TASK=""; ROOT=""; HANDOFF=""; MODE=""; MISSION=""; MISSION_FILE=""
WRITES_CSV=""; TASK_CLASS=""; FANOUT_ARG=""; LOG_PATH=""; DIFF_PATHS=""
NO_CACHE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task|--task-id)    TASK="${2:-}"; shift 2 ;;
    --root)              ROOT="${2:-}"; shift 2 ;;
    --handoff)           HANDOFF="${2:-}"; shift 2 ;;
    --mode)              MODE="${2:-}"; shift 2 ;;
    --mission)           MISSION="${2:-}"; shift 2 ;;
    --mission-file)      MISSION_FILE="${2:-}"; shift 2 ;;
    --writes)            WRITES_CSV="${2:-}"; shift 2 ;;
    --class)             TASK_CLASS="${2:-}"; shift 2 ;;
    --fanout)            FANOUT_ARG="${2:-}"; shift 2 ;;
    --log-path)          LOG_PATH="${2:-}"; shift 2 ;;
    --diff-paths)        DIFF_PATHS="${2:-}"; shift 2 ;;
    --no-cache)          NO_CACHE=1; shift ;;
    *) printf 'leadv2-plan-run.sh: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${TASK}" || -z "${ROOT}" || -z "${HANDOFF}" || -z "${MODE}" ]]; then
  printf 'leadv2-plan-run.sh: --task, --root, --handoff and --mode are all required\n' >&2
  exit 2
fi

case "${MODE}" in
  prepass|plan|diagnose) ;;
  *) printf 'leadv2-plan-run.sh: --mode must be prepass|plan|diagnose (got: %s)\n' "${MODE}" >&2; exit 2 ;;
esac

if [[ -n "${MISSION}" && -n "${MISSION_FILE}" ]]; then
  printf 'leadv2-plan-run.sh: --mission and --mission-file are mutually exclusive\n' >&2
  exit 2
fi

if [[ -z "${MISSION}" && -z "${MISSION_FILE}" ]]; then
  printf 'leadv2-plan-run.sh: one of --mission or --mission-file is required\n' >&2
  exit 2
fi

PLAN_FANOUT="${FANOUT_ARG:-${LEADV2_PLAN_FANOUT:-2}}"
[[ "${PLAN_FANOUT}" =~ ^[1-9][0-9]*$ ]] || PLAN_FANOUT=2

ARM_TIMEOUT_S="${LEADV2_PLAN_ARM_TIMEOUT_S:-900}"

# Read mission into memory BEFORE any arm dispatch (P3's race protection idiom).
MISSION_TEXT=""
if [[ -n "${MISSION_FILE}" ]]; then
  [[ -f "${MISSION_FILE}" ]] || { printf 'leadv2-plan-run.sh: mission-file not found: %s\n' "${MISSION_FILE}" >&2; exit 2; }
  MISSION_TEXT="$(cat "${MISSION_FILE}")"
else
  MISSION_TEXT="${MISSION}"
fi

mkdir -p "${HANDOFF}" 2>/dev/null || true

# Engine-local logger — stderr-only, never calls the lane's journal emit.
emit() { printf '[leadv2-plan-run] %s %s\n' "${1:-}" "${2:-}" >&2; }

# Compute artifact path relative to ROOT for gate output.
_artifact_rel="${HANDOFF}"
case "${HANDOFF}" in
  "${ROOT}/"*) _artifact_rel="${HANDOFF#${ROOT}/}" ;;
esac

CONTEXT_YAML="${HANDOFF}/context.yaml"

# Write gate file atomically (.tmp + mv -f).
# Keys mirror review-gate.md format (design §3.2).
GATE_WRITTEN=0
write_gate() { # <status> <reason> <arms_csv> <acceptance>
  local status="$1" reason="$2" arms_csv="${3:--}"
  local acceptance="${4:-skipped}"
  local artifact="${_artifact_rel}/context.yaml"
  [[ "${MODE}" == "diagnose" ]] && artifact="${_artifact_rel}/root-cause.md"
  {
    printf 'mode: %s\n' "${MODE}"
    printf 'status: %s\n' "${status}"
    printf 'reason: %s\n' "${reason}"
    printf 'arms: %s\n' "${arms_csv}"
    printf 'artifact: %s\n' "${artifact}"
    printf 'acceptance: %s\n' "${acceptance}"
  } > "${HANDOFF}/plan-gate.md.tmp"
  mv -f "${HANDOFF}/plan-gate.md.tmp" "${HANDOFF}/plan-gate.md"
  GATE_WRITTEN=1
}

# EXIT trap — fallback-only writer (R2). Fires only when the engine exited
# abnormally without writing a gate.
_exit_trap() {
  [[ "${GATE_WRITTEN}" == "1" ]] && return 0
  write_gate "blocked" "provider_error" "-" "${MODE:+skipped}"
}
trap _exit_trap EXIT

# ---------------------------------------------------------------------------
# 2. Kill switch — LEADV2_ARCHITECT_GATE=0 disables the engine
# ---------------------------------------------------------------------------
if [[ "${LEADV2_ARCHITECT_GATE:-1}" == "0" ]]; then
  emit decision "plan_run task=${TASK} status=disabled mode=${MODE}"
  write_gate "pass" "disabled" "-" "skipped"
  exit 0
fi

# Compute mission signature early (needed for cache probe AND cache stamping).
MISSION_SIG="$(printf '%s' "${MISSION_TEXT}" | shasum -a 256 | awk '{print $1}')"

# ---------------------------------------------------------------------------
# 3. Cache probe (prepass/plan only; skipped under --no-cache)
#    H4: a cached artifact carrying no lane_writes: key is a miss, not a hit.
#    M7: a park still stamps the cache so a byte-identical retry does not pay
#    the architect twice.
# ---------------------------------------------------------------------------
if [[ "${MODE}" != "diagnose" && "${NO_CACHE}" == "0" && "${LEADV2_PREPASS_CACHE:-1}" != "0" ]]; then
  CACHED_SIG=""
  [[ -f "${HANDOFF}/context.yaml.sig" ]] && CACHED_SIG="$(cat "${HANDOFF}/context.yaml.sig" 2>/dev/null)"
  if [[ -n "${CACHED_SIG}" && "${CACHED_SIG}" == "${MISSION_SIG}" && -f "${CONTEXT_YAML}" ]]; then
    # H4: cached artifact with no lane_writes: key is a miss.
    if ! grep -q '^lane_writes:' "${CONTEXT_YAML}" 2>/dev/null; then
      emit decision "plan_run task=${TASK} status=cache_miss mode=${MODE} reason=no_lane_writes"
    # H4 continued: cached artifact that fails validate is a miss, not a hit.
    elif bash "${SCRIPT_DIR}/leadv2-acceptance-shape.sh" validate "${CONTEXT_YAML}" >/dev/null 2>&1; then
      emit decision "plan_run task=${TASK} status=cached mode=${MODE}"
      write_gate "pass" "ok" "-" "valid"
      exit 0
    else
      emit decision "plan_run task=${TASK} status=cache_miss mode=${MODE} reason=stale_cached_artifact"
    fi
  else
    emit decision "plan_run task=${TASK} status=cache_miss mode=${MODE}"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Pool resolution — structurally identical to resolve_review_pool_call()
#    in leadv2-review-run.sh:71-110, but uses --plan-pool (no --author; plan
#    has no author-exclusion concept). The resolver filters against
#    DISPATCHABLE_PLAN_ARMS via job=plan.
# ---------------------------------------------------------------------------
resolve_plan_pool_call() {
  local resolver="${LEADV2_GLM_POLICY_RESOLVER:-}"
  if [[ -z "${resolver}" ]]; then
    if [[ -f "${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py" ]]; then
      resolver="${SCRIPT_DIR}/lib/leadv2-glm-policy-resolve.py"
    else
      local _canonical="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py"
      [[ -f "${_canonical}" ]] && resolver="${_canonical}"
    fi
  fi
  if [[ -z "${resolver}" || ! -f "${resolver}" ]]; then
    printf 'planner=\npool=\nrefusal=resolver_missing_failclosed\n'
    return
  fi
  local routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"
  local _signals_json='{}'
  local -a resolver_args=(--routing-yaml "${routing_yaml}" --job plan --base-arm codex \
    --plan-pool --signals "${_signals_json}")
  [[ -n "${GLM_POLICY_QUOTA_LIVE:-}" ]] && resolver_args+=(--quota-live "${GLM_POLICY_QUOTA_LIVE}")
  python3 "${resolver}" "${resolver_args[@]}" 2>/dev/null || printf 'planner=\npool=\nrefusal=resolver_error_failclosed\n'
}

# ---------------------------------------------------------------------------
# 5. Failure classification — lifted from leadv2-review-run.sh with one addition:
#    codex_skipped_by_policy (rc=0) → arm_unavailable (not error, not park).
# ---------------------------------------------------------------------------
classify_arm_failure() { # <rc> <err-file> <out-file>
  local rc="${1:-}" err_file="${2:-}" out_file="${3:-}"
  local combined
  combined="$(cat "${out_file}" 2>/dev/null || true)"$'\n'"$(cat "${err_file}" 2>/dev/null || true)"

  if [[ "${rc}" == "77" ]]; then
    printf 'refused_channel_down'
    return 0
  fi

  local marker
  marker="$(printf '%s\n' "${combined}" | sed -n 's/.*LEADV2_DISPATCH_REFUSED:[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' | head -1)"
  if [[ -n "${marker}" && ( "${rc}" == "1" || "${rc}" == "2" || "${rc}" == "75" ) ]]; then
    if [[ "${marker}" == "peak_hours" ]]; then
      printf 'refused_peak_hours'
    else
      printf 'refused_quota'
    fi
    return 0
  fi

  if [[ "${rc}" == "1" && "${combined}" == *"[glm-quota-gate] REROUTE"* ]]; then
    printf 'refused_quota'
    return 0
  fi

  if [[ "${rc}" == "75" ]]; then
    printf 'refused_quota'
    return 0
  fi

  # Addition for plan engine: codex_skipped_by_policy (rc=0) is arm_unavailable.
  if [[ "${rc}" == "0" && "${combined}" == *"codex_skipped_by_policy"* ]]; then
    printf 'arm_unavailable'
    return 0
  fi

  printf 'ran'
  return 0
}

next_ok_arm_after() { # <after-arm>  reads ${pool}
  local after="$1" found=0 entry arm
  local _pool="${pool}"
  local IFS=','
  for entry in ${_pool}; do
    arm="${entry%%:*}"
    if [[ "${found}" == "1" && "${entry}" == "${arm}:ok:"* ]]; then
      printf '%s' "${arm}"
      return 0
    fi
    [[ "${arm}" == "${after}" ]] && found=1
  done
  return 1
}

# _engine_pool_ok_arms — extract ordered list of :ok: arms from ${pool}, dedup (A4).
_engine_pool_ok_arms() {
  local entry arm
  local IFS=','
  local seen=""
  for entry in ${pool}; do
    arm="${entry%%:*}"
    [[ "${entry}" == "${arm}:ok:"* ]] || continue
    case ",${seen}," in
      *",${arm},"*) continue ;;
    esac
    seen="${seen},${arm}"
    printf '%s\n' "${arm}"
  done
}

# ---------------------------------------------------------------------------
# 6. Arm implementations
# ---------------------------------------------------------------------------
run_planner_arm() { # <arm> <role> — sets planner_rc, writes output to plan-arm-<suffix>.yaml
  local arm="$1" role="$2"
  local suffix="${arm}"
  [[ "${role}" == "critic" ]] && suffix="${arm}-critic"
  local planner_out="${HANDOFF}/plan-arm-${suffix}.yaml"
  local planner_err="${HANDOFF}/plan-arm-${suffix}.err"
  local planner_mission="${HANDOFF}/plan-arm-${suffix}.mission"

  # Build mission prompt for this arm. Arms are told context.yaml is engine-owned.
  local engine_owned_notice=$'ENGINE-OWNED (do NOT emit these — your values are discarded):\nid, mission, reads, writes, lane_writes, acceptance.authored_at\n'
  if [[ "${role}" == "architect" ]]; then
    {
      printf '%s\n' "${engine_owned_notice}"
      printf '\nMISSION:\n%s\n' "${MISSION_TEXT}"
      printf '\nYou are the architect. Produce a YAML document with ONLY these judgment fields.\n'
      printf 'Answer with one fenced block:\n\n```yaml\nPLAN_YAML:\ndecisions: [...]\noff_limits: [...]\nplan:\n  steps: [...]\nacceptance:\n  surface: <rendered_line|prod_db_row|log_line|http_response|file_artifact>\n  observable: <what a human sees at the surface>\nrisk: <low|medium|high>\n```\n'
    } > "${planner_mission}"
  else
    # Critic role: read the architect draft and emit findings + revised judgment.
    local arch_draft="${HANDOFF}/plan-arm-${arm}.yaml"
    [[ -f "${arch_draft}" ]] || arch_draft="${HANDOFF}/plan-arm-codex.yaml"
    {
      printf '%s\n' "${engine_owned_notice}"
      printf '\nMISSION:\n%s\n' "${MISSION_TEXT}"
      printf '\nYou are the critic. Review the architect draft below.\n'
      printf 'Emit PLAN_FINDING: lines for any blocking issue, then a revised PLAN_YAML block.\n'
      printf '\n--- ARCHITECT DRAFT ---\n'
      cat "${arch_draft}" 2>/dev/null
    } > "${planner_mission}"
  fi

  if [[ "${arm}" == "codex" ]]; then
    local codex_mode="plan"
    [[ "${MODE}" == "diagnose" ]] && codex_mode="diagnose"
    bash "${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/leadv2-codex-planner.sh}" \
      --task-id "${TASK}" --mode "${codex_mode}" --mission-file "${planner_mission}" --wait \
      > "${planner_out}" 2> "${planner_err}"
    planner_rc=$?
  else
    # sonnet / opus / fable — MUST go through claude-subsession.sh, never bare claude -p
    # (design.md R5: -p + stream-json requires --verbose or the process dies instantly).
    PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" \
      --role "${role}" --model "${arm}" --task-id "dispatch-${TASK}" \
      --mission-file "${planner_mission}" --wait \
      > "${planner_out}" 2> "${planner_err}"
    planner_rc=$?
  fi
  printf '%s' "${planner_rc}" > "${HANDOFF}/plan-arm-${suffix}.rc"
}

# Bounded-wait watcher — bash 3.2-safe, no GNU timeout.
_engine_run_arm_with_timeout() { # <arm> <role>
  local arm="$1" role="$2"
  (
    run_planner_arm "${arm}" "${role}"
  ) &
  local job_pid=$!
  ( sleep "${ARM_TIMEOUT_S}"; kill -TERM "${job_pid}" 2>/dev/null ) &
  local watcher_pid=$!
  wait "${job_pid}" 2>/dev/null
  kill "${watcher_pid}" 2>/dev/null
  wait "${watcher_pid}" 2>/dev/null
  true
}

# Extract the PLAN_YAML fenced block from an arm output file.
# If no fenced block exists, returns the whole file (for stub/test arms that
# emit raw YAML directly).
extract_plan_yaml() { # <file> → stdout: extracted YAML
  local f="$1"
  local extracted
  # awk: after PLAN_YAML:, skip the opening ``` fence, print content until
  # the closing ``` fence, then exit.
  extracted="$(awk '
    /^PLAN_YAML:/ { found=1; next }
    found && /^```/ { fence++ ; if (fence==1) next; exit }
    found { print }
  ' "$f" 2>/dev/null)"
  if [[ -n "${extracted}" ]]; then
    printf '%s\n' "${extracted}"
  else
    cat "$f" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# 7. Diagnose mode main flow
# ---------------------------------------------------------------------------
if [[ "${MODE}" == "diagnose" ]]; then
  ROOT_CAUSE="${HANDOFF}/root-cause.md"

  resolver_out="$(resolve_plan_pool_call)"
  pool="$(printf '%s\n' "${resolver_out}" | sed -n 's/^pool=//p' | head -n1)"
  refusal="$(printf '%s\n' "${resolver_out}" | sed -n 's/^refusal=//p' | head -n1)"

  fanout_list=()
  while IFS= read -r _arm; do
    [[ -n "${_arm}" ]] || continue
    fanout_list+=("${_arm}")
    [[ "${#fanout_list[@]}" -ge "${PLAN_FANOUT}" ]] && break
  done < <(_engine_pool_ok_arms)

  if [[ "${#fanout_list[@]}" -eq 0 ]]; then
    if [[ -n "${planner}" ]]; then
      fanout_list=("${planner}")
    else
      emit decision "diagnose_run task=${TASK} status=blocked reason=all_plan_arms_unavailable"
      write_gate "blocked" "all_plan_arms_unavailable" "-" "skipped"
      exit 9
    fi
  fi

  # Build diagnose-specific input — no persona-engine constants (design §2.2).
  _diag_input=""
  if [[ -n "${LOG_PATH}" && -f "${LOG_PATH}" ]]; then
    _diag_input="$(tail -100 "${LOG_PATH}" 2>/dev/null || true)"
  fi
  [[ -n "${DIFF_PATHS}" ]] && _diag_input="${_diag_input}\nDiff paths: ${DIFF_PATHS}"

  # Sequential: architect first.
  _first_arm="${fanout_list[0]}"
  _engine_run_arm_with_timeout "${_first_arm}" "architect"

  _first_rc="$(cat "${HANDOFF}/plan-arm-${_first_arm}.rc" 2>/dev/null || printf '1')"
  _first_err="${HANDOFF}/plan-arm-${_first_arm}.err"
  _first_out="${HANDOFF}/plan-arm-${_first_arm}.yaml"
  _cls="$(classify_arm_failure "${_first_rc}" "${_first_err}" "${_first_out}")"

  ran_arm=""
  if [[ "${_cls}" == "ran" ]]; then
    ran_arm="${_first_arm}"
  elif [[ "${_cls}" == "arm_unavailable" ]]; then
    emit decision "diagnose_run arm_unavailable arm=${_first_arm} reason=policy task=${TASK}"
    # Try next arm
    _next_arm="$(next_ok_arm_after "${_first_arm}" || true)"
    if [[ -n "${_next_arm}" ]]; then
      _engine_run_arm_with_timeout "${_next_arm}" "architect"
      _next_rc="$(cat "${HANDOFF}/plan-arm-${_next_arm}.rc" 2>/dev/null || printf '1')"
      _next_err="${HANDOFF}/plan-arm-${_next_arm}.err"
      _next_out="${HANDOFF}/plan-arm-${_next_arm}.yaml"
      _cls2="$(classify_arm_failure "${_next_rc}" "${_next_err}" "${_next_out}")"
      if [[ "${_cls2}" == "ran" ]]; then
        ran_arm="${_next_arm}"
      fi
    fi
  fi

  if [[ -z "${ran_arm}" ]]; then
    if [[ "${_first_rc}" -ne 0 ]]; then
      emit decision "diagnose_run task=${TASK} status=blocked reason=provider_error"
      write_gate "blocked" "provider_error" "-" "skipped"
    else
      emit decision "diagnose_run task=${TASK} status=blocked reason=empty_response"
      write_gate "blocked" "empty_response" "-" "skipped"
    fi
    exit 9
  fi

  # Read the diagnose artifact from disk (not stdout — §3.3 artifact discipline).
  _diag_artifact="${HANDOFF}/plan-arm-${ran_arm}.yaml"
  [[ -s "${_diag_artifact}" ]] || _diag_artifact="${HANDOFF}/plan-arm-${ran_arm}.md"

  # Validate: root_cause and confidence must be present and non-empty.
  _has_root_cause="$(python3 -c '
import yaml, sys
try:
    doc = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print("0"); sys.exit(0)
rc = doc.get("root_cause")
conf = doc.get("confidence")
if rc and str(rc).strip() and conf and str(conf).strip():
    print("1")
else:
    print("0")
' "${_diag_artifact}" 2>/dev/null)" || _has_root_cause="0"

  if [[ "${_has_root_cause}" != "1" ]]; then
    emit decision "diagnose_run task=${TASK} status=blocked reason=empty_response arm=${ran_arm}"
    write_gate "blocked" "empty_response" "${ran_arm}" "skipped"
    exit 9
  fi

  # Copy to canonical output name.
  cp -f "${_diag_artifact}" "${ROOT_CAUSE}"
  emit decision "diagnose_run task=${TASK} status=ran arm=${ran_arm}"
  write_gate "pass" "ok" "${ran_arm}" "skipped"
  exit 0
fi

# ---------------------------------------------------------------------------
# 8. Plan/Prepass mode — skeleton write BEFORE arm dispatch (R1, R3)
#    authored_at is stamped HERE, before any code is written by an arm, so
#    assert-precedence can never fail on a legitimate plan.
# ---------------------------------------------------------------------------
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf 'id: %s\n' "dispatch-${TASK}"
  printf 'mission: |\n'
  printf '%s\n' "${MISSION_TEXT}" | sed 's/^/  /'
  printf 'reads: []\n'
  printf 'writes: [%s]\n' "${WRITES_CSV}"
  if [[ -n "${WRITES_CSV}" ]]; then
    printf 'lane_writes: %s\n' "${WRITES_CSV}"
  else
    printf 'lane_writes: []\n'
  fi
  printf 'acceptance:\n'
  printf '  authored_at: %s\n' "${NOW_ISO}"
} > "${CONTEXT_YAML}.skeleton"
mv -f "${CONTEXT_YAML}.skeleton" "${CONTEXT_YAML}"

# ---------------------------------------------------------------------------
# 9. Pool resolution + fan-out for plan/prepass
# ---------------------------------------------------------------------------
resolver_out="$(resolve_plan_pool_call)"
pool="$(printf '%s\n' "${resolver_out}" | sed -n 's/^pool=//p' | head -n1)"
refusal="$(printf '%s\n' "${resolver_out}" | sed -n 's/^refusal=//p' | head -n1)"
# The resolver emits reviewer= (or planner=) for the first eligible arm. Used
# as a fallback when no :ok: arm exists in the pool (unknown-quota arms are
# admitted as the terminal arm — mirroring leadv2-review-run.sh:467-471).
planner="$(printf '%s\n' "${resolver_out}" | sed -nE 's/^(reviewer|planner)=//p' | head -n1)"

case "${refusal}" in
  resolver_missing_failclosed|resolver_error_failclosed)
    emit decision "plan_run task=${TASK} status=blocked reason=${refusal}"
    write_gate "blocked" "${refusal}" "-" "skipped"
    # M7: stamp cache so a byte-identical retry does not re-pay the architect.
    printf '%s' "${MISSION_SIG}" > "${HANDOFF}/context.yaml.sig" 2>/dev/null || true
    exit 9
    ;;
esac

fanout_list=()
while IFS= read -r _arm; do
  [[ -n "${_arm}" ]] || continue
  fanout_list+=("${_arm}")
  [[ "${#fanout_list[@]}" -ge "${PLAN_FANOUT}" ]] && break
done < <(_engine_pool_ok_arms)

if [[ "${#fanout_list[@]}" -eq 0 ]]; then
  if [[ -n "${planner}" ]]; then
    fanout_list=("${planner}")
  else
    emit decision "plan_run task=${TASK} status=blocked reason=all_plan_arms_unavailable"
    write_gate "blocked" "all_plan_arms_unavailable" "-" "skipped"
    printf '%s' "${MISSION_SIG}" > "${HANDOFF}/context.yaml.sig" 2>/dev/null || true
    exit 9
  fi
fi

# A4 dedup guard — iterate WITHOUT ${arr[@]:-} (bash-3.2 quirk that expands
# to ONE empty-string word on a zero-element array, false-positiving "duplicate ''").
_dedup_check=""
for _arm in "${fanout_list[@]}"; do
  case ",${_dedup_check}," in
    *",${_arm},") printf 'leadv2-plan-run.sh: INTERNAL: duplicate arm %s in fan-out\n' "${_arm}" >&2; exit 2 ;;
  esac
  _dedup_check="${_dedup_check},${_arm}"
done

# ---------------------------------------------------------------------------
# 10. Architect pass
# ---------------------------------------------------------------------------
_first_arm="${fanout_list[0]}"
_engine_run_arm_with_timeout "${_first_arm}" "architect"

_first_rc="$(cat "${HANDOFF}/plan-arm-${_first_arm}.rc" 2>/dev/null || printf '1')"
_first_err="${HANDOFF}/plan-arm-${_first_arm}.err"
_first_out="${HANDOFF}/plan-arm-${_first_arm}.yaml"
_cls="$(classify_arm_failure "${_first_rc}" "${_first_err}" "${_first_out}")"

architect_arm=""
if [[ "${_cls}" == "ran" ]]; then
  architect_arm="${_first_arm}"
elif [[ "${_cls}" == "arm_unavailable" ]]; then
  emit decision "plan_run arm_unavailable arm=${_first_arm} reason=policy task=${TASK}"
  _next_arm="$(next_ok_arm_after "${_first_arm}" || true)"
  if [[ -n "${_next_arm}" ]]; then
    _engine_run_arm_with_timeout "${_next_arm}" "architect"
    _next_rc="$(cat "${HANDOFF}/plan-arm-${_next_arm}.rc" 2>/dev/null || printf '1')"
    _next_err="${HANDOFF}/plan-arm-${_next_arm}.err"
    _next_out="${HANDOFF}/plan-arm-${_next_arm}.yaml"
    _cls2="$(classify_arm_failure "${_next_rc}" "${_next_err}" "${_next_out}")"
    if [[ "${_cls2}" == "ran" ]]; then
      architect_arm="${_next_arm}"
    fi
  fi
fi

if [[ -z "${architect_arm}" ]]; then
  if [[ "${_first_rc}" -ne 0 ]]; then
    emit decision "plan_run task=${TASK} status=blocked reason=provider_error rc=${_first_rc}"
    write_gate "blocked" "provider_error" "-" "skipped"
  else
    emit decision "plan_run task=${TASK} status=blocked reason=empty_response"
    write_gate "blocked" "empty_response" "-" "skipped"
  fi
  printf '%s' "${MISSION_SIG}" > "${HANDOFF}/context.yaml.sig" 2>/dev/null || true
  exit 9
fi

# Body persistence guard (REVIEW-BODY-PERSIST-01 port): arm ran (rc=0) but
# artifact body is missing → blocked, never silent pass.
_arch_out="${HANDOFF}/plan-arm-${architect_arm}.yaml"
_arch_bytes="$(wc -c < "${_arch_out}" 2>/dev/null | tr -d '[:space:]')"; _arch_bytes="${_arch_bytes:-0}"
if [[ "${_arch_bytes}" -lt 50 ]]; then
  emit decision "plan_run task=${TASK} status=blocked reason=body_lost arm=${architect_arm}"
  write_gate "blocked" "body_lost" "${architect_arm}" "skipped"
  printf '%s' "${MISSION_SIG}" > "${HANDOFF}/context.yaml.sig" 2>/dev/null || true
  exit 9
fi

ran_arms_csv="${architect_arm}"

# ---------------------------------------------------------------------------
# 11. Critic pass — SKIPPED in prepass mode (design §2.1 step 7).
#     In plan mode, run on a different arm where the pool allows.
# ---------------------------------------------------------------------------
if [[ "${MODE}" != "prepass" ]]; then
  _critic_arm="$(next_ok_arm_after "${architect_arm}" || true)"
  if [[ -z "${_critic_arm}" ]]; then
    _critic_arm="${architect_arm}"
  fi
  _engine_run_arm_with_timeout "${_critic_arm}" "critic"
  emit decision "plan_run task=${TASK} status=ran arm=${architect_arm} critic=${_critic_arm}"
  ran_arms_csv="${architect_arm},${_critic_arm}"
else
  emit decision "plan_run task=${TASK} status=ran arm=${architect_arm} critic=skipped_prepass"
fi

# Determine primary judgment source — prefer critic's revised block if present.
_primary_out="${HANDOFF}/plan-arm-${_critic_arm:-${architect_arm}}-critic.yaml"
if [[ ! -s "${_primary_out}" || "$(wc -c < "${_primary_out}" | tr -d '[:space:]')" -lt 50 ]]; then
  _primary_out="${HANDOFF}/plan-arm-${architect_arm}.yaml"
fi

# ---------------------------------------------------------------------------
# 12. Merge — extract PLAN_YAML, overlay judgment keys, engine-owned keys win.
#     Uses leadv2-context-merge.py which discards engine-owned keys from arm
#     drafts and checks REQUIRED_FIELDS.
# ---------------------------------------------------------------------------
_merge_py="${SCRIPT_DIR}/lib/leadv2-context-merge.py"
_merge_canonical="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-context-merge.py"
[[ -f "${_merge_py}" ]] || _merge_py="${_merge_canonical}"

# Extract PLAN_YAML blocks from arm outputs into clean YAML files for the merger.
_arm_drafts=""
_extracted="${HANDOFF}/.plan-extracted-architect.yaml"
extract_plan_yaml "${HANDOFF}/plan-arm-${architect_arm}.yaml" > "${_extracted}" 2>/dev/null || true
if [[ -s "${_extracted}" ]]; then
  _arm_drafts="${_extracted}"
fi

if [[ "${MODE}" != "prepass" && -n "${_critic_arm:-}" ]]; then
  _extracted_critic="${HANDOFF}/.plan-extracted-critic.yaml"
  _critic_file="${HANDOFF}/plan-arm-${_critic_arm}-critic.yaml"
  if [[ -s "${_critic_file}" ]]; then
    extract_plan_yaml "${_critic_file}" > "${_extracted_critic}" 2>/dev/null || true
    if [[ -s "${_extracted_critic}" ]]; then
      _arm_drafts="${_arm_drafts} ${_extracted_critic}"
    fi
  fi
fi

# validate_and_merge: returns 0 on success, 1 on failure.
# Sets VALIDATE_REASON on failure for the retry path.
VALIDATE_REASON=""
validate_and_merge() {
  local out_ctx="${CONTEXT_YAML}"
  local -a merge_args=(--skeleton "${out_ctx}" --out "${out_ctx}.merged")
  local d
  for d in ${_arm_drafts}; do
    merge_args+=(--arm "${d}")
  done

  if python3 "${_merge_py}" "${merge_args[@]}" 2>"${HANDOFF}/.merge-err"; then
    mv -f "${out_ctx}.merged" "${out_ctx}"
  else
    VALIDATE_REASON="required_fields_missing"
    return 1
  fi

  # Validate with the REAL validator (design §2.1 step 9b).
  if bash "${SCRIPT_DIR}/leadv2-acceptance-shape.sh" validate "${out_ctx}" 2>"${HANDOFF}/.validate-err"; then
    : # validation passed
  else
    if [[ "${LEADV2_REQUIRE_ACCEPTANCE:-1}" == "0" ]]; then
      : # gate flag disabled — don't block
    else
      VALIDATE_REASON="acceptance_invalid"
      return 1
    fi
  fi

  # assert-precedence when lane_writes names existing files (design §2.1 step 9c).
  local has_existing=0 _w _w_trimmed
  for _w in ${WRITES_CSV//,/ }; do
    _w_trimmed="$(printf '%s' "${_w}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "${_w_trimmed}" && -f "${ROOT}/${_w_trimmed}" ]] && has_existing=1 && break
  done
  if [[ "${has_existing}" == "1" ]]; then
    if ! bash "${SCRIPT_DIR}/leadv2-acceptance-shape.sh" assert-precedence --task-id "${TASK}" --context "${out_ctx}" 2>"${HANDOFF}/.precedence-err"; then
      VALIDATE_REASON="precedence_violated"
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# 13. Validate — exactly one retry on failure (design §2.1 step 10)
# ---------------------------------------------------------------------------
ACCEPTANCE_VERDICT="valid"
if validate_and_merge; then
  : # success
else
  emit decision "plan_run task=${TASK} status=retrying reason=${VALIDATE_REASON}"

  # Retry: re-dispatch architect on next ok arm with failure reasons appended.
  _retry_arm="$(next_ok_arm_after "${architect_arm}" || true)"
  [[ -n "${_retry_arm}" ]] || _retry_arm="${architect_arm}"

  _retry_reason="$(cat "${HANDOFF}/.merge-err" "${HANDOFF}/.validate-err" "${HANDOFF}/.precedence-err" 2>/dev/null | head -20)"
  {
    printf '\n\n--- RETRY: previous attempt failed validation. Fix these issues: ---\n'
    printf '%s\n' "${_retry_reason}"
    printf '\nRe-emit the complete judgment block with these issues fixed.\n'
  } >> "${HANDOFF}/plan-arm-${_retry_arm}.mission"

  _engine_run_arm_with_timeout "${_retry_arm}" "architect"
  _retry_out="${HANDOFF}/plan-arm-${_retry_arm}.yaml"

  # Update drafts to use retry output.
  if [[ -s "${_retry_out}" ]]; then
    extract_plan_yaml "${_retry_out}" > "${_extracted}" 2>/dev/null || true
    _arm_drafts="${_extracted}"
    if validate_and_merge; then
      : # retry succeeded
    else
      ACCEPTANCE_VERDICT="invalid"
      emit decision "plan_run task=${TASK} status=failed reason=${VALIDATE_REASON}"
      write_gate "fail" "${VALIDATE_REASON}" "${ran_arms_csv}" "${ACCEPTANCE_VERDICT}"
      exit 7
    fi
  else
    ACCEPTANCE_VERDICT="invalid"
    emit decision "plan_run task=${TASK} status=failed reason=acceptance_invalid"
    write_gate "fail" "acceptance_invalid" "${ran_arms_csv}" "${ACCEPTANCE_VERDICT}"
    exit 7
  fi
fi

# ---------------------------------------------------------------------------
# 14. Success — stamp cache sig (M7), write gate
# ---------------------------------------------------------------------------
printf '%s' "${MISSION_SIG}" > "${HANDOFF}/context.yaml.sig" 2>/dev/null || true

emit decision "plan_run task=${TASK} status=pass reason=ok mode=${MODE} arms=${ran_arms_csv}"
write_gate "pass" "ok" "${ran_arms_csv}" "${ACCEPTANCE_VERDICT}"
exit 0
