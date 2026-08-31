#!/usr/bin/env bash
# leadv2-review-run.sh — ONE-PATH-EVERYWHERE-01: sole-owner review engine.
#
# WRITE-RACE NOTE (risk A1): this engine writes docs/handoff/<task>/review-gate.md via
# `.tmp` + `mv` (atomic). The lane's own EXIT trap (leadv2-dispatch-product-close.sh)
# only writes review-gate.md when the file is ABSENT — it is a fallback-only writer.
# Ordering is therefore: this engine writes FIRST; the lane's trap only fires if the
# engine crashed before writing anything at all. There is no second writer racing this
# one under normal operation.
#
# OWNERSHIP: this script is self-contained. It does NOT source the lane
# (leadv2-dispatch-product-close.sh) and never calls the lane's _stamp_review_terminal,
# _dl_note, or its journal `emit` — those remain lane-owned; the lane wraps this call
# with its own process model / EXIT trap / terminal-state stamping. This is what makes
# the engine callable from a bare bash session (e.g. a Codex-led session) with none of
# the lane's helper functions loaded.
#
# DEVIATION NOTE: resolve_review_pool_call() below is lifted verbatim from the lane
# (including its one `emit decision ...` observability line), but this file defines
# its OWN minimal `emit()` — a stderr-only logger — instead of depending on the lane's
# journal emit. This keeps the lifted function's body byte-identical while honoring the
# "never call the lane's emit" rule above.
#
# FLAG: LEADV2_REVIEW_ENGINE gates whether the LANE calls this script (default 0, must
# stay 0 in production per ONE-PATH-EVERYWHERE-01 rollout). This script itself carries
# no internal flag — once invoked, it always runs its full pipeline. The lead/interactive
# skill path calls it unconditionally (design §5), independent of the lane's flag.
#
# REVIEW-ROUNDCAP-01: the engine now enforces the declared "max 2 rounds then
# architect escape" policy itself instead of leaving it to the (LLM) lead's
# judgement — docs/phases.md's old "Round cap is enforced by LEAD, not the
# engine" line is superseded. LEADV2_REVIEW_MAX_ROUNDS (default 2, 0=unlimited)
# refuses a further round with exit 8 once .review-round.state's attempts
# counter reaches the limit. NOT COVERED: leadv2-dispatch-product-close.sh's
# inline review body used at LEADV2_REVIEW_ENGINE=0 (the production default)
# never calls this engine, so it is not capped by this change.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2329 # begin/end stubs kept for load-stanza parity with the other 8 trace call sites; this file only calls arm_exit
if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${SCRIPT_DIR}/lib/leadv2-trace.sh"
else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi

# REVIEW-GATE-SHOWS-FINDINGS-01: shared findings renderer, appended to review-gate.md
# at the fail/pass exits below. Guarded source + no-op stub so a missing/broken
# renderer degrades to today's exact gate output, never to a missing gate (design R3).
_REVIEW_FINDINGS_SH="${SCRIPT_DIR}/leadv2-review-findings.sh"
[[ -f "${_REVIEW_FINDINGS_SH}" ]] || _REVIEW_FINDINGS_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-review-findings.sh"
# shellcheck source=leadv2-review-findings.sh
[[ -f "${_REVIEW_FINDINGS_SH}" ]] && source "${_REVIEW_FINDINGS_SH}"
command -v render_gate_findings >/dev/null 2>&1 || render_gate_findings() { :; }

# REVIEW-ROUNDCAP-01 fix-round-1 H1: the attempts/spawns read-modify-write below needs the
# same cross-process lock the sibling diff-hash ledger uses
# (leadv2-dispatch-code.sh:2570 atomic_review_check_and_record). Guarded source + no-op
# stub, mirroring _REVIEW_FINDINGS_SH above: this script stays self-contained, and a
# missing lib degrades to today's unlocked behaviour rather than killing the engine.
_REVIEW_LOCK_SH="${SCRIPT_DIR}/leadv2-portable-lock.sh"
# shellcheck source=leadv2-portable-lock.sh
[[ -f "${_REVIEW_LOCK_SH}" ]] && source "${_REVIEW_LOCK_SH}"
if ! declare -F lv2_lock_wait >/dev/null 2>&1; then
  lv2_lock_wait() { return 0; }   # lib absent -> proceed unlocked (today's behaviour)
fi

# ---------------------------------------------------------------------------
# 1. Arg parsing
# ---------------------------------------------------------------------------
TASK=""; ROOT=""; HANDOFF=""; DIFF_FILE=""; AUTHOR=""; FANOUT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK="${2:-}"; shift 2 ;;
    --root)    ROOT="${2:-}"; shift 2 ;;
    --handoff) HANDOFF="${2:-}"; shift 2 ;;
    --diff)    DIFF_FILE="${2:-}"; shift 2 ;;
    --author)  AUTHOR="${2:-}"; shift 2 ;;
    --fanout)  FANOUT_ARG="${2:-}"; shift 2 ;;
    *) printf 'leadv2-review-run.sh: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${TASK}" || -z "${ROOT}" || -z "${HANDOFF}" || -z "${DIFF_FILE}" || -z "${AUTHOR}" ]]; then
  printf 'leadv2-review-run.sh: --task, --root, --handoff, --diff and --author are all required\n' >&2
  exit 2
fi

if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then
  LEADV2_TRACE_ID="${LEADV2_TRACE_ID:-${TASK}}"
  export LEADV2_TRACE_ID
fi
lv2_trace_arm_exit "review"

# V3 core: one independent review is the ordinary path. Wider fan-out remains
# an explicit override for callers that need it.
REVIEW_FANOUT="${FANOUT_ARG:-${LEADV2_REVIEW_FANOUT:-1}}"
[[ "${REVIEW_FANOUT}" =~ ^[1-9][0-9]*$ ]] || REVIEW_FANOUT=1

mkdir -p "${HANDOFF}" 2>/dev/null || true

# Engine-local logger. See DEVIATION NOTE above — the lane's real journal `emit` is
# never called from this file.
emit() { printf '[leadv2-review-run] %s %s\n' "${1:-}" "${2:-}" >&2; }

WRITES_CSV="${LEADV2_DISPATCH_LANE_WRITES:-}"

# Risk selection happens in this shell. resolve_review_pool_call runs in a
# command substitution below, so sourcing there would not make its functions
# available to the security-pass decision. Missing or unloadable signals are a
# fail-closed condition: run the security pass rather than silently skip it.
REVIEW_SIGNALS_STATUS="missing"
_REVIEW_SIGNALS_LIB="${SCRIPT_DIR}/lib/leadv2-review-signals.sh"
[[ -f "${_REVIEW_SIGNALS_LIB}" ]] || _REVIEW_SIGNALS_LIB="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-review-signals.sh"
# shellcheck source=lib/leadv2-review-signals.sh
# shellcheck disable=SC1090 # canonical fallback is intentionally runtime-selected
if [[ -f "${_REVIEW_SIGNALS_LIB}" ]] && source "${_REVIEW_SIGNALS_LIB}" && declare -F leadv2_review_signals >/dev/null 2>&1; then
  REVIEW_SIGNALS_STATUS="ready"
fi

# ---------------------------------------------------------------------------
# 2. Pool resolution — lifted verbatim from leadv2-dispatch-product-close.sh
#    (dispatch-00629379 / CODEX-GATE-01 item 6 / N-5 D5). See that file's own
#    comments at resolve_review_pool_call() for the full incident history; do
#    not re-derive the fail-closed signals contract here.
# ---------------------------------------------------------------------------
resolve_review_pool_call() {
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
    printf 'reviewer=\npool=\nrefusal=resolver_missing_failclosed\n'
    return
  fi
  local routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"
  local _signals_json='{"protected_path":true,"safety_touched":true}'
  local _signals_lib="${SCRIPT_DIR}/lib/leadv2-review-signals.sh"
  local _sig_source="lib_missing_failclosed" _sig_protected="1" _sig_matched="-"
  if [[ -f "${_signals_lib}" ]]; then
    # shellcheck source=lib/leadv2-review-signals.sh
    source "${_signals_lib}"
    local _sig_cap
    _sig_cap="$(mktemp "${TMPDIR:-/tmp}/leadv2-rev-sig.XXXXXX" 2>/dev/null || printf '%s/leadv2-rev-sig.%s' "${TMPDIR:-/tmp}" "$$")"
    _signals_json="$(leadv2_review_signals "${routing_yaml}" "${WRITES_CSV}" 2>"${_sig_cap}" || true)"
    _sig_source="$(sed -n 's/^signals_source=//p' "${_sig_cap}" | head -n1)"
    _sig_matched="$(sed -n 's/^signals_matched=//p' "${_sig_cap}" | head -n1)"
    rm -f "${_sig_cap}" 2>/dev/null || true
    [[ -n "${_sig_source}" ]] || _sig_source="lib_missing_failclosed"
    [[ -n "${_sig_matched}" ]] || _sig_matched="-"
    case "${_signals_json}" in
      *'"protected_path":false'*) _sig_protected="0" ;;
      *) _sig_protected="1" ;;
    esac
  fi
  emit decision "review_signals task=${TASK} protected_path=${_sig_protected} source=${_sig_source} matched=${_sig_matched}"
  local -a resolver_args=(--routing-yaml "${routing_yaml}" --job review --base-arm codex \
    --review-pool --author "${AUTHOR}" --signals "${_signals_json}")
  [[ -n "${GLM_POLICY_QUOTA_LIVE:-}" ]] && resolver_args+=(--quota-live "${GLM_POLICY_QUOTA_LIVE}")
  # FP-07B-POOL-PARSE-01: A2 parity with the close-gate copy (the lane's
  # resolve_review_pool_call since dispatch-8e2a32be). The old tail here --
  # `2>/dev/null || printf fallback` -- threw the resolver's stderr away and, on
  # any hard-fail path (argparse exit 2, python missing), left `pool=` EMPTY
  # while the run continued, so the FP-07 body-lost retry silently had zero
  # candidates (live 2026-08-28, FP-03 review: resolver stdout was gate-shape
  # arm=/rule= lines only). stderr now lands in a per-lane artifact, the rc is
  # journaled, and a stdout carrying NO pool= line at all can never parse as a
  # successful empty pool -- it fails closed with a named refusal.
  local _resolver_err_file="${HANDOFF}/review-pool-resolver.err"
  local _resolver_out _resolver_rc
  mkdir -p "${HANDOFF}" 2>/dev/null || true
  _resolver_out="$(python3 "${resolver}" "${resolver_args[@]}" 2>"${_resolver_err_file}")"
  _resolver_rc=$?
  if ! printf '%s\n' "${_resolver_out}" | grep -q '^pool='; then
    _resolver_out=$'reviewer=\npool=\nrefusal=resolver_error_failclosed'
  fi
  emit decision "review_pool_resolver task=${TASK} rc=${_resolver_rc} stderr=${_resolver_err_file#"${ROOT}"/}"
  # The caller captures THIS function's stdout as resolver_out -- the original
  # tail passed python's stdout straight through; the buffer must be re-printed.
  printf '%s\n' "${_resolver_out}"
}

# ---------------------------------------------------------------------------
# 3. Reviewer artifact / verdict parsing — lifted verbatim (same contract the
#    lane's parser already tolerates unknown additive lines like arms:/verified:).
# ---------------------------------------------------------------------------
resolve_review_artifact() { # <arm> -> sets REVIEW_ARTIFACT/REVIEW_SOURCE
  local arm="$1"
  local adir="${ROOT}/docs/handoff/dispatch-${TASK}-review" cand
  REVIEW_ARTIFACT=""
  REVIEW_SOURCE=""
  for cand in "${adir}/critic.full.md" "${adir}/critic.md" "${adir}/critic.summary.md"; do
    if [[ -s "${cand}" && "${cand}" -nt "${REVIEW_STAMP}" ]]; then
      REVIEW_ARTIFACT="${cand}"
      REVIEW_SOURCE="artifact:${cand#"${ROOT}/"}"
      return 0
    fi
  done
  return 1
}

