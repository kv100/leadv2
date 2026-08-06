#!/usr/bin/env bash
# Offline regression for ROUTER-DOOR-ENFORCE-01 Part 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
QUOTA_GATE_BIN="${SCRIPT_DIR}/../leadv2-glm-quota-gate.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

make_root() {
  local root="$1"
  mkdir -p "${root}/.claude/ref"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<'YAML'
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
YAML
}

make_refusing_glm() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate' >&2
echo '[glm-quota-gate] REROUTE — GLM quota ≥ 80% on: weekly=82%.' >&2
exit 1
SH
  chmod +x "${path}"
}

make_peak_refusing_glm() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: peak_hours' >&2
echo '[glm-quota-gate] PEAK HOURS — GLM-5.2 costs 3×.' >&2
exit 2
SH
  chmod +x "${path}"
}

make_live_glm() {
  local path="$1" delay="${2:-0}"
  cat > "${path}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  bg) sleep ${delay}; echo 'glm-test-run' ;;
  status) exit 0 ;;
  *) exit 2 ;;
esac
SH
  chmod +x "${path}"
}

make_crashing_glm() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo 'simulated launcher crash' >&2
exit 42
SH
  chmod +x "${path}"
}

make_failing_launcher() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo 'simulated launcher crash' >&2
exit 42
SH
  chmod +x "${path}"
}

# LEADV2_DISPATCH_KIMI_BIN fake: kimi is the arm tried immediately after glm in the
# free-arm chain (glm -> kimi -> codex -> sonnet). Every scenario below that makes glm
# refuse/fail MUST also fake this bin -- otherwise the real kimi-coder.sh launches a
# live, token-spending kimi-k3-free session against this checkout (discovered live
# during this task: an unfaked run spawned a real background session under
# ~/.claude/cache/kimi-runs/, killed once found). Exit 77 + the REFUSED marker mirrors
# kimi-coder.sh's own documented launch-probe-failure contract (KIMI-CHANNEL-01).
make_refusing_kimi() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo '[kimi-coder] LEADV2_DISPATCH_REFUSED: kimi_unavailable_offline_test' >&2
exit 77
SH
  chmod +x "${path}"
}

make_live_codex() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  task) echo 'Dispatch started in the background as task-test-abc123.' ;;
  status) exit 0 ;;
  *) exit 2 ;;
esac
SH
  chmod +x "${path}"
}

make_quota_live() {
  local path="$1" five="$2" weekly="$3"
  cat > "${path}" <<SH
#!/usr/bin/env bash
printf '%s\\n' '{"status":"ok","five_hour":{"pct":${five},"reset_iso":"2026-07-28T12:00:00"},"weekly":{"pct":${weekly},"reset_iso":"2026-08-01T12:00:00"}}'
SH
  chmod +x "${path}"
}

make_quota_live "${TMP_ROOT}/quota-reroute-live.sh" 81 10
quota_reroute_out="$(LEADV2_QUOTA_LIVE="${TMP_ROOT}/quota-reroute-live.sh" GLM_SIMULATE_UTC_HOUR=1 \
  bash "${QUOTA_GATE_BIN}" 2>&1)"