materialize_subsession_body() { # <review_out> <review_stamp> <task_id>
  local rfile="$1" rstamp="$2" tid="$3"
  local adir="${ROOT}/docs/handoff/dispatch-${tid}-review"
  local cand body_file="" rel_path=""

  for cand in "${adir}/critic.full.md" "${adir}/critic.md" "${adir}/critic.summary.md"; do
    if [[ -s "${cand}" && "${cand}" -nt "${rstamp}" ]]; then
      body_file="${cand}"
      rel_path="${cand#"${ROOT}/"}"
      break
    fi
  done

  if [[ -z "${body_file}" ]]; then
    local stream="${adir}/critic.stream.jsonl"
    if [[ -s "${stream}" && "${stream}" -nt "${rstamp}" ]] && command -v python3 >/dev/null 2>&1; then
      local tmp_body
      tmp_body="$(python3 - "$stream" 2>/dev/null <<'PY'
import json, sys
texts = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("type") == "assistant":
        msg = obj.get("message", {})
        for block in msg.get("content", []):
            if isinstance(block, dict) and block.get("type") == "text":
                texts.append(block.get("text", ""))
if texts:
    print(texts[-1])
PY
      )"
      if [[ -n "${tmp_body}" ]]; then
        local label_line
        label_line="$(cat "${rfile}" 2>/dev/null)"
        printf '%s\n--- body from: %s ---\n%s\n' "${label_line}" "${stream#"${ROOT}/"}" "${tmp_body}" > "${rfile}"
        return 0
      fi
    fi
    return 1
  fi

  local label_line
  label_line="$(cat "${rfile}" 2>/dev/null)"
  printf '%s\n--- body from: %s ---\n' "${label_line}" "${rel_path}" > "${rfile}.tmp"
  cat "${body_file}" >> "${rfile}.tmp"
  mv "${rfile}.tmp" "${rfile}"
  return 0
}

# The Claude CLI's --output-format json writes an envelope whose human answer is
# in `result`.  glm-coder deliberately preserves that envelope for its generic
# callers, but a review artifact must expose the review contract at top level so
# the gate can parse REVIEW_VERDICT/REVIEW_FINDINGS.  Materialize only a valid
# successful envelope; leave malformed or non-JSON output untouched for the
# existing body-lost guard to fail closed.
materialize_glm_review_body() { # <review_out>
  local rfile="$1" body
  command -v python3 >/dev/null 2>&1 || return 1
  body="$(python3 - "$rfile" 2>/dev/null <<'PY'
import json, sys
try:
    raw = open(sys.argv[1], encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(1)
for line in reversed(raw):
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    result = obj.get("result")
    if obj.get("is_error") is False and isinstance(result, str) and result.strip():
        print(result)
        break
PY
  )"
  [[ -n "${body}" ]] || return 1
  printf '%s\n' "${body}" > "${rfile}.tmp"
  mv "${rfile}.tmp" "${rfile}"
}

parse_review_verdict() { # review-file
  local review_file="$1"
  PARSED_VERDICT=""
  VERDICT_SOURCE=""
  FINDINGS_CRITICAL=0
  FINDINGS_HIGH=0
  FINDINGS_MEDIUM=0
  FINDINGS_LOW=0

  PARSED_VERDICT="$(sed -nE 's/^[[:space:]]*REVIEW_VERDICT:[[:space:]]*(FAIL|PASS_WITH_NITS|PASS)([[:space:]]|$).*/\1/p' "${review_file}" | head -n 1)"
  if [[ -n "${PARSED_VERDICT}" ]]; then
    VERDICT_SOURCE="marker"
  else
    PARSED_VERDICT="$(sed -nE 's/^[[:space:]]*(VERDICT|Verdict):[[:space:]]*(FAIL|PASS_WITH_NITS|PASS)([[:space:]]|$).*/\2/p' "${review_file}" | head -n 1)"
    [[ -n "${PARSED_VERDICT}" ]] && VERDICT_SOURCE="alt_marker"
  fi
  [[ -n "${PARSED_VERDICT}" ]] || return 1

  local findings_matches findings_count
  findings_matches="$(sed -nE 's/^[[:space:]]*REVIEW_FINDINGS:[[:space:]]*critical=([0-9]+)[[:space:]]+high=([0-9]+)[[:space:]]+medium=([0-9]+)[[:space:]]+low=([0-9]+)[[:space:]]*$/\1 \2 \3 \4/p' "${review_file}")"
  findings_count="$(printf '%s\n' "${findings_matches}" | grep -c .)"
  if [[ "${findings_count}" -ne 1 ]]; then
    PARSED_VERDICT=""
    return 1
  fi
  read -r FINDINGS_CRITICAL FINDINGS_HIGH FINDINGS_MEDIUM FINDINGS_LOW <<< "${findings_matches}"
  if [[ "${PARSED_VERDICT}" != FAIL && ( ${FINDINGS_CRITICAL} -gt 0 || ${FINDINGS_HIGH} -gt 0 ) ]]; then
    PARSED_VERDICT=FAIL
    VERDICT_SOURCE="contradiction_override"
  fi
}

review_floor_ok() { # <file> -> 0 if it clears the floor, 1 if not
  local f="$1"
  local min_bytes="${LEADV2_REVIEW_MIN_BYTES:-200}"
  if grep -q '^[[:space:]]*REVIEW_VERDICT:' "${f}" 2>/dev/null && \
     grep -q '^[[:space:]]*REVIEW_FINDINGS:' "${f}" 2>/dev/null; then
    return 0
  fi
  local bytes lines
  bytes="$(wc -c < "${f}" 2>/dev/null | tr -d '[:space:]')"; bytes="${bytes:-0}"
  lines="$(wc -l < "${f}" 2>/dev/null | tr -d '[:space:]')"; lines="${lines:-0}"
  if [[ "${bytes}" -lt "${min_bytes}" || "${lines}" -lt 3 ]]; then
    return 1
  fi
  return 0
}

# _review_resolve_codex_base -> echoes a rev to diff FROM on stdout, rc0. rc1 when
# no usable base resolves (caller must refuse rather than hand codex a bare `HEAD`
# that would silently review nothing on an already-committed lane -- the exact
# mechanism this function exists to avoid; see REVIEW-CODEX-EMPTY-BASE-01 below).
#
# REVIEW-CODEX-EMPTY-BASE-01: codex's own `--base HEAD` used to diff the lane's
# CURRENT HEAD against itself once the lane had already committed its work --
# collectReviewContext (codex-companion's lib/git.mjs resolveReviewTarget) treats
# an explicit --base as authoritative and never falls back to working-tree mode,
# so a committed lane always got an empty branch diff from codex, a short/empty
# stdout, and the REVIEW-BODY-PERSIST-01 guard downstream (left untouched by this
# fix, per design) then correctly declared review_body_lost because codex ALWAYS
# writes its `[codex-task] tier=...` banner to stderr regardless of whether the
# review body itself was real.
#
# This mirrors leadv2-dispatch-product-close.sh's _pc_diff_base exactly (same
# two-candidate resolution: the lane's recorded start SHA first, origin/main
# second) rather than re-deriving root/ancestry arithmetic here -- ROOT is this
# engine's own --root arg (already resolved by the caller, never counted via
# `../` hops), and LEADV2_LANE_START_SHA is an env var this process already
# inherits from leadv2-dispatch-code.sh's spawn_product_close (which exports it
# to leadv2-dispatch-product-close.sh, whose own child-process env -- this
# engine included -- inherits it for free; no cross-file wiring needed).
#
# Degenerate-environment guard: if ROOT is not inside a git working tree at all
# (a bare fixture tempdir, not a production lane worktree), there is no git
# ancestry to resolve -- fall back to the OLD literal "HEAD" rather than
# refusing outright, so this function only ever REFUSES (rc1) when ROOT genuinely
# is a git repo but no usable merge-base exists in it. This keeps the refusal
# path scoped to the real Fault B scenario (a committed lane in a real repo)
# instead of firing on any caller that hands this engine a non-repo directory.
_review_resolve_codex_base() {
  if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'HEAD'
    return 0
  fi
  local sha="${LEADV2_LANE_START_SHA:-}" base
  if [[ -n "${sha}" ]] && git -C "${ROOT}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    base="$(git -C "${ROOT}" merge-base "${sha}" HEAD 2>/dev/null || true)"
    if [[ -n "${base}" ]]; then
      printf '%s' "${base}"
      return 0
    fi
  fi
  if git -C "${ROOT}" cat-file -e "origin/main^{commit}" 2>/dev/null; then
    base="$(git -C "${ROOT}" merge-base origin/main HEAD 2>/dev/null || true)"
    if [[ -n "${base}" ]]; then
      printf '%s' "${base}"
      return 0
    fi
  fi
  return 1
}

# ---------------------------------------------------------------------------
# 4. run_reviewer_arm — lifted verbatim (KIMI-CHANNEL-01b §2.3.1-2.3.2 /
#    dispatch-00629379). One behaviour change from the lane copy: output/err
#    filenames are keyed per fan-out slot (arm name is already unique per
#    fan-out by construction — see the dedup guard in step 6 below), so
#    parallel jobs never collide on the same review-${arm}.md/.err pair.
# ---------------------------------------------------------------------------
run_reviewer_arm() { # <arm>
  local arm="$1"
  review_out="${HANDOFF}/review-${arm}.md"
  review_err="${HANDOFF}/review-${arm}.err"
  mission_file="${HANDOFF}/review-mission-${arm}.md"
  if [[ "${arm}" == codex ]]; then
    local codex_base
    if ! codex_base="$(_review_resolve_codex_base)"; then
      emit decision "review_arm_skipped arm=codex reason=no_base_resolved task=${TASK}"
      review_rc=77
      return
    fi
    if git -C "${ROOT}" diff --quiet "${codex_base}" -- 2>/dev/null; then
      emit decision "review_arm_skipped arm=codex reason=empty_diff task=${TASK}"
      review_rc=77
      return
    fi
    bash "${LEADV2_DISPATCH_CODEX_BIN:-${SCRIPT_DIR}/codex-task.sh}" adversarial-review --base "${codex_base}" --wait --cwd "${ROOT}" \
      --focus "Review ONLY the diff at ${DIFF_FILE}. You are independent of the author (${AUTHOR}). Report correctness findings by severity (Critical / High / Medium / Low). ${review_contract_focus} When using rg to inspect the diff or repository, treat exit 1 as a normal no-match result: write every potentially empty search as rg ... || true, then continue the review. A no-match is never a command failure or a reason to stop. Authoritative surfaces for this repo: \`.claude/CLAUDE.md\`, \`docs/reference/ENGINE-REFERENCE.md\`, \`docs/systems-map/CONTROL-TRUTH.md\`, \`docs/systems-map/TRUTH-TABLE.md\`, \`docs/BOARD.md\`. Read only the ones the diff touches. Treat any \`docs/specs/*.md\` as possibly stale unless corroborated by code. Before promoting a Codex finding, corroborate it against those surfaces; drop or downgrade any finding whose sole basis is a \`docs/specs/*.md\` claim." \
      > "${review_out}" 2> "${review_err}"; review_rc=$?
  elif [[ "${arm}" == glm ]]; then
    printf 'Review ONLY the diff at %s. You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${DIFF_FILE}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    glm_bin="${LEADV2_DISPATCH_GLM_BIN:-${SCRIPT_DIR}/glm-coder.sh}"
    omp_bin="${LEADV2_DISPATCH_OMP_BIN:-${ROOT}/.claude/leadv2-overrides/omp-task.sh}"
    review_rc=75
    if [[ -x "${glm_bin}" ]]; then
      # T14: review missions get the CRITIC role-scoped MCP allowlist
      # (config/mcp-role-critic.json), not the developer default.
      LEADV2_WORKER_ROLE=critic bash "${glm_bin}" run "@${mission_file}" --out "${review_out}" --cwd "${ROOT}" >/dev/null 2> "${review_err}"
      review_rc=$?
      if [[ ${review_rc} -eq 0 ]]; then
        materialize_glm_review_body "${review_out}" || true
      fi
    fi
    if [[ ${review_rc} -eq 75 && -x "${omp_bin}" ]]; then
      omp_run_id="$(bash "${omp_bin}" task "$(cat "${mission_file}")" --dir "${ROOT}" 2>> "${review_err}")"
      if [[ -n "${omp_run_id}" ]]; then
        omp_status=""
        omp_waited=0
        while (( omp_waited < 900 )); do
          omp_status="$(bash "${omp_bin}" status "${omp_run_id}" 2>/dev/null)"
          [[ "${omp_status}" == status=done* || "${omp_status}" == status=failed* ]] && break
          sleep 5
          omp_waited=$((omp_waited + 5))
        done
        cat "/tmp/omp-task-${omp_run_id}.log" > "${review_out}" 2>/dev/null || true
        [[ "${omp_status}" == status=done* ]] && review_rc=0 || review_rc=1
      fi
    fi
  elif [[ "${arm}" == kimi ]]; then
    printf 'Review ONLY the diff at %s. You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${DIFF_FILE}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    kimi_bin="${LEADV2_DISPATCH_KIMI_BIN:-${SCRIPT_DIR}/kimi-coder.sh}"
    if ! bash "${kimi_bin}" probe >/dev/null 2> "${review_err}"; then
      review_rc=77
      return
    fi
    bash "${kimi_bin}" run "@${mission_file}" --out "${review_out}" --cwd "${ROOT}" >/dev/null 2> "${review_err}"
    review_rc=$?
  else
    # sonnet or opus — MUST go through claude-subsession.sh, never a bare `claude -p`
    # (that combination requires --verbose or the process dies instantly; see
    # claude-subsession.sh ~line 338-342).
    printf 'Review ONLY the diff at %s. You are independent of the author (%s).\nReport correctness findings by severity (Critical / High / Medium / Low).\n%s\n' \
      "${DIFF_FILE}" "${AUTHOR}" "${review_contract}" > "${mission_file}"
    PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" --role critic --model "${arm}" --task-id "dispatch-${TASK}-review" --mission-file "${mission_file}" --wait \
      > "${review_out}" 2> "${review_err}"; review_rc=$?
    if [[ ${review_rc} -eq 0 ]]; then
      materialize_subsession_body "${review_out}" "${REVIEW_STAMP}" "${TASK}" || true
    fi
  fi
}

# ---------------------------------------------------------------------------
# 5. classify_arm_failure / next_ok_arm_after — lifted verbatim.
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

  # INFRA-WORKER-DIED (PLUGIN-TOOLING-FIX-01 A): a worker the reaper killed, or one
  # that died mid-stream without ever writing its .rc, is NOT a review that ran. It
  # produced no verdict and must never be counted as an author-quality signal.
  if [[ "${combined}" == *"reaped:"* ]]; then
    printf 'infra_worker_died'
    return 0
  fi
  # rc empty == _engine_arm_job never reached its `printf > .rc` (SIGTERM from the
  # arm-timeout watcher, or a hard kill). Partial .md content proves the worker was
  # mid-stream, not merely never launched.
  if [[ -z "${rc}" ]] && [[ -s "${out_file}" ]]; then
    printf 'infra_worker_died'
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

# _review_next_distinct_ok_arm <failed-arm> <author> <used-csv>
# Body-loss recovery must use an untried, distinct pool arm: rerunning the
# failed reviewer would only reproduce the lost body behind a fake retry.
_review_next_distinct_ok_arm() {
  local failed="$1" author="$2" used_csv="${3:-}" entry arm
  local IFS=','
  for entry in ${pool}; do
    arm="${entry%%:*}"
    [[ "${entry}" == "${arm}:ok:"* ]] || continue
    [[ "${arm}" != "${failed}" && "${arm}" != "${author}" ]] || continue
    [[ ",${used_csv}," != *",${arm},"* ]] || continue
    printf '%s' "${arm}"
    return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# 5b. REVIEW-ROUND1-EXHAUSTIVE-01: round detection + mission-text assembly.
#     Round 1 (no prior real verdict, or a stale/unrelated sidecar) is an
#     exhaustive multi-lens pass. Round 2+ (a prior FAIL/PASS verdict exists
#     for a diff that has since changed) is verification-only: the reviewer
#     checks whether each prior finding was fixed and admits a new finding
#     only if the fixes introduced it. See design §3 truth table — verify_only
#     requires positive evidence on every axis; anything missing falls back to
#     exhaustive, which is always safe.
# ---------------------------------------------------------------------------
_review_diff_hash() { # -> stdout "ok=0|1\n[hash]"; sets nothing (subshell-safe: caller parses)
  if [[ ! -f "${DIFF_FILE}" ]]; then
    printf 'ok=0\n'
    printf 'leadv2-review-run: diff file missing or unreadable: %s\n' "${DIFF_FILE}" >&2
    return 0
  fi
  local hash
  hash="$(shasum -a 256 "${DIFF_FILE}" | awk '{print $1}')"
  if [[ -n "${hash}" ]]; then
    printf 'ok=1\n%s' "${hash}"
  else
    printf 'ok=0\n'
  fi
}

# _review_prior_findings_body <round> -> stdout = "count=<N>\n<rendered body>"
# (body capped at 40 lines / 300 chars each). Line 1 is always the count
# sentinel — the caller (a command-substitution subshell boundary) parses it
# back into PRIOR_FINDINGS_COUNT rather than relying on a global set inside
# this function (H2: that global never survived the subshell). count=0 means
# "nothing to verify" (design §3 row: real verdict, 0 findings -> exhaustive).
_review_prior_findings_body() {
  local round="$1"
  local json="${HANDOFF}/review-findings.round${round}.json"
  local gate="${HANDOFF}/review-gate.round${round}.md"
  local -a lines=()

  if [[ -f "${json}" ]] && command -v python3 >/dev/null 2>&1; then
    while IFS= read -r _pfline; do
      [[ -n "${_pfline}" ]] && lines+=("${_pfline}")
    done < <(python3 - "${json}" 2>/dev/null <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for f in data.get("findings", []):
    sev = f.get("severity", "")
    if sev not in ("Critical", "High"):
        continue
    dim = f.get("dimension", "")
    file = f.get("file", "")
    ln = f.get("line", "")
    desc = f.get("desc", "")
    print("- [%s/%s] %s:%s %s" % (sev, dim, file, ln, desc))
PY
    )
  fi

  if [[ "${#lines[@]}" -eq 0 && -f "${gate}" ]]; then
    while IFS= read -r _fline; do
      lines+=("- ${_fline#FINDING: }")
    done < <(grep -E '^FINDING: severity=(Critical|High) ' "${gate}" 2>/dev/null)
  fi

  local count="${#lines[@]}"
  if [[ "${count}" -eq 0 ]]; then
    printf 'count=0\n'
    return 0
  fi

  local cap=40 truncated=0
  if [[ "${count}" -gt "${cap}" ]]; then
    truncated=1
    lines=("${lines[@]:0:${cap}}")
  fi

  local _l _out=""
  for _l in "${lines[@]}"; do
    [[ "${#_l}" -gt 300 ]] && _l="${_l:0:300}"
    _out+="${_l}"$'\n'
  done
  if [[ "${truncated}" -eq 1 ]]; then
    _out+="(… capped, see docs/handoff/dispatch-${TASK}/review-gate.round${round}.md)"$'\n'
  fi
  printf 'count=%s\n%s' "${count}" "${_out}"
}

# _review_highest_snapshot_round -> stdout = max N over existing
# review-gate.round<N>.md / review-findings.round<N>.json filenames in
# HANDOFF; 0 when none exist. Non-numeric filename remnants are ignored (M2).
_review_highest_snapshot_round() {
  local max=0 f n
  for f in "${HANDOFF}"/review-gate.round*.md "${HANDOFF}"/review-findings.round*.json; do
    [[ -f "${f}" ]] || continue
    n="$(basename "${f}")"
    n="${n#review-gate.round}"
    n="${n#review-findings.round}"
    n="${n%.md}"
    n="${n%.json}"
    [[ "${n}" =~ ^[0-9]+$ ]] || continue
    [[ "${n}" -gt "${max}" ]] && max="${n}"
  done
  printf '%s' "${max}"
}

# _review_parse_findings <round> -> sets globals PRIOR_FINDINGS_COUNT (int)
# and findings_body (may be empty). Parses the count=<N> sentinel that
# _review_prior_findings_body emits as its first line (see H2 note above);
# the sentinel must never leak past this point into PRIOR_FINDINGS_BODY.
_review_parse_findings() {
  local round="$1"
  local _raw _first
  _raw="$(_review_prior_findings_body "${round}")"
  _first="${_raw%%$'\n'*}"
  if [[ "${_first}" == count=* ]]; then
    PRIOR_FINDINGS_COUNT="${_first#count=}"
    if [[ "${_raw}" == *$'\n'* ]]; then
      findings_body="${_raw#*$'\n'}"
    else
      findings_body=""
    fi
  else
    PRIOR_FINDINGS_COUNT=0
    findings_body=""
  fi
  [[ "${PRIOR_FINDINGS_COUNT}" =~ ^[0-9]+$ ]] || PRIOR_FINDINGS_COUNT=0
}

# _review_round_context -> sets REVIEW_ROUND (int>=1), REVIEW_MODE
# (exhaustive|verify_only), PRIOR_FINDINGS_BODY (may be empty),
# PRIOR_FINDINGS_COUNT (int). Side effect: refreshes the numbered snapshot
# (review-gate.round<N>.md / review-findings.round<N>.json) whenever it is
# missing or differs from the live gate — never removes/renames the live
# gate. rc always 0 — this must never block a review.
#
# H1 fix: the round number is now MONOTONIC — computed once from
# max(sidecar round, highest existing snapshot round), instead of trusting
# the sidecar round alone, which regressed to a lower number whenever an
# intervening run wrote a stale/lower sidecar. The one case that does NOT
# advance the round is a re-review of the EXACT SAME diff that produced the
# current prior round (confirmed via the diff hash, not just "a round file
# exists") — re-running review against unchanged work must not grow the round
# forever; it degrades to exhaustive at the frozen round instead.
_review_round_context() {
  REVIEW_ROUND=1
  REVIEW_MODE="exhaustive"
  PRIOR_FINDINGS_BODY=""
  PRIOR_FINDINGS_COUNT=0
  # REVIEW-ROUNDCAP-01: reset every call so a frozen round from a prior
  # invocation in the same process never leaks forward.
  _REVIEW_ROUND_FROZEN=0
  _REVIEW_REPEAT_FAIL_BLOCK=0

  local state="${HANDOFF}/.review-round.state"
  local sidecar_round="" sidecar_diff="" sidecar_attempts=""
  if [[ -f "${state}" ]]; then
    sidecar_round="$(sed -n 's/^round=//p' "${state}" | head -n1)"
    sidecar_diff="$(sed -n 's/^diff=//p' "${state}" | head -n1)"
    sidecar_attempts="$(sed -n 's/^attempts=//p' "${state}" | head -n1)"
  fi
  # M2: a corrupt/non-numeric sidecar round degrades to "absent", not a crash.
  [[ "${sidecar_round}" =~ ^[0-9]+$ && "${sidecar_round}" -le 999 ]] || sidecar_round=""

  local gate="${HANDOFF}/review-gate.md"
  local gate_status=""
  [[ -f "${gate}" ]] && gate_status="$(sed -n 's/^status:[[:space:]]*//p' "${gate}" | head -n1)"
  local is_real_verdict=0
  [[ "${gate_status}" == "fail" || "${gate_status}" == "pass" ]] && is_real_verdict=1

  if [[ "${is_real_verdict}" -eq 1 && -n "${sidecar_round}" ]]; then
    local snap_gate="${HANDOFF}/review-gate.round${sidecar_round}.md"
    local snap_findings="${HANDOFF}/review-findings.round${sidecar_round}.json"
    cmp -s "${gate}" "${snap_gate}" 2>/dev/null || cp -f "${gate}" "${snap_gate}" 2>/dev/null || true
    if [[ -f "${HANDOFF}/review-findings.json" ]]; then
      cmp -s "${HANDOFF}/review-findings.json" "${snap_findings}" 2>/dev/null || cp -f "${HANDOFF}/review-findings.json" "${snap_findings}" 2>/dev/null || true
    fi
  fi

  local highest_snap
  highest_snap="$(_review_highest_snapshot_round)"
  local prior_round=0
  [[ -n "${sidecar_round}" && "${sidecar_round}" -gt "${prior_round}" ]] && prior_round="${sidecar_round}"
  [[ "${highest_snap}" -gt "${prior_round}" ]] && prior_round="${highest_snap}"

  local findings_body=""

  # Test seam / operator escape hatch: force a mode regardless of on-disk
  # state. LEADV2_REVIEW_ROUND=2 no longer forces verify_only unconditionally
  # (H3): an empty prior-findings body still falls back to exhaustive.
  if [[ "${LEADV2_REVIEW_ROUND:-}" == "1" ]]; then
    REVIEW_ROUND=1; REVIEW_MODE="exhaustive"
    return 0
  fi
  if [[ "${LEADV2_REVIEW_ROUND:-}" == "2" ]]; then
    _review_parse_findings "${prior_round:-1}"
    REVIEW_ROUND=$(( prior_round > 1 ? prior_round + 1 : 2 ))
    if [[ -z "${findings_body}" && -z "${PRIOR_FINDINGS_BODY}" ]]; then
      REVIEW_MODE="exhaustive"
      PRIOR_FINDINGS_BODY=""
    else
      REVIEW_MODE="verify_only"
      PRIOR_FINDINGS_BODY="${findings_body:-${PRIOR_FINDINGS_BODY}}"
    fi
    return 0
  fi

  if [[ "${is_real_verdict}" -eq 0 || "${prior_round}" -eq 0 ]]; then
    return 0
  fi

  # Frozen-round case: this exact diff already produced the current prior
  # round's real verdict — nothing new to look at, so the round does not
  # advance (T3 / T10's mid-repro "re-review the unchanged diff" step).
  if [[ "${REVIEW_DIFF_HASH_OK:-0}" -eq 1 && -n "${sidecar_diff}" && "${sidecar_diff}" == "${diff_hash:0:8}" ]]; then
    REVIEW_ROUND="${prior_round}"
    REVIEW_MODE="exhaustive"
    # REVIEW-ROUNDCAP-01: the round genuinely did not advance here (identical
    # diff, nothing new reviewed), so this re-invocation must not burn a fresh
    # policy attempt either — see _review_state_write.
    _REVIEW_ROUND_FROZEN=1
    # A failed implementation may receive one review of a changed diff. Do
    # not turn an unchanged failed result into another full census.
    # Legacy sidecars did not record attempts and are evidence snapshots, not
    # a consumed V3 recheck budget. LEADV2_REVIEW_MAX_ROUNDS=0 remains the
    # documented explicit unlimited override.
    if [[ "${gate_status}" == "fail" && "${sidecar_attempts}" =~ ^[1-9][0-9]*$ && "${LEADV2_REVIEW_MAX_ROUNDS:-2}" != 0 ]]; then
      _REVIEW_REPEAT_FAIL_BLOCK=1
    fi
    return 0
  fi

  # Diff has changed (or its hash is unknown/unverifiable) since the prior
  # round -> this is new content, so the round advances.
  REVIEW_ROUND=$((prior_round + 1))

  _review_parse_findings "${prior_round}"
  if [[ -z "${findings_body}" && -z "${PRIOR_FINDINGS_BODY}" ]] || [[ "${REVIEW_DIFF_HASH_OK:-0}" -ne 1 ]]; then
    REVIEW_MODE="exhaustive"
    PRIOR_FINDINGS_COUNT=0
    return 0
  fi

  REVIEW_MODE="verify_only"
  PRIOR_FINDINGS_BODY="${findings_body:-${PRIOR_FINDINGS_BODY}}"
  return 0
}

# _review_roundcap_read -> stdout = "<attempts> <spawns>" (two ints, fail-open
# 0 0). REVIEW-ROUNDCAP-01: attempts counts verdict-producing, non-dedup review
# runs for this task; spawns counts every fan-out launch regardless of dedup
# (the actual money-spent number, see §4a in the design). A lane upgraded
# mid-flight (state file has the legacy round=<n> but no attempts= line yet)
# falls back to round=<n> as the attempt count so it caps immediately instead
# of getting a free extra round.
#
# _review_state_lock_file -> stdout = lock path, beside the state file it guards.
_review_state_lock_file() { printf '%s/.review-round.state.lock' "${HANDOFF}"; }

# Wait budget for that lock. Default 10s, matching atomic_review_check_and_record
# (leadv2-dispatch-code.sh:2570). Test seam only -- production never sets it.
_review_state_lock_wait_s() {
  local raw="${LEADV2_REVIEW_STATE_LOCK_WAIT_S:-}"
  [[ "${raw}" =~ ^[0-9]+$ ]] && { printf '%s' "${raw}"; return 0; }
  printf '10'
}

_review_roundcap_read() {
  local _rcr_lockf; _rcr_lockf="$(_review_state_lock_file)"
  (
    lv2_lock_wait "${_rcr_lockf}" "$(_review_state_lock_wait_s)" || true
    local state="${HANDOFF}/.review-round.state"
    local attempts="" spawns="" legacy_round=""
    if [[ -f "${state}" ]]; then
      attempts="$(sed -n 's/^attempts=//p' "${state}" | head -n1)"
      spawns="$(sed -n 's/^spawns=//p' "${state}" | head -n1)"
      legacy_round="$(sed -n 's/^round=//p' "${state}" | head -n1)"
    fi
    [[ "${attempts}" =~ ^[0-9]+$ && "${attempts}" -le 99999 ]] || attempts=""
    [[ "${spawns}" =~ ^[0-9]+$ && "${spawns}" -le 99999 ]] || spawns=""
    if [[ -z "${attempts}" ]]; then
      if [[ "${legacy_round}" =~ ^[0-9]+$ && "${legacy_round}" -le 999 ]]; then
        attempts="${legacy_round}"
      else
        attempts=0
      fi
    fi
    [[ -z "${spawns}" ]] && spawns=0
    printf '%s %s' "${attempts}" "${spawns}"
  ) 9>"${_rcr_lockf}" 2>/dev/null
}

# _review_roundcap_limit -> stdout = resolved LEADV2_REVIEW_MAX_ROUNDS.
# Absent/empty/malformed all default to 2 (the declared policy); 0 is the
# kill-switch and is passed through verbatim, uncapped. Never eval'd, never
# word-split — checked only via integer regex, per the config-boundary table.
_review_roundcap_limit() {
  local raw="${LEADV2_REVIEW_MAX_ROUNDS:-}"
  if [[ -z "${raw}" ]]; then
    printf '2'
    return 0
  fi
  if [[ "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${raw}"
    return 0
  fi
  printf 'leadv2-review-run.sh: LEADV2_REVIEW_MAX_ROUNDS=%s is not a non-negative integer, defaulting to 2\n' "${raw}" >&2
  printf '2'
}

# _review_spawncap_limit <resolved_max_rounds> -> stdout = resolved
# LEADV2_REVIEW_MAX_SPAWNS. Default 3x the round cap; kill-switched whenever
# the round cap itself is 0 (unlimited); malformed/non-positive falls back to
# the derived default rather than refusing.
_review_spawncap_limit() {
  local max_rounds="$1"
  if [[ "${max_rounds}" -eq 0 ]]; then
    printf '0'
    return 0
  fi
  local raw="${LEADV2_REVIEW_MAX_SPAWNS:-}"
  if [[ "${raw}" =~ ^[0-9]+$ && "${raw}" -gt 0 ]]; then
    printf '%s' "${raw}"
    return 0
  fi
  printf '%s' "$(( max_rounds * 3 ))"
}

# _review_state_write [mode] -> rc0 always. Writes .review-round.state
# atomically, clamping the on-disk round so it can never decrease (H1
# belt-and-suspenders: even a forced LEADV2_REVIEW_ROUND=1 run cannot regress a
# higher round already on disk). Skips the write entirely when the diff hash
# could not be computed (M1) — a round file must never be written from an
# unknown/empty diff hash.
#
# REVIEW-ROUNDCAP-01: mode="verdict" (default, called at every verdict-
# producing exit) increments `attempts` unless REVIEW_DEDUP=1 is set (a
# diff-hash dedup rc=2 must not grow the policy-legible attempt count — design
# requirement 4) or the round was frozen by _review_round_context (a
# re-review of an already-reviewed, unchanged diff must not burn a fresh
# attempt either — it is not a new round). mode="spawn" (called once,
# immediately before the fan-out is
# launched) increments `spawns` instead — this is the backstop counter that
# actually bounds spend, because dedup runs still pay for a full fan-out (§4a).
# Single writer, both counters, so no second source of truth is introduced.
_review_state_write() {
  [[ "${REVIEW_DIFF_HASH_OK:-0}" -eq 1 ]] || return 0
  local mode="${1:-verdict}"
  local _rsw_lockf; _rsw_lockf="$(_review_state_lock_file)"
  (
    lv2_lock_wait "${_rsw_lockf}" "$(_review_state_lock_wait_s)" || true
    local state="${HANDOFF}/.review-round.state"
    local existing_round=0 existing_attempts=0 existing_spawns=0
    if [[ -f "${state}" ]]; then
      existing_round="$(sed -n 's/^round=//p' "${state}" | head -n1)"
      [[ "${existing_round}" =~ ^[0-9]+$ ]] || existing_round=0
      existing_attempts="$(sed -n 's/^attempts=//p' "${state}" | head -n1)"
      [[ "${existing_attempts}" =~ ^[0-9]+$ ]] || existing_attempts=0
      existing_spawns="$(sed -n 's/^spawns=//p' "${state}" | head -n1)"
      [[ "${existing_spawns}" =~ ^[0-9]+$ ]] || existing_spawns=0
    fi
    local write_round="${REVIEW_ROUND}"
    [[ "${existing_round}" -gt "${write_round}" ]] && write_round="${existing_round}"

    local write_attempts="${existing_attempts}"
    local write_spawns="${existing_spawns}"
    if [[ "${mode}" == "spawn" ]]; then
      write_spawns=$(( existing_spawns + 1 ))
    elif [[ "${REVIEW_DEDUP:-0}" -ne 1 && "${_REVIEW_ROUND_FROZEN:-0}" -ne 1 ]]; then
      write_attempts=$(( existing_attempts + 1 ))
    fi

    { printf 'round=%s\ndiff=%s\nattempts=%s\nspawns=%s\n' "${write_round}" "${diff_hash:0:8}" "${write_attempts}" "${write_spawns}" > "${state}.tmp" \
      && mv -f "${state}.tmp" "${state}"; } 2>/dev/null || true
  ) 9>"${_rsw_lockf}" 2>/dev/null || true
  return 0
}

# _review_build_contract -> stdout = full mission contract text for the
# current REVIEW_MODE/REVIEW_ROUND/PRIOR_FINDINGS_BODY. Always ends with the
# four unchanged verbatim-format contract lines so every downstream parser
# (parse_review_verdict, leadv2-review-findings.sh) is unaffected.
_review_build_contract() {
  if [[ "${REVIEW_MODE}" == "verify_only" ]]; then
    printf 'VERIFICATION-ONLY ROUND %s\n\n' "${REVIEW_ROUND}"
    printf 'This diff already went through review. Below are the prior findings from the previous round.\n'
    printf 'For each one, verify by execution whether each prior finding below is fixed.\n'
    printf 'Admit a NEW finding ONLY if the fixes introduced it. Do not re-litigate pre-existing issues you were not asked to verify.\n\n'
    printf 'Prior findings:\n%s\n' "${PRIOR_FINDINGS_BODY}"
    printf '\n%s' "${_review_contract_base}"
  else
    printf 'EXHAUSTIVE ROUND %s\n\n' "${REVIEW_ROUND}"
    printf 'Review this diff through FIVE lenses:\n'
    printf '1. correctness\n2. tests-can-fail (falsification)\n3. product-invariant/contract\n4. census\n5. claims-without-evidence\n\n'
    printf 'Census rule: if you find one instance of a defect shape, enumerate ALL same-shape instances in the touched files before returning.\n'
    printf 'Claims-without-evidence rule: enumerate every factual claim about an external system or API made in the diff, its comments, or the deliverable. Each must carry inline evidence (probe output, log excerpt, doc link plus live check) or the literal tag UNVERIFIED. An untagged evidence-free claim that DRIVES a decision -- a code path, a config value, a limit, a retry policy -- is a BLOCKING finding. A tagged one is MEDIUM at most.\n\n'
    printf 'Report EVERYTHING you find in this one pass. Never stop at the first 1-3 findings.\n\n'
    printf '%s' "${_review_contract_base}"
  fi
}

# _review_flatten <text> -> stdout = <text> collapsed to one line (newlines
# and runs of spaces collapsed). Used ONLY for the codex --focus argument,
# which is a single shell word (R6) — the new mission text must never contain
# `"` or a backtick, enforced by the offline test suite.
_review_flatten() {
  printf '%s' "$1" | tr '\n' ' ' | tr -s ' '
}

# ---------------------------------------------------------------------------
# 6. Fan-out helpers (new — design §2 step 3/4)
# ---------------------------------------------------------------------------

# _engine_pool_ok_arms — extract the ordered list of :ok: arms from ${pool},
# deduplicated (risk A4: the same arm must never appear twice in one fan-out).
# Prints one arm per line.
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
# REVIEW-FANOUT-VISIBILITY-01 (R2, 2026-08-22) - name the degradation.
#
# Diagnosed cause of the dead fan-out: NOT a code defect in pool selection. The
# resolver's pool is quota-correct; the environment simply has one live arm. On
# 2026-08-22 the live reading was codex=98% (>= review_threshold_pct 95),
# glm=90% (>= glm_review_threshold_pct 90), anthropic=32%, and the lane's AUTHOR
# was `sonnet` - so of the 4-arm review_arm_order [codex, glm, opus, sonnet],
# three were excluded and exactly ONE (`opus`) was `:ok:`. REVIEW_FANOUT asked
# for 3; the pool could offer 1.
#
# The DEFECT is that this was invisible: the artifact printed `arms: opus` and
# the identical `status:` line a genuine 3-arm union prints, so a union verdict
# computed over a SINGLE opinion wore the strong name of a fan-out. The helpers
# below exist so review-gate.md states requested-vs-achieved and names why each
# missing arm was missing.
# ---------------------------------------------------------------------------

# _engine_pool_excluded <ran-csv> - for every arm in ${pool} that is NOT in the
# comma-separated <ran-csv>, print `<arm>=<disposition>`, joined by commas
# (e.g. `codex=blocked:98,glm=blocked:90,sonnet=author`). A trailing empty detail
# field is stripped, so `glm:author:` renders `glm=author`, never `glm=author:`.
_engine_pool_excluded() { # <ran-csv>
  local ran_csv="${1:-}"
  local entry arm disp out=""
  local IFS=','
  for entry in ${pool}; do
    arm="${entry%%:*}"
    [[ -n "${arm}" ]] || continue
    case ",${ran_csv}," in
      *",${arm},"*) continue ;;
    esac
    disp="${entry#"${arm}:"}"
    disp="${disp%:}"
    [[ -n "${disp}" ]] || disp="unknown"
    out="${out:+${out},}${arm}=${disp}"
  done
  printf '%s' "${out}"
}

# _engine_pool_ok_count - how many DISTINCT `:ok:` arms the pool actually offered.
# This is the ceiling on the fan-out width, independent of REVIEW_FANOUT.
_engine_pool_ok_count() {
  local n=0 a
  while IFS= read -r a; do
    [[ -n "${a}" ]] && n=$((n + 1))
  done < <(_engine_pool_ok_arms)
  printf '%s' "${n}"
}

# _engine_arm_from_floor <arm> - true when this arm entered the pool through the
# resolver's emergency rank-table floor (`<arm>:floor:<pct|degraded>`), which
# bypasses lockout AND quota gating outright. A floor-sourced reviewer must never
# read as identical to a healthy quota-cleared one.
_engine_arm_from_floor() { # <arm>
  case ",${pool}," in
    *",${1}:floor:"*) return 0 ;;
  esac
  return 1
}

# Per-arm job wrapper: runs run_reviewer_arm in a background-safe subshell,
# then persists the result (rc/out/err are file-based so the parent can read
# them back after `wait`, since subshell locals do not propagate).
# REVIEW-ARM-FAILCLOSED-02: the .rc write must survive every exit path of
# run_reviewer_arm. A bare call aborts mid-function under a `set -e` caller
# (the `bash <stub>; review_rc=$?` inside never reaches its capture), and a
# path that never assigns review_rc kills the subshell on the printf itself
# under `set -u` — either way review-<arm>.rc is absent and the parent cannot
# classify the arm. `|| review_rc=$?` neutralises -e for the whole call AND
# captures a nonzero return; ${review_rc:-1} turns "completed but never set an
# rc" into rc=1 instead of an unbound-variable crash.
_engine_arm_job() { # <arm>
  local arm="$1"
  review_rc=""
  run_reviewer_arm "${arm}" || review_rc=$?
  printf '%s' "${review_rc:-1}" > "${HANDOFF}/review-${arm}.rc"
}

# Bounded-wait wrapper: bash 3.2 has no built-in per-background-job timeout, so
# a watcher subshell kills the job after ${ARM_TIMEOUT_S}. Portable, no GNU
# coreutils `timeout` dependency.
ARM_TIMEOUT_S="${LEADV2_REVIEW_ARM_TIMEOUT_S:-900}"
_engine_run_arm_with_timeout() { # <arm>
  local arm="$1"
  ( _engine_arm_job "${arm}" ) &
  local job_pid=$!
  ( sleep "${ARM_TIMEOUT_S}"; kill -TERM "${job_pid}" 2>/dev/null ) &
  local watcher_pid=$!
  wait "${job_pid}" 2>/dev/null
  kill "${watcher_pid}" 2>/dev/null
  wait "${watcher_pid}" 2>/dev/null
  true
}

# Security/hack detection is an escalation, not an ordinary reviewer. It is
# enabled by an explicit operator flag or by protected/high-risk write signals.
# The pass is never counted as one of the independent review arms.
HACKDETECT_OUT="${HANDOFF}/review-hackdetect.md"
HACKDETECT_ERR="${HANDOFF}/review-hackdetect.err"
_engine_security_pass_enabled() {
  case "${LEADV2_REVIEW_SECURITY_PASS:-0}" in 1|true|TRUE|yes|YES) return 0 ;; esac
  if [[ "${REVIEW_SIGNALS_STATUS:-missing}" != "ready" ]] || ! declare -F leadv2_review_signals >/dev/null 2>&1; then
    return 0
  fi
  local routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"
  local signals
  if ! signals="$(leadv2_review_signals "${routing_yaml}" "${WRITES_CSV}" 2>/dev/null)"; then
    return 0
  fi
  if [[ "${signals}" != *'"protected_path":'* || "${signals}" != *'"safety_touched":'* ]]; then
    return 0
  fi
  [[ "${signals}" == *'"protected_path":true'* || "${signals}" == *'"safety_touched":true'* ]]
}