quota_reroute_rc=$?
if [[ ${quota_reroute_rc} -eq 1 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' <<<"${quota_reroute_out}"; then
  pass 'quota gate emits machine-readable reroute marker'
else
  fail 'quota gate reroute marker' "rc=${quota_reroute_rc} output=${quota_reroute_out}"
fi

make_quota_live "${TMP_ROOT}/quota-peak-live.sh" 10 10
quota_peak_out="$(LEADV2_QUOTA_LIVE="${TMP_ROOT}/quota-peak-live.sh" GLM_SIMULATE_UTC_HOUR=6 \
  bash "${QUOTA_GATE_BIN}" 2>&1)"
quota_peak_rc=$?
if [[ ${quota_peak_rc} -eq 2 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: peak_hours' <<<"${quota_peak_out}"; then
  pass 'quota gate emits machine-readable peak marker'
else
  fail 'quota gate peak marker' "rc=${quota_peak_rc} output=${quota_peak_out}"
fi

make_root "${TMP_ROOT}/refusal-root"
make_refusing_glm "${TMP_ROOT}/refusing-glm.sh"
make_refusing_kimi "${TMP_ROOT}/refusing-kimi-1.sh"
make_live_codex "${TMP_ROOT}/live-codex.sh"
refusal_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/refusal-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/refusal-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/refusing-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/refusing-kimi-1.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/live-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only quota refusal advances chain' 2>&1)"
refusal_rc=$?
if [[ ${refusal_rc} -eq 0 ]] \
  && grep -q 'reason=glm_refused_quota_gate' <<<"${refusal_out}" \
  && grep -q 'worker_spawned by=router model=codex' <<<"${refusal_out}" \
  && ! grep -q 'dispatch_rolled_back' <<<"${refusal_out}" \
  && ! grep -q 'spawn_failed by=router model=glm' <<<"${refusal_out}"; then
  pass 'quota refusal journals refusal and advances GLM -> Codex'
else
  fail 'quota refusal advances chain' "rc=${refusal_rc} output=${refusal_out}"
fi

make_root "${TMP_ROOT}/peak-root"
make_peak_refusing_glm "${TMP_ROOT}/peak-glm.sh"
make_refusing_kimi "${TMP_ROOT}/refusing-kimi-2.sh"
peak_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/peak-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/peak-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/peak-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/refusing-kimi-2.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/live-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only peak refusal advances chain' 2>&1)"
peak_rc=$?
if [[ ${peak_rc} -eq 0 ]] \
  && grep -q 'reason=glm_refused_peak_hours' <<<"${peak_out}" \
  && grep -q 'worker_spawned by=router model=codex' <<<"${peak_out}" \
  && ! grep -q 'spawn_failed by=router model=glm' <<<"${peak_out}"; then
  pass 'peak-hours refusal journals refusal and advances GLM -> Codex'
else
  fail 'peak-hours refusal advances chain' "rc=${peak_rc} output=${peak_out}"
fi

make_root "${TMP_ROOT}/crash-root"
make_crashing_glm "${TMP_ROOT}/crashing-glm.sh"
make_failing_launcher "${TMP_ROOT}/failing-kimi.sh"
make_failing_launcher "${TMP_ROOT}/failing-codex.sh"
make_failing_launcher "${TMP_ROOT}/failing-sonnet.sh"
crash_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/crash-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/crash-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/crashing-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/failing-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/failing-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/failing-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only launcher crash stays failure' 2>&1)"
crash_rc=$?
if [[ ${crash_rc} -eq 4 ]] \
  && grep -q 'spawn_failed by=router model=glm.*rc=42.*reason=launcher_nonzero_exit' <<<"${crash_out}" \
  && ! grep -q 'glm_refused_' <<<"${crash_out}" \
  && grep -q 'dispatch_rolled_back reason=all_arms_unavailable.*glm_failed_launcher' <<<"${crash_out}"; then
  pass 'launcher crash remains a failure'
else
  fail 'launcher crash remains failure' "rc=${crash_rc} output=${crash_out}"
fi

make_root "${TMP_ROOT}/dedup-root"
make_live_glm "${TMP_ROOT}/live-glm.sh"
dedup_first="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/dedup-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/dedup-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/live-glm.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only one mission only once' 2>&1)"
dedup_first_rc=$?
dedup_second="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/dedup-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/dedup-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/live-glm.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only one mission only once' 2>&1)"
dedup_second_rc=$?
if [[ ${dedup_first_rc} -eq 0 && ${dedup_second_rc} -eq 2 ]] \
  && grep -q 'dispatch_refused reason=duplicate_task_signature' <<<"${dedup_second}"; then
  pass 'duplicate dispatch is refused and journalled'
else
  fail 'duplicate dispatch refusal' "first_rc=${dedup_first_rc} second_rc=${dedup_second_rc} output=${dedup_first} ${dedup_second}"
fi

diff_hash='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
review_first="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/dedup-root" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/review-cache" \
  bash "${DISPATCH_BIN}" record-review --diff-hash "${diff_hash}" --verdict PASS 2>&1)"
review_first_rc=$?
review_second="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/dedup-root" LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/review-cache" \
  bash "${DISPATCH_BIN}" record-review --diff-hash "${diff_hash}" --verdict PASS 2>&1)"
review_second_rc=$?
if [[ ${review_first_rc} -eq 0 && ${review_second_rc} -eq 2 ]] \
  && grep -q 'review_refused reason=duplicate_diff_hash' <<<"${review_second}"; then
  pass 'record-review refuses duplicate diff hash'
else
  fail 'duplicate review refusal' "first_rc=${review_first_rc} second_rc=${review_second_rc} output=${review_first} ${review_second}"
fi

make_root "${TMP_ROOT}/race-root"
make_live_glm "${TMP_ROOT}/slow-glm.sh" 1
race_cache="${TMP_ROOT}/race-cache"
CLAUDE_PROJECT_ROOT="${TMP_ROOT}/race-root" LEADV2_DISPATCH_CACHE_DIR="${race_cache}" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/slow-glm.sh" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only racing reservation' >"${TMP_ROOT}/race-one.out" 2>&1 &
race_one_pid=$!
sleep 0.1
CLAUDE_PROJECT_ROOT="${TMP_ROOT}/race-root" LEADV2_DISPATCH_CACHE_DIR="${race_cache}" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/slow-glm.sh" LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only racing reservation' >"${TMP_ROOT}/race-two.out" 2>&1 &
race_two_pid=$!
wait "${race_one_pid}"; race_one_rc=$?
wait "${race_two_pid}"; race_two_rc=$?
race_successes=0; [[ ${race_one_rc} -eq 0 ]] && race_successes=$((race_successes + 1)); [[ ${race_two_rc} -eq 0 ]] && race_successes=$((race_successes + 1))
race_refusals=0; [[ ${race_one_rc} -eq 2 ]] && race_refusals=$((race_refusals + 1)); [[ ${race_two_rc} -eq 2 ]] && race_refusals=$((race_refusals + 1))
if [[ ${race_successes} -eq 1 && ${race_refusals} -eq 1 ]] \
  && (grep -q 'dispatch_refused reason=duplicate_task_signature' "${TMP_ROOT}/race-one.out" || grep -q 'dispatch_refused reason=duplicate_task_signature' "${TMP_ROOT}/race-two.out"); then
  pass 'racing reserves admit exactly one dispatch'
else
  fail 'racing reserve exclusivity' "rcs=${race_one_rc},${race_two_rc} outputs=$(cat "${TMP_ROOT}/race-one.out") $(cat "${TMP_ROOT}/race-two.out")"
fi

# ── ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 tests ──────────────────────────────────

# Helper: make a root whose routing YAML has a custom dispatch_ladder.
make_ladder_root() {
  local root="$1" ladder_yaml="$2"
  mkdir -p "${root}/.claude/ref"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<YAML
${ladder_yaml}
router:
  dispatch_ladder:
    - id: codex
      provider: codex
      model: gpt-5.6-terra
      when: [all]
      effort: standard
    - id: sonnet
      provider: anthropic
      model: sonnet
      when: [all]
      effort: standard
    - id: glm
      provider: glm
      model: glm-5.2
      when: [all]
      effort: standard
    - id: kimi
      provider: kimi
      model: moonshotai/kimi-k3-free
      when: [all]
      effort: standard
YAML
}

# Helper: write a per-provider quota lockout record.
make_lockout() {
  local dir="$1" provider="$2" locked_until_epoch="$3" source="${4:-test}"
  mkdir -p "${dir}" 2>/dev/null
  cat > "${dir}/quota-lockout-${provider}.json" <<JSON
{"provider":"${provider}","locked_until":"${locked_until_epoch}","locked_until_epoch":${locked_until_epoch},"source":"${source}"}
JSON
}

# Test 1: ladder order comes from the yaml. With a yaml ladder ordered
# codex,sonnet,glm,kimi, when the resolver picks glm as primary, the candidate
# chain must be glm,kimi (glm's position onward) — NOT the hardcoded
# glm,kimi,codex,sonnet. This FAILS on HEAD (hardcoded order) and passes
# after the change.
make_ladder_root "${TMP_ROOT}/ladder-root" ""
make_live_glm "${TMP_ROOT}/ladder-glm.sh"
make_refusing_kimi "${TMP_ROOT}/ladder-kimi.sh"
make_live_codex "${TMP_ROOT}/ladder-codex.sh"
ladder_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/ladder-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/ladder-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/ladder-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/ladder-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/ladder-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only ladder from yaml' 2>&1)"
ladder_rc=$?
if [[ ${ladder_rc} -eq 0 ]] \
  && grep -q 'candidate_chain' <<<"${ladder_out}"; then
  _ladder_arms="$(grep 'candidate_chain' <<<"${ladder_out}" | sed -n 's/.*arms=//p')"
  if [[ "${_ladder_arms}" == "glm,kimi" ]]; then
    pass 'ladder order from yaml: resolved glm → candidates glm,kimi (not glm,kimi,codex,sonnet)'
  else
    fail 'ladder order from yaml' "candidate_chain arms='${_ladder_arms}' expected 'glm,kimi'"
  fi
else
  fail 'ladder order from yaml' "rc=${ladder_rc} output=${ladder_out}"
fi

# Test 2: a provider marked locked-until-future is skipped and the next arm
# is chosen, with the skip journalled. FAILS on HEAD (no precheck exists).
make_root "${TMP_ROOT}/lockout-root"
make_live_glm "${TMP_ROOT}/lockout-glm.sh"
make_refusing_kimi "${TMP_ROOT}/lockout-kimi.sh"
make_live_codex "${TMP_ROOT}/lockout-codex.sh"
_future_epoch=$(( $(date +%s) + 86400 ))
make_lockout "${TMP_ROOT}/lockout-cache" "glm" "${_future_epoch}" "test_quota_lockout"
lockout_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/lockout-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/lockout-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/lockout-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/lockout-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/lockout-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/lockout-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only lockout skips glm' 2>&1)"
lockout_rc=$?
if [[ ${lockout_rc} -eq 0 ]] \
  && grep -q 'quota_precheck_skip model=glm' <<<"${lockout_out}" \
  && grep -q 'worker_spawned by=router model=codex' <<<"${lockout_out}"; then
  pass 'quota precheck skips locked provider and journals the skip'
else
  fail 'quota precheck skip' "rc=${lockout_rc} output=${lockout_out}"
fi

# Test 3: a lockout in the past is ignored — glm dispatches AND codex is
# simultaneously skipped (locked future). On HEAD neither the past-lockout
# check nor the codex skip exists. FAILS on HEAD.
make_root "${TMP_ROOT}/pastlock-root"
make_live_glm "${TMP_ROOT}/pastlock-glm.sh"
make_refusing_kimi "${TMP_ROOT}/pastlock-kimi.sh"
make_live_codex "${TMP_ROOT}/pastlock-codex.sh"
_past_epoch=$(( $(date +%s) - 3600 ))
make_lockout "${TMP_ROOT}/pastlock-cache" "glm" "${_past_epoch}" "expired_lockout"
# Also lock codex with a FUTURE timestamp so the test asserts the precheck
# ran (codex IS skipped) while glm (past lockout) is NOT skipped.
make_lockout "${TMP_ROOT}/pastlock-cache" "codex" "${_future_epoch}" "test_codex_lock"
pastlock_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/pastlock-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/pastlock-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/pastlock-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/pastlock-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/pastlock-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/pastlock-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only past lockout ignored future codex locked' 2>&1)"
pastlock_rc=$?
if [[ ${pastlock_rc} -eq 0 ]] \
  && grep -q 'worker_spawned by=router model=glm' <<<"${pastlock_out}" \
  && ! grep -q 'quota_precheck_skip model=glm' <<<"${pastlock_out}" \
  && grep -q 'quota_precheck_skip model=codex' <<<"${pastlock_out}"; then
  pass 'past lockout is ignored for glm while future lockout skips codex'
else
  fail 'past lockout ignored' "rc=${pastlock_rc} output=${pastlock_out}"
fi

# Test 4: an absent lockout record does not block glm, AND a present
# future-lockout on codex IS enforced. On HEAD the codex skip does not
# happen. FAILS on HEAD.
make_root "${TMP_ROOT}/nolock-root"
make_live_glm "${TMP_ROOT}/nolock-glm.sh"
make_refusing_kimi "${TMP_ROOT}/nolock-kimi.sh"
make_live_codex "${TMP_ROOT}/nolock-codex.sh"
# No lockout for glm — but lock codex with a future timestamp.
make_lockout "${TMP_ROOT}/nolock-cache" "codex" "${_future_epoch}" "test_codex_lock2"
nolock_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/nolock-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/nolock-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/nolock-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/nolock-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/nolock-kimi.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/nolock-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only no glm lockout codex locked' 2>&1)"
nolock_rc=$?
if [[ ${nolock_rc} -eq 0 ]] \
  && grep -q 'worker_spawned by=router model=glm' <<<"${nolock_out}" \
  && ! grep -q 'quota_precheck_skip model=glm' <<<"${nolock_out}" \
  && grep -q 'quota_precheck_skip model=codex' <<<"${nolock_out}"; then
  pass 'absent glm lockout does not block while codex lockout is enforced'
else
  fail 'absent lockout no-block' "rc=${nolock_rc} output=${nolock_out}"
fi

# Test 5: dispatch with cwd = the plugin repo resolves a routing config
# rather than logging no_routing_yaml. FAILS on HEAD (logs no_routing_yaml).
make_live_glm "${TMP_ROOT}/selfhost-glm.sh"
make_refusing_kimi "${TMP_ROOT}/selfhost-kimi.sh"
selfhost_out="$(env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/selfhost-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/selfhost-glm.sh" \
  LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/selfhost-kimi.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only selfhost routing' 2>&1)"
selfhost_rc=$?
if [[ ${selfhost_rc} -eq 0 ]] \
  && ! grep -q 'no_routing_yaml' <<<"${selfhost_out}"; then
  pass 'dispatch from plugin repo resolves routing config (no no_routing_yaml)'
else
  fail 'plugin self-host routing' "rc=${selfhost_rc} output=${selfhost_out}"
fi

[[ ${FAIL} -eq 0 ]]