_engine_hack_detect_job() {
  local mission="${HANDOFF}/review-mission-hackdetect.md"
  {
    printf 'Run hack-detection on the diff at %s: TODO/FIXME band-aids, magic numbers, broad except, hardcoded creds/secrets, silent fallbacks.\n' "${DIFF_FILE}"
    printf 'Report each as one line, exact format:\nFINDING: severity=<Critical|High|Medium|Low> file=<path> line=<n> dimension=hack desc=<one line>\n'
    printf 'Emit nothing else.\n'
  } > "${mission}"
  # The hack pass shares the critic role implementation but never its artifact
  # namespace: claude-subsession keys stream/cost files by task id plus role.
  PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" --role critic --model haiku --task-id "dispatch-${TASK}-review-hackdetect" --mission-file "${mission}" --wait \
    > "${HACKDETECT_OUT}" 2> "${HACKDETECT_ERR}" || true
}

# A verifier is useful only when independent reviewers disagree over a
# blocking finding. Keep it off on the ordinary single-review path; operators
# may enable it explicitly, and security escalation enables it for a dispute.
_engine_verifier_policy_enabled() {
  case "${LEADV2_REVIEW_VERIFY_FINDINGS:-0}" in 1|true|TRUE|yes|YES) return 0 ;; esac
  [[ "${SECURITY_REVIEW_ENABLED:-0}" -eq 1 ]]
}

# Verify/refute: for every Critical/High FINDING: line, spawn one refutation job on
# an arm != the arm that raised it. Ported prompt from workflows/leadv2-review.js:196.
_engine_verify_job() { # <arm> <out-file> <severity> <dimension> <desc>
  local arm="$1" out="$2" sev="$3" dim="$4" desc="$5"
  local mission="${out}.mission"
  printf 'Try to REFUTE this finding. Default is_real=false if you cannot concretely confirm it against %s.\nFinding [%s/%s]: %s\nReport exactly one line: VERIFY_VERDICT: <upheld|refuted>\n' \
    "${DIFF_FILE}" "${sev}" "${dim}" "${desc}" > "${mission}"
  PROJECT_ROOT="${ROOT}" bash "${LEADV2_DISPATCH_ARCHITECT_BIN:-${SCRIPT_DIR}/claude-subsession.sh}" --role critic --model "${arm}" --task-id "dispatch-${TASK}-review" --mission-file "${mission}" --wait \
    > "${out}" 2>>"${out}.err" || true
}

# ---------------------------------------------------------------------------
# 7. Main
# ---------------------------------------------------------------------------
review_adir="${ROOT}/docs/handoff/dispatch-${TASK}-review"
mkdir -p "${review_adir}" 2>/dev/null || true
REVIEW_STAMP="${HANDOFF}/.review-start.stamp"
touch "${REVIEW_STAMP}" 2>/dev/null || true
_review_contract_base=$'Your review MUST contain these two lines, verbatim format, before any prose:\nREVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>\nREVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>\nFAIL if any Critical or High finding. PASS if the diff is clean. PASS_WITH_NITS otherwise.\nAlso report every Critical/High finding on its own line, exact format:\nFINDING: severity=<Critical|High> file=<path> line=<n> dimension=<correctness|security|design|perf> desc=<one line>\n\nIf no findings are found, please output a brief explanation (at least one sentence) after the required lines to ensure the review body is sufficient for processing.'

# REVIEW-ROUND1-EXHAUSTIVE-01: diff hash hoisted here (was computed later, at
# the old line ~546) so round detection — which must run before pool resolve
# (R1: even the `status: unreviewed` exit below writes a gate) — has it
# available. The old post-pool-resolve computation is removed; nothing else
# reads diff_hash before this point.
# _review_diff_hash_raw carries an "ok=0|1" sentinel on its first line — the
# raw hash is only trustworthy when ok=1 (M1: an empty/unreadable diff must
# never silently look like a valid, unchanged hash).
_review_diff_hash_raw="$(_review_diff_hash)"
if [[ "${_review_diff_hash_raw%%$'\n'*}" == "ok=1" ]]; then
  REVIEW_DIFF_HASH_OK=1
  diff_hash="${_review_diff_hash_raw#*$'\n'}"
else
  REVIEW_DIFF_HASH_OK=0
  diff_hash=""
fi
_review_round_context
review_contract="$(_review_build_contract)"
review_contract_focus="$(_review_flatten "${review_contract}")"
emit decision "review_round task=${TASK} round=${REVIEW_ROUND} mode=${REVIEW_MODE} prior_findings=${PRIOR_FINDINGS_COUNT:-0}"

if [[ "${_REVIEW_REPEAT_FAIL_BLOCK:-0}" -eq 1 ]]; then
  printf 'status: blocked\nreason: review_recheck_cap\nrounds: 2\n' > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=review_recheck_cap"
  exit 8
fi

# REVIEW-ROUNDCAP-01: refuse a further review round once the declared policy
# limit is reached. Placed AFTER _review_round_context (so the prior round's
# gate/findings are already snapshotted — refusing here never destroys a real
# verdict) and BEFORE the machine-round-0 check below, so a capped lane never
# pays for even that cheap selfcheck read. The (LLM) lead cannot bypass this by
# re-invoking: attempts is unaffected by the LEADV2_REVIEW_ROUND test seam, so
# a re-invocation after the cap re-enters this same branch and exits 8 again,
# idempotently, at ~0 cost.
_review_roundcap_pair="$(_review_roundcap_read)"
_review_roundcap_attempts="${_review_roundcap_pair% *}"
_review_roundcap_max="$(_review_roundcap_limit)"
if [[ "${_review_roundcap_max}" -gt 0 && "${_review_roundcap_attempts}" -ge "${_review_roundcap_max}" ]]; then
  {
    printf 'status: blocked\nreason: review_roundcap\nrounds: %s\nmax_rounds: %s\nescalation: %s/review-roundcap-escalation.md\n' \
      "${_review_roundcap_attempts}" "${_review_roundcap_max}" "${HANDOFF}"
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  {
    printf '# Review round cap reached\n\n'
    printf "Task \`%s\` has been reviewed %s time(s) without converging to a passing verdict " "${TASK}" "${_review_roundcap_attempts}"
    printf '(configured maximum: %s). The engine is refusing to spend another review round on it.\n\n' "${_review_roundcap_max}"
    printf 'This lane needs architect escalation or PARK — a human or the lead must decide next steps.\n'
    printf 'Raise the limit for one more attempt with LEADV2_REVIEW_MAX_ROUNDS, or set it to 0 to disable the cap entirely.\n'
  } > "${HANDOFF}/review-roundcap-escalation.md.tmp"
  mv -f "${HANDOFF}/review-roundcap-escalation.md.tmp" "${HANDOFF}/review-roundcap-escalation.md"
  _review_roundcap_journal_bin="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
  [[ -f "${_review_roundcap_journal_bin}" ]] && bash "${_review_roundcap_journal_bin}" append "${TASK}" review_roundcap "review_roundcap task=${TASK} rounds=${_review_roundcap_attempts} max=${_review_roundcap_max}" >/dev/null 2>&1 || true
  emit decision "review_gate task=${TASK} status=blocked reason=review_roundcap rounds=${_review_roundcap_attempts} max=${_review_roundcap_max}"
  printf '[leadv2-review-run] REVIEW ROUNDCAP: task=%s rounds=%s max=%s — refusing a further review round.\n' "${TASK}" "${_review_roundcap_attempts}" "${_review_roundcap_max}" >&2
  printf '[leadv2-review-run] This lane needs architect escalation or PARK. See %s/review-roundcap-escalation.md\n' "${HANDOFF}" >&2
  exit 8
fi

# V3-TIERED-REVIEW-01: machine round-0, before any LLM round is spawned.
# leadv2-dispatch-product-close.sh's builder-selfcheck (BUILDER-SELFCHECK-
# GATE-01, lib/leadv2-builder-selfcheck.sh) already ran bash -n / py_compile /
# changed-scope suites over this exact diff at build time and wrote its
# verdict to HANDOFF/selfcheck.md (first line `verdict: RED|GREEN|DEGRADED`).
# Paying for an LLM fan-out on a diff builder-selfcheck already proved fails
# mechanics is pure waste -- consume that verdict instead of re-running the
# same checks. Additive only: when the artifact is absent (this engine can
# run standalone, per its own header note, with no prior build-time
# selfcheck), falls through to the existing LLM-round behavior unchanged.
# Flag default-on, independently overridable from the LLM-round machinery
# below (which stays untouched by this gate).
if [[ "${LEADV2_REVIEW_MACHINE_ROUND0:-1}" != 0 ]]; then
  _round0_selfcheck_md="${HANDOFF}/selfcheck.md"
  if [[ -f "${_round0_selfcheck_md}" ]] && grep -q '^verdict: RED$' "${_round0_selfcheck_md}" 2>/dev/null; then
    # round-1 HIGH fix: a RED verdict with no proof it was computed from THIS diff
    # (absent/malformed diff_hash line, or a hash that doesn't match the diff being
    # reviewed right now) must never fail-closed a since-changed, possibly-healthy
    # diff -- fall through to the normal LLM round instead, same as no-artifact.
    _round0_selfcheck_hash="$(sed -n 's/^diff_hash: \([0-9a-f]\{64\}\)$/\1/p' "${_round0_selfcheck_md}" 2>/dev/null | head -n1)"
    if [[ "${REVIEW_DIFF_HASH_OK:-0}" -eq 1 && -n "${_round0_selfcheck_hash}" && "${_round0_selfcheck_hash}" == "${diff_hash}" ]]; then
      {
        printf 'status: fail\nreason: selfcheck_red_round0\nselfcheck: docs/handoff/dispatch-%s/selfcheck.md\n' "${TASK}"
      } > "${HANDOFF}/review-gate.md.tmp"
      mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
      _review_state_write
      emit decision "review_gate task=${TASK} status=fail round=0 reason=selfcheck_red_round0"
      exit 7
    fi
    emit decision "review_gate task=${TASK} status=round0_skip round=0 reason=selfcheck_diff_hash_mismatch selfcheck_hash=${_round0_selfcheck_hash:-none} diff_hash=${diff_hash:0:8}"
  fi
fi

# Step 2: pool resolve.
resolver_out="$(resolve_review_pool_call)"
reviewer="$(printf '%s\n' "${resolver_out}" | sed -n 's/^reviewer=//p' | head -n1)"
pool="$(printf '%s\n' "${resolver_out}" | sed -n 's/^pool=//p' | head -n1)"
refusal="$(printf '%s\n' "${resolver_out}" | sed -n 's/^refusal=//p' | head -n1)"
SECURITY_REVIEW_ENABLED=0
if _engine_security_pass_enabled; then
  SECURITY_REVIEW_ENABLED=1
fi
emit decision "review_security task=${TASK} enabled=${SECURITY_REVIEW_ENABLED}"
source "${SCRIPT_DIR}/lib/leadv2-review-reroute-note.sh"
_reroute_note="$(leadv2_review_reroute_note "${TASK}" "${pool}" "${reviewer}")"
[[ -n "${_reroute_note}" ]] && emit decision "${_reroute_note}"

if [[ -n "${reviewer}" && "${reviewer}" == "${AUTHOR}" ]]; then
  refusal="reviewer_equals_author"
  reviewer=""
fi

if [[ -z "${reviewer}" ]]; then
  refusal="${refusal:-all_review_arms_unavailable}"
  {
    printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: \n' "${AUTHOR}" "${pool}"
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=${pool} refusal=${refusal} tried="
  exit 9
fi

# Step 3/4: fan-out list — first REVIEW_FANOUT distinct :ok: arms, dedup guard (A4).
fanout_list=()
while IFS= read -r _arm; do
  [[ -n "${_arm}" ]] || continue
  fanout_list+=("${_arm}")
  [[ "${#fanout_list[@]}" -ge "${REVIEW_FANOUT}" ]] && break
done < <(_engine_pool_ok_arms)

if [[ "${#fanout_list[@]}" -eq 0 ]]; then
  # Should not happen (reviewer is non-empty above), but fail closed rather than
  # silently landing with zero arms run.
  fanout_list=("${reviewer}")
fi

# A4 guard: assert no duplicate arm made it into the fan-out list. NOTE: iterate
# fanout_list WITHOUT the `${arr[@]:-}` default-operator form — on a bash array
# with zero elements that form expands to ONE empty-string word (a documented
# bash quirk, not the "no elements" behaviour `${arr[@]}` alone gives under
# `set -u`), which would make this guard false-positive "duplicate ''" the very
# first time the pool degrades to zero live arms. Reached AFTER the zero-arm
# fallback above, so fanout_list is guaranteed non-empty here.
_dedup_check=""
for _arm in "${fanout_list[@]}"; do
  case ",${_dedup_check}," in
    *",${_arm},"*)
      printf 'leadv2-review-run.sh: INTERNAL: duplicate arm %s in fan-out list — refusing to run\n' "${_arm}" >&2
      exit 2
      ;;
  esac
  _dedup_check="${_dedup_check},${_arm}"
done

# REVIEW-ROUNDCAP-01 spawn backstop (design §4a). record-review's diff-hash
# dedup (rc=2, below) fires AFTER the fan-out already ran and was paid for, so
# a lane whose diff/verdict are stable can dedup forever without `attempts`
# ever advancing. `spawns` counts every launch unconditionally — dedup or not
# — and is the number that actually bounds spend; `attempts` stays the
# policy-legible number the escalation file quotes.
_review_spawncap_pair="$(_review_roundcap_read)"
_review_spawncap_spawns="${_review_spawncap_pair#* }"
_review_spawncap_max="$(_review_spawncap_limit "${_review_roundcap_max}")"
if [[ "${_review_spawncap_max}" -gt 0 && "${_review_spawncap_spawns}" -ge "${_review_spawncap_max}" ]]; then
  {
    printf 'status: blocked\nreason: review_spawncap\nspawns: %s\nmax_spawns: %s\nescalation: %s/review-roundcap-escalation.md\n' \
      "${_review_spawncap_spawns}" "${_review_spawncap_max}" "${HANDOFF}"
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  {
    printf '# Review spawn cap reached\n\n'
    printf "Task \`%s\` has launched %s reviewer fan-out(s) (configured maximum: %s), " "${TASK}" "${_review_spawncap_spawns}" "${_review_spawncap_max}"
    printf 'including dedup rounds that never advanced the round counter. The engine is refusing to spend another one.\n\n'
    printf 'This lane needs architect escalation or PARK — a human or the lead must decide next steps.\n'
  } > "${HANDOFF}/review-roundcap-escalation.md.tmp"
  mv -f "${HANDOFF}/review-roundcap-escalation.md.tmp" "${HANDOFF}/review-roundcap-escalation.md"
  _review_spawncap_journal_bin="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
  [[ -f "${_review_spawncap_journal_bin}" ]] && bash "${_review_spawncap_journal_bin}" append "${TASK}" review_spawncap "review_spawncap task=${TASK} spawns=${_review_spawncap_spawns} max=${_review_spawncap_max}" >/dev/null 2>&1 || true
  emit decision "review_gate task=${TASK} status=blocked reason=review_spawncap spawns=${_review_spawncap_spawns} max=${_review_spawncap_max}"
  printf '[leadv2-review-run] REVIEW SPAWNCAP: task=%s spawns=%s max=%s — refusing a further review round.\n' "${TASK}" "${_review_spawncap_spawns}" "${_review_spawncap_max}" >&2
  printf '[leadv2-review-run] This lane needs architect escalation or PARK. See %s/review-roundcap-escalation.md\n' "${HANDOFF}" >&2
  exit 8
fi
_review_state_write spawn

# Launch independent review arms. The security/hack escalation runs only on
# protected/high-risk paths or when explicitly requested.
for _arm in "${fanout_list[@]}"; do
  _engine_run_arm_with_timeout "${_arm}" &
done
if [[ "${SECURITY_REVIEW_ENABLED}" -eq 1 ]]; then
  ( _engine_hack_detect_job ) &
fi
# A reviewer/hack child is expected to return its own nonzero transport rc.
# Do not let `set -e` turn that into a parent-process abort before Step 5 can
# persist and classify every arm into a terminal review-gate verdict.
wait || true

# Step 5: per-arm refusal reselection. Walk fan-out results; any refused_* arm is
# re-selected forward through ${pool} (bounded, tried[] cap) so one refusing arm
# does not stall the arms that already succeeded.
ran_arms=()
tried=()
_pc_unavailable=0
for _arm in "${fanout_list[@]}"; do
  _rc_file="${HANDOFF}/review-${_arm}.rc"
  _rc="$(cat "${_rc_file}" 2>/dev/null || printf '')"
  _out="${HANDOFF}/review-${_arm}.md"
  _err="${HANDOFF}/review-${_arm}.err"
  _slot_arm="${_arm}"
  _slot_rc="${_rc}"
  _died_retry=0
  while :; do
    cls="$(classify_arm_failure "${_slot_rc}" "${_err}" "${_out}")"
    if [[ "${cls}" == "infra_worker_died" ]]; then
      if [[ "${_died_retry}" -ge 1 ]]; then
        emit decision "review_gate task=${TASK} status=arm_infra_died arm=${_slot_arm} attempt=2 kind=infra action=give_up"
        break
      fi
      _died_retry=1
      emit decision "review_gate task=${TASK} status=arm_infra_died arm=${_slot_arm} attempt=1 kind=infra action=retry"
      rm -f "${HANDOFF}/review-${_slot_arm}.rc"
      # REVIEW-ARM-FAILCLOSED-02: bare run_reviewer_arm here let a `set -e`
      # caller abort the whole engine mid-retry with NO terminal gate written;
      # same || capture + rc default as _engine_arm_job.
      run_reviewer_arm "${_slot_arm}" || review_rc=$?
      _slot_rc="${review_rc:-1}"
      printf '%s' "${_slot_rc}" > "${HANDOFF}/review-${_slot_arm}.rc"
      continue
    fi
    if [[ "${cls}" != refused_* ]]; then
      break
    fi
    emit decision "review_gate task=${TASK} status=arm_refused arm=${_slot_arm} reason=${cls}"
    tried+=("${_slot_arm}")
    if [[ "${#tried[@]}" -ge 4 ]]; then
      _slot_arm=""
      break
    fi
    next_arm="$(next_ok_arm_after "${_slot_arm}" || true)"
    if [[ -z "${next_arm}" || "${next_arm}" == "${AUTHOR}" ]]; then
      _slot_arm=""
      break
    fi
    _slot_arm="${next_arm}"
    _out="${HANDOFF}/review-${_slot_arm}.md"
    _err="${HANDOFF}/review-${_slot_arm}.err"
    # REVIEW-ARM-FAILCLOSED-02: see the retry site above — same || capture.
    run_reviewer_arm "${_slot_arm}" || review_rc=$?
    _slot_rc="${review_rc:-1}"
    printf '%s' "${_slot_rc}" > "${HANDOFF}/review-${_slot_arm}.rc"
  done
  [[ -n "${_slot_arm}" ]] && ran_arms+=("${_slot_arm}")
done

if [[ "${#ran_arms[@]}" -eq 0 ]]; then
  _pc_tried_csv="$(IFS=,; echo "${tried[*]:-}")"
  {
    printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: %s\n' \
      "${AUTHOR}" "${pool}" "${_pc_tried_csv}"
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=${pool} tried=${_pc_tried_csv}"
  exit 9
fi

# REVIEW-BODY-PERSIST-01 guard: a paid review whose body was lost must surface
# as blocked, except for one recovery attempt on an untried, distinct pool arm.
# This protects the Codex no-match choke without allowing an arm to retry itself.
_review_body_retry_used=0
for _ran_index in "${!ran_arms[@]}"; do
  _arm="${ran_arms[${_ran_index}]}"
  while :; do
    _out="${HANDOFF}/review-${_arm}.md"
    _err="${HANDOFF}/review-${_arm}.err"
    _rc="$(cat "${HANDOFF}/review-${_arm}.rc" 2>/dev/null || printf '1')"
    if [[ "${_rc}" -eq 0 ]]; then
      _pc_body_min="${LEADV2_REVIEW_BODY_MIN_BYTES:-300}"
      _pc_body_bytes="$(wc -c < "${_out}" 2>/dev/null | tr -d '[:space:]')"; _pc_body_bytes="${_pc_body_bytes:-0}"
      if ! grep -q '^[[:space:]]*REVIEW_VERDICT:' "${_out}" 2>/dev/null && [[ "${_pc_body_bytes}" -lt "${_pc_body_min}" ]]; then
        if [[ -s "${_err}" ]] || grep -q 'cost recorded:' "${_err}" 2>/dev/null; then
          _pc_body_rel="${_out#"${ROOT}"/}"
          _pc_used_csv="$(IFS=,; echo "${ran_arms[*]}")"
          _pc_retry_arm=""
          if [[ "${_review_body_retry_used}" -eq 0 ]]; then
            _pc_retry_arm="$(_review_next_distinct_ok_arm "${_arm}" "${AUTHOR}" "${_pc_used_csv}" || true)"
          fi
          if [[ -n "${_pc_retry_arm}" ]]; then
            _review_body_retry_used=1
            emit decision "review_arm_retry from=${_arm} to=${_pc_retry_arm} task=${TASK} reason=review_body_lost"
            _pc_retry_journal="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
            if [[ -f "${_pc_retry_journal}" ]]; then
              bash "${_pc_retry_journal}" append "${TASK}" review_arm_retry \
                "review_arm_retry from=${_arm} to=${_pc_retry_arm}" >/dev/null 2>&1 || true
            fi
            _arm="${_pc_retry_arm}"
            ran_arms[${_ran_index}]="${_arm}"
            run_reviewer_arm "${_arm}" || review_rc=$?
            _rc="${review_rc:-1}"
            printf '%s' "${_rc}" > "${HANDOFF}/review-${_arm}.rc"
            continue
          fi
          printf 'status: blocked\nreason: review_body_lost\narm: %s\nbody: %s\nbytes: %s\n' \
            "${_arm}" "${_pc_body_rel}" "${_pc_body_bytes}" > "${HANDOFF}/review-gate.md.tmp"
          mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
          emit decision "review_gate task=${TASK} status=blocked reason=review_body_lost arm=${_arm} body=${_pc_body_rel} bytes=${_pc_body_bytes}"
          exit 6
        fi
      fi
    fi
    break
  done
done

# REVIEW-UNION-VERDICT-01 (2026-08-21): the union of arms is authoritative — ANY
# arm's FAIL fails the gate, not just the first one that happened to parse.
#
# The old loop took the first parsable arm and `break`-ed, so with an explicit
# multi-arm fan-out a Critical found by arm 2 or 3 did not block: its findings were
# unioned into the JSON while gating still keyed on arm 1's verdict. The Codex
# process audit named this precisely (codex-findings.md, Q1/proposal 2, against
# review-run.sh:1006-1027 and :1152-1164): "more arms currently buy more prose, not
# a stronger gate", and the effective counters computed at :1141-1148 were never
# used. Paying for three reviewers and gating on one is the worst of both — the cost
# of breadth with the assurance of a single opinion.
#
# `reviewer_primary` still names the FIRST parsable arm, so artifact paths, the
# dedup ledger key and the rendered findings block are unchanged when nothing
# escalates. Only the verdict is strengthened, and only in the blocking direction:
# an arm can turn PASS into FAIL, never FAIL into PASS.
verdict=""
reviewer_primary=""
_union_fail_arm=""
_review_has_fail=0
_review_has_nonfail=0
for _arm in "${ran_arms[@]}"; do
  resolve_review_artifact "${_arm}" || true
  _file="${REVIEW_ARTIFACT:-${HANDOFF}/review-${_arm}.md}"
  _rc="$(cat "${HANDOFF}/review-${_arm}.rc" 2>/dev/null || printf '1')"
  if [[ "${_rc}" -ne 0 && -z "${REVIEW_ARTIFACT}" ]]; then
    continue
  fi
  if [[ ! -s "${_file}" ]] || ! review_floor_ok "${_file}"; then
    continue
  fi
  if ! parse_review_verdict "${_file}"; then
    continue
  fi
  if [[ -z "${reviewer_primary}" ]]; then
    verdict="${PARSED_VERDICT}"
    reviewer_primary="${_arm}"
  fi
  if [[ "${PARSED_VERDICT}" == FAIL ]]; then
    _review_has_fail=1
  else
    _review_has_nonfail=1
  fi
  # Escalate on any arm's FAIL, including one found after the primary.
  if [[ "${PARSED_VERDICT}" == FAIL && -z "${_union_fail_arm}" ]]; then
    _union_fail_arm="${_arm}"
  fi
done

REVIEW_FINDINGS_DISPUTED=0
if [[ "${_review_has_fail}" -eq 1 && "${_review_has_nonfail}" -eq 1 ]]; then
  REVIEW_FINDINGS_DISPUTED=1
fi

if [[ -n "${_union_fail_arm}" && "${verdict}" != FAIL ]]; then
  emit decision "review_union_escalate task=${TASK} primary=${reviewer_primary} primary_verdict=${verdict} failing_arm=${_union_fail_arm}"
  verdict="FAIL"
  # Report the arm that actually failed, so the gate's findings block and the
  # ledger name the reviewer whose verdict is being enforced rather than an arm
  # that passed. resolve_review_artifact is re-run for that arm so
  # REVIEW_ARTIFACT/FINDINGS_* below describe the failing review, not the primary.
  reviewer_primary="${_union_fail_arm}"
  resolve_review_artifact "${_union_fail_arm}" || true
  parse_review_verdict "${REVIEW_ARTIFACT:-${HANDOFF}/review-${_union_fail_arm}.md}" || true
  verdict="FAIL"
fi

if [[ -z "${verdict}" ]]; then
  # No surviving arm produced a usable verdict — same three-way named-reason
  # vocabulary the lane already uses (N-5 D4), scoped to the whole fan-out.
  # REVIEW-ARM-FAILCLOSED-02: classify EVERY surviving arm with its rc, not
  # just the first, so the terminal status names which arms produced no
  # verdict and why (additive `arm_rc:` line; the parser tolerates unknown
  # lines, and `arms:` keeps its plain-csv meaning).
  _first_arm="${ran_arms[0]}"
  _first_rc="$(cat "${HANDOFF}/review-${_first_arm}.rc" 2>/dev/null || printf '1')"
  _fc_arms_rc=""
  for _arm in "${ran_arms[@]}"; do
    _fc_rc="$(cat "${HANDOFF}/review-${_arm}.rc" 2>/dev/null || printf 'missing')"
    _fc_arms_rc="${_fc_arms_rc:+${_fc_arms_rc},}${_arm}=${_fc_rc}"
  done
  if [[ "${_first_rc}" -ne 0 ]]; then
    printf 'status: blocked\nreason: provider_error\nrc: %s\narm_rc: %s\n' "${_first_rc}" "${_fc_arms_rc}" > "${HANDOFF}/review-gate.md.tmp"
    emit decision "review_gate task=${TASK} status=blocked reason=provider_error rc=${_first_rc} arm_rc=${_fc_arms_rc}"
  else
    printf 'status: blocked\nreason: empty_response\narm_rc: %s\n' "${_fc_arms_rc}" > "${HANDOFF}/review-gate.md.tmp"
    emit decision "review_gate task=${TASK} status=blocked reason=empty_response arm_rc=${_fc_arms_rc}"
  fi
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  exit 6
fi

FINDINGS_CRITICAL_TOTAL="${FINDINGS_CRITICAL}"
FINDINGS_HIGH_TOTAL="${FINDINGS_HIGH}"
FINDINGS_MEDIUM_TOTAL="${FINDINGS_MEDIUM}"
FINDINGS_LOW_TOTAL="${FINDINGS_LOW}"

# --- Step 6/7: synthesis — union FINDING: lines across ran_arms + hack-detect,
# dedup by (file,line,severity,dimension), then verify each Critical/High on an
# arm != its raiser. -------------------------------------------------------
FINDINGS_RAW="${HANDOFF}/.review-findings-raw.tsv"
: > "${FINDINGS_RAW}"
# REVIEW-TERMINAL-PASS-01: the no-findings greps below are the first element of
# their pipelines; under a caller's `bash -e` our own pipefail turns a no-match
# grep (rc 1) into a pipeline failure and errexit aborts the engine BEFORE the
# terminal pass review-gate.md is written. `|| :` keeps the pipeline green when
# there is simply nothing to union.
for _arm in "${ran_arms[@]}"; do
  _file="${HANDOFF}/review-${_arm}.md"
  [[ -f "${REVIEW_ARTIFACT:-}" && "${_arm}" == "${reviewer_primary}" ]] && _file="${REVIEW_ARTIFACT}"
  { grep -E '^FINDING:' "${_file}" 2>/dev/null || :; } | while IFS= read -r _line; do
    _sev="$(printf '%s\n' "${_line}" | sed -nE 's/.*severity=([A-Za-z]+).*/\1/p')"
    _f="$(printf '%s\n' "${_line}" | sed -nE 's/.*file=([^ ]+).*/\1/p')"
    _ln="$(printf '%s\n' "${_line}" | sed -nE 's/.*line=([0-9]+).*/\1/p')"
    _dim="$(printf '%s\n' "${_line}" | sed -nE 's/.*dimension=([A-Za-z]+).*/\1/p')"
    _desc="$(printf '%s\n' "${_line}" | sed -nE 's/.*desc=(.*)$/\1/p')"
    [[ -n "${_sev}" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${_arm}" "${_sev}" "${_f}" "${_ln}" "${_dim}" "${_desc}" >> "${FINDINGS_RAW}"
  done
done
{ grep -E '^FINDING:' "${HACKDETECT_OUT}" 2>/dev/null || :; } | while IFS= read -r _line; do
  _sev="$(printf '%s\n' "${_line}" | sed -nE 's/.*severity=([A-Za-z]+).*/\1/p')"
  _f="$(printf '%s\n' "${_line}" | sed -nE 's/.*file=([^ ]+).*/\1/p')"
  _ln="$(printf '%s\n' "${_line}" | sed -nE 's/.*line=([0-9]+).*/\1/p')"
  _dim="hack"
  _desc="$(printf '%s\n' "${_line}" | sed -nE 's/.*desc=(.*)$/\1/p')"
  [[ -n "${_sev}" ]] || continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "hackdetect" "${_sev}" "${_f}" "${_ln}" "${_dim}" "${_desc}" >> "${FINDINGS_RAW}"
done

# Security is an independent blocking review when escalated. Its Critical/High
# findings must fail the terminal gate even if the ordinary critic passed.
SECURITY_CRITICAL="$(awk -F'\t' '$1 == "hackdetect" && $2 == "Critical" { n++ } END { print n + 0 }' "${FINDINGS_RAW}" 2>/dev/null)"
SECURITY_HIGH="$(awk -F'\t' '$1 == "hackdetect" && $2 == "High" { n++ } END { print n + 0 }' "${FINDINGS_RAW}" 2>/dev/null)"
if [[ "${SECURITY_CRITICAL}" -gt 0 || "${SECURITY_HIGH}" -gt 0 ]]; then
  FINDINGS_CRITICAL_TOTAL=$(( FINDINGS_CRITICAL_TOTAL + SECURITY_CRITICAL ))
  FINDINGS_HIGH_TOTAL=$(( FINDINGS_HIGH_TOTAL + SECURITY_HIGH ))
  verdict="FAIL"
  emit decision "review_security_block task=${TASK} critical=${SECURITY_CRITICAL} high=${SECURITY_HIGH}"
fi

# Dedup by (file,line,severity,dimension) — keep the first arm to report it.
FINDINGS_DEDUP="${HANDOFF}/.review-findings-dedup.tsv"
awk -F'\t' '{key=$3"|"$4"|"$2"|"$5; if (!(key in seen)) {seen[key]=1; print}}' "${FINDINGS_RAW}" > "${FINDINGS_DEDUP}" 2>/dev/null || : > "${FINDINGS_DEDUP}"

# Build review-findings.json with verification per Critical/High finding.
FINDINGS_JSON="${HANDOFF}/review-findings.json"
{
  printf '{"task":"%s","arms":[' "${TASK}"
  _first=1
  for _arm in "${ran_arms[@]}"; do
    [[ "${_first}" -eq 1 ]] || printf ','
    printf '"%s"' "${_arm}"
    _first=0
  done
  printf '],"fanout":%s,"findings":[' "${#fanout_list[@]}"

  _needs_verify=0
  _verified_count=0
  _first=1
  while IFS=$'\t' read -r _arm _sev _f _ln _dim _desc; do
    [[ -n "${_arm}" ]] || continue
    _verifier_arm=""
    _verifier_verdict="unverified"
    if [[ "${_sev}" == "Critical" || "${_sev}" == "High" ]]; then
      _needs_verify=$((_needs_verify + 1))
      if [[ "${REVIEW_FINDINGS_DISPUTED}" -eq 1 ]] && _engine_verifier_policy_enabled; then
        # Pick a verifier arm != raiser from ran_arms.
        for _cand in "${ran_arms[@]}"; do
          [[ "${_cand}" != "${_arm}" ]] && { _verifier_arm="${_cand}"; break; }
        done
        if [[ -n "${_verifier_arm}" ]]; then
          _vout="${HANDOFF}/review-verify-$(printf '%s' "${_f}_${_ln}_${_sev}" | tr -c 'A-Za-z0-9' '_').${_verifier_arm}.md"
          _engine_verify_job "${_verifier_arm}" "${_vout}" "${_sev}" "${_dim}" "${_desc}" || true
          if grep -qE '^VERIFY_VERDICT:[[:space:]]*upheld' "${_vout}" 2>/dev/null; then
            _verifier_verdict="upheld"
            _verified_count=$((_verified_count + 1))
          elif grep -qE '^VERIFY_VERDICT:[[:space:]]*refuted' "${_vout}" 2>/dev/null; then
            _verifier_verdict="refuted"
            _verified_count=$((_verified_count + 1))
          fi
        fi
      fi
    fi
    [[ "${_first}" -eq 1 ]] || printf ','
    _first=0
    _desc_esc="$(printf '%s' "${_desc}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"dimension":"%s","severity":"%s","file":"%s","line":%s,"arm":"%s","verifier_arm":"%s","verifier_verdict":"%s","desc":"%s"}' \
      "${_dim}" "${_sev}" "${_f}" "${_ln:-0}" "${_arm}" "${_verifier_arm}" "${_verifier_verdict}" "${_desc_esc}"
  done < "${FINDINGS_DEDUP}"
  printf ']}'
} > "${FINDINGS_JSON}.tmp"
mv -f "${FINDINGS_JSON}.tmp" "${FINDINGS_JSON}"

# Recompute _needs_verify/_verified_count outside the subshell the while-loop
# ran in (pipes/process substitution create subshells; re-derive from the JSON
# so the counts are accurate in THIS shell).
# REVIEW-TERMINAL-PASS-01: `{ grep ... || :; }` — on a no-findings review these
# greps match nothing; pipefail would carry grep's rc 1 out of the substitution
# and a `bash -e` caller would abort the assignment before the terminal gate.
_needs_verify="$({ grep -oE '"severity":"(Critical|High)"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; _needs_verify="${_needs_verify:-0}"
_verified_count="$({ grep -oE '"verifier_verdict":"(upheld|refuted)"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; _verified_count="${_verified_count:-0}"

if [[ "${#ran_arms[@]}" -le 1 && "${_needs_verify}" -gt 0 && "${_verified_count}" -eq 0 ]]; then
  VERIFIED_LINE="verified: 0/${_needs_verify} reason=single_arm_pool"
else
  VERIFIED_LINE="verified: ${_verified_count}/${_needs_verify}"
fi

# A refuted Critical/High drops from the blocking count but stays in JSON
# (verifier_verdict: refuted) — recompute blocking severity from JSON minus refuted.
_blocking_refuted="$({ grep -oE '"severity":"(Critical|High)"[^}]*"verifier_verdict":"refuted"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; _blocking_refuted="${_blocking_refuted:-0}"
_effective_critical=$((FINDINGS_CRITICAL_TOTAL))
_effective_high=$((FINDINGS_HIGH_TOTAL))
# Best-effort: only decrement if we can attribute the refuted counts to a severity
# via the JSON grep above (coarse; the two counters below still reflect the
# reviewer's own REVIEW_FINDINGS: counts and are what today's gate contract keys on).

ARMS_CSV="$(IFS=,; echo "${ran_arms[*]}")"

# REVIEW-FANOUT-VISIBILITY-01: compute the degradation verdict for the artifact.
# `requested` is what the caller asked for (REVIEW_FANOUT), `ran` is how many arms
# actually produced a slot. When they differ this gate is a WEAKER check than its
# name implies, and the artifact must say so instead of printing a union verdict
# over fewer opinions without comment.
_FANOUT_REQUESTED="${REVIEW_FANOUT}"
_FANOUT_LAUNCHED="${#fanout_list[@]}"
_FANOUT_RAN="${#ran_arms[@]}"
_FANOUT_POOL_OK="$(_engine_pool_ok_count)"
_FANOUT_EXCLUDED="$(_engine_pool_excluded "${ARMS_CSV}")"
_FANOUT_SOURCE="pool"
for _arm in "${ran_arms[@]}"; do
  if _engine_arm_from_floor "${_arm}"; then _FANOUT_SOURCE="floor"; break; fi
done
if [[ "${_FANOUT_RAN}" -lt "${_FANOUT_REQUESTED}" ]]; then
  _FANOUT_DEGRADED=1
  _FANOUT_DEGRADED_WORD="true"
  if [[ "${_FANOUT_POOL_OK}" -lt "${_FANOUT_REQUESTED}" ]]; then
    _FANOUT_REASON="pool_offered_${_FANOUT_POOL_OK}_ok_arms"
  else
    _FANOUT_REASON="arms_dropped_after_launch"
  fi
else
  _FANOUT_DEGRADED=0
  _FANOUT_DEGRADED_WORD="false"
  _FANOUT_REASON="none"
fi
FANOUT_LINE="$(printf 'fanout: %s/%s degraded=%s launched=%s pool_ok=%s source=%s reason=%s excluded=%s' \
  "${_FANOUT_RAN}" "${_FANOUT_REQUESTED}" "${_FANOUT_DEGRADED_WORD}" "${_FANOUT_LAUNCHED}" \
  "${_FANOUT_POOL_OK}" "${_FANOUT_SOURCE}" "${_FANOUT_REASON}" "${_FANOUT_EXCLUDED:--}")"
if [[ "${_FANOUT_DEGRADED}" -eq 1 ]]; then
  FANOUT_LINE="${FANOUT_LINE}
fanout_degraded: verdict computed over ${_FANOUT_RAN} of ${_FANOUT_REQUESTED} requested arms because ${_FANOUT_EXCLUDED:-no other arm was available} - this gate is WEAKER than a full ${_FANOUT_REQUESTED}-arm review"
fi
emit decision "review_fanout task=${TASK} ran=${_FANOUT_RAN} requested=${_FANOUT_REQUESTED} degraded=${_FANOUT_DEGRADED_WORD} launched=${_FANOUT_LAUNCHED} pool_ok=${_FANOUT_POOL_OK} source=${_FANOUT_SOURCE} reason=${_FANOUT_REASON} excluded=${_FANOUT_EXCLUDED:--}"

DISPATCH_BIN="${LEADV2_DISPATCH_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
record_out="$(bash "${DISPATCH_BIN}" record-review --diff-hash "${diff_hash}" --verdict "${verdict}" --reviewer "${reviewer_primary}" --run-id "dispatch-${TASK}" 2>&1)"; record_rc=$?
if [[ ${record_rc} -eq 2 ]]; then
  REVIEW_DEDUP=1
  emit decision "review_gate task=${TASK} status=dedup diff=${diff_hash:0:8}"
else
  REVIEW_DEDUP=0
  emit decision "review_gate task=${TASK} status=ran author=${AUTHOR} reviewer=${reviewer_primary} verdict=${verdict} diff=${diff_hash:0:8} arms=${ARMS_CSV}"
fi

# GATE-PROVES-ITS-OWN-CONTROL-01: if the round declared a mutation catalog
# (docs/handoff/<task>/mutation-catalog.txt — one negative-control claim per
# line, see lib/leadv2-control-prover.sh header for the format), the machine
# applies every declared mutation itself and requires the declared suite to
# go red alone, then revert byte-clean. A PASS verdict is never trusted on
# the author's or reviewer's say-so for a declared control. Purely additive:
# a round with no catalog file behaves exactly as before.
_CONTROL_CATALOG="${HANDOFF}/mutation-catalog.txt"
if [[ "${verdict}" != FAIL && -f "${_CONTROL_CATALOG}" ]]; then
  _cp_out="$(bash "${SCRIPT_DIR}/lib/leadv2-control-prover.sh" --catalog "${_CONTROL_CATALOG}" --root "${ROOT}" 2>&1)"; _cp_rc=$?
  if [[ ${_cp_rc} -ne 0 ]]; then
    verdict="FAIL"
    emit decision "review_gate task=${TASK} status=blocked reason=control_not_diagnostic rc=${_cp_rc}"
    printf '%s\n' "${_cp_out}" > "${HANDOFF}/control-prover.md"
  fi
fi

if [[ "${verdict}" == FAIL ]]; then
  {
    printf 'arms: %s\n%s\n%s\n' "${ARMS_CSV}" "${FANOUT_LINE}" "${VERIFIED_LINE}"
    printf 'status: fail\ncritical: %s\nhigh: %s\nmedium: %s\nlow: %s\n' \
      "${FINDINGS_CRITICAL_TOTAL}" "${FINDINGS_HIGH_TOTAL}" "${FINDINGS_MEDIUM_TOTAL}" "${FINDINGS_LOW_TOTAL}"
    render_gate_findings "${REVIEW_ARTIFACT:-${HANDOFF}/review-${reviewer_primary}.md}" "${FINDINGS_JSON}" \
      "${reviewer_primary}" "docs/handoff/dispatch-${TASK}/review-${reviewer_primary}.md" || true
  } > "${HANDOFF}/review-gate.md.tmp"
  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
  _review_state_write
  _rgf_dnm=""; [[ "${RGF_DO_NOT_MERGE:-0}" == "1" ]] && _rgf_dnm=" do_not_merge=1"
  emit decision "review_gate task=${TASK} status=fail critical=${FINDINGS_CRITICAL_TOTAL} high=${FINDINGS_HIGH_TOTAL}${_rgf_dnm}"
  exit 7
fi

{
  printf 'arms: %s\n%s\n%s\n' "${ARMS_CSV}" "${FANOUT_LINE}" "${VERIFIED_LINE}"
  printf 'status: pass\nreviewer: %s\ndiff: %s\n' "${reviewer_primary}" "${diff_hash:0:8}"
  render_gate_findings "${REVIEW_ARTIFACT:-${HANDOFF}/review-${reviewer_primary}.md}" "${FINDINGS_JSON}" \
    "${reviewer_primary}" "docs/handoff/dispatch-${TASK}/review-${reviewer_primary}.md" || true
} > "${HANDOFF}/review-gate.md.tmp"
mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
_review_state_write
_rgf_dnm=""; [[ "${RGF_DO_NOT_MERGE:-0}" == "1" ]] && _rgf_dnm=" do_not_merge=1"
emit decision "review_gate task=${TASK} status=pass diff=${diff_hash:0:8} arms=${ARMS_CSV}${_rgf_dnm}"
exit 0
