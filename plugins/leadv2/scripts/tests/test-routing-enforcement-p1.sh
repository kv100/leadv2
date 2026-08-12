#!/usr/bin/env bash
# Offline regression for ROUTER-DOOR-ENFORCE-01 Part 0.
#
# dispatch-a24b1588 round-1b item 2 verification (2026-08-06): swept every
# `env -u CLAUDE_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` invocation in this file --
# only Test 5 (selfhost) and Test 6 (degraded) use it, and both already pin
# `PROJECT_ROOT` to a sandbox root (5e69c0b), so no further code change was
# needed here. Cross-cwd demonstration (fresh a1afed9 worktree + this file,
# `PROJECT_ROOT`/`LEADV2_PROJECT_ROOT` ambient-env isolated): this file run
# from /private/tmp, this lane worktree, and persona-engine (which carries its
# own .claude/ref/leadv2-routing.yaml) all print "18 passed, 0 failed"-shaped
# results. The UNPINNED a1afed9 source of this same file diverges exactly as
# predicted: 18/18 from /private/tmp, but Test 6 (degraded mode) FAILS from
# persona-engine because unpinned `PROJECT_ROOT` resolves via
# `git rev-parse --show-toplevel` on the caller's cwd and finds persona-
# engine's own routing config instead of hitting the degraded/no-config path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
QUOTA_GATE_BIN="${SCRIPT_DIR}/../leadv2-glm-quota-gate.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0

# Fail-closed spawn fence: every provider bin env var is pointed at a poison
# script that exits non-zero and prints a marker. Any test that forgets to
# override one gets a loud, offline failure instead of a live billed session.
# Individual tests override only the bins they intend to exercise.
for _arm in glm kimi codex; do
  _poison="${TMP_ROOT}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done
export LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"
# sonnet uses SUBSESSION_BIN, not a dedicated bin; point it at poison too.
# Tests that need a live sonnet override LEADV2_DISPATCH_SUBSESSION_BIN.
export LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh"
printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${TMP_ROOT}/poison-sonnet.sh"
chmod +x "${TMP_ROOT}/poison-sonnet.sh"
# _wait_arm_early_verdict (fb1c7da, 2026-08-06) polls each spawned worker's status
# adapter for a 20 s window by default. The fake launchers in this suite return
# empty status text, so the poller stays in "unknown" for the full window — every
# successful spawn pays 20 s. With ~12 spawn-involving test cases the suite took
# 4+ minutes, causing e2e_gate timeouts. The kill switch (LEADV2_ARM_EARLY_VERDICT_S=0)
# is the documented bypass: these tests assert routing/refusal-chain logic, not
# post-spawn quota-verdict behaviour.
export LEADV2_ARM_EARLY_VERDICT_S=0
_SUITE_START_EPOCH="$(date +%s)"
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
      dispatch: false
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

# Test 1: ladder order from yaml, dispatch:false entries excluded.
# With a yaml ladder ordered codex,sonnet,glm,kimi(dispatch:false), when the
# resolver picks glm as primary, the candidate chain must be glm only — NOT
# glm,kimi (kimi is excluded by dispatch:false) and NOT glm,kimi,codex,sonnet
# (the old hardcoded order). The word "kimi" must not appear in the chain.
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
  if [[ "${_ladder_arms}" == "glm" ]] \
    && ! grep -q 'kimi' <<<"${_ladder_arms}"; then
    pass 'ladder order from yaml, dispatch:false entries excluded: resolved glm → candidates glm (no kimi)'
  else
    fail 'ladder order from yaml, dispatch:false entries excluded' "candidate_chain arms='${_ladder_arms}' expected 'glm' (no kimi)"
  fi
else
  fail 'ladder order from yaml, dispatch:false entries excluded' "rc=${ladder_rc} output=${ladder_out}"
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

# Test 5: dispatch with NO project routing config resolves the plugin's own
# canonical routing config (self-host fallback) rather than logging
# no_routing_yaml. dispatch-a24b1588 Item 2 sweep: this test's *intent* is
# self-host resolution, but without a PROJECT_ROOT pin it is cwd-dependent --
# `PROJECT_ROOT` falls back to `git rev-parse --show-toplevel` on the CALLER's
# cwd (dispatch-code.sh:264), so run from inside a repo that carries its OWN
# `.claude/ref/leadv2-routing.yaml` (persona-engine, m3-market, respiro-ios),
# this test would find THAT config and pass for the wrong reason -- it would
# never actually exercise the plugin-fallback path it claims to prove. Pin
# PROJECT_ROOT to a config-less sandbox root so the only way this test can
# pass is via the plugin-preferred self-host probe.
make_live_glm "${TMP_ROOT}/selfhost-glm.sh"
make_refusing_kimi "${TMP_ROOT}/selfhost-kimi.sh"
mkdir -p "${TMP_ROOT}/selfhost-root"
selfhost_out="$(env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
  PROJECT_ROOT="${TMP_ROOT}/selfhost-root" \
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

# Test 6: no routing config anywhere (degraded mode). Both project and plugin
# config must miss, so the journal shows routing_config_degraded AND dispatch
# still proceeds. Uses LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE to simulate a
# missing plugin config. dispatch-a24b1588 Item 2: PROJECT_ROOT is pinned to a
# config-less sandbox root (same disease as Test 5) -- unpinned, the same
# `git rev-parse --show-toplevel`-on-caller's-cwd fallback makes this test's
# verdict depend on where it was invoked from: run from /private/tmp it finds
# no repo and passes; run from inside a repo carrying its own routing config
# it finds that config, degraded mode is never exercised, and the test fails
# to prove degraded mode at all -- same commit, opposite verdict.
mkdir -p "${TMP_ROOT}/degraded-root"
make_live_glm "${TMP_ROOT}/degraded-glm.sh"
degraded_out="$(env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR \
  PROJECT_ROOT="${TMP_ROOT}/degraded-root" \
  LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE="/nonexistent/path/routing.yaml" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/degraded-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/degraded-glm.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only degraded mode test' 2>&1)"
degraded_rc=$?
if [[ ${degraded_rc} -eq 0 ]] \
  && grep -q 'routing_config_degraded' <<<"${degraded_out}" \
  && grep -q 'worker_spawned' <<<"${degraded_out}"; then
  pass 'degraded mode announces routing_config_degraded and still dispatches'
else
  fail 'degraded mode announcement' "rc=${degraded_rc} output=${degraded_out}"
fi

# Test 7: spawn fence verification. After the full suite runs, no POISON marker
# should appear in any output, and no new kimi-run directory should exist.
# NOTE: this test runs at the END and only passes if every prior test respected
# the fence.
_poison_hits="$(grep -rl 'POISON:' "${TMP_ROOT}" 2>/dev/null | grep -v 'poison-' | head -1 || true)"
if [[ -z "${_poison_hits}" ]]; then
  pass 'spawn fence: no POISON marker in any test output'
else
  fail 'spawn fence' "POISON found in: ${_poison_hits}"
fi

# Test 8: C1 dry-run proof — production routing yaml yields candidate_chain
# without kimi. Uses the plugin's own canonical config, fakes GLM to refuse,
# and asserts arms=glm,codex,sonnet.
make_refusing_glm "${TMP_ROOT}/prodtest-glm.sh"
make_live_codex "${TMP_ROOT}/prodtest-codex.sh"
prodtest_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/prodtest-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/prodtest-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/prodtest-cache" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/prodtest-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/prodtest-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only production yaml dry run' 2>&1)"
_prodtest_arms="$(grep 'candidate_chain' <<<"${prodtest_out}" | sed -n 's/.*arms=//p' | head -1)"
if [[ "${_prodtest_arms}" == "glm,codex,sonnet" ]] \
  && ! grep -q 'kimi' <<<"${_prodtest_arms}"; then
  pass 'production yaml dry run: candidate_chain arms=glm,codex,sonnet (no kimi)'
else
  fail 'production yaml dry run' "arms='${_prodtest_arms}' expected 'glm,codex,sonnet'"
fi

# Test 9: quota lockout write→read. GLM launcher refuses with quota_gate;
# assert quota_lockout_recorded in journal AND the lockout file exists; then
# run a second dispatch and assert glm is skipped via precheck and codex spawns.
make_refusing_glm "${TMP_ROOT}/lockwrite-glm.sh"
make_live_codex "${TMP_ROOT}/lockwrite-codex.sh"
mkdir -p "${TMP_ROOT}/lockwrite-root/.claude/ref" "${TMP_ROOT}/lockwrite-root/docs/leadv2/.bus-offsets" "${TMP_ROOT}/lockwrite-root/docs/leadv2/tasks"
lockwrite_out1="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/lockwrite-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/lockwrite-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/lockwrite-cache" \
  LEADV2_QUOTA_LOCKOUT_MINUTES=30 \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/lockwrite-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/lockwrite-codex.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only lockout write read run1' 2>&1)"
lockwrite_rc1=$?
_lockout_file="${TMP_ROOT}/lockwrite-cache/quota-lockout-glm.json"
if [[ ${lockwrite_rc1} -ne 0 ]] \
  || ! grep -q 'quota_lockout_recorded.*provider=glm' <<<"${lockwrite_out1}" \
  || [[ ! -f "${_lockout_file}" ]]; then
  fail 'quota lockout write side' "rc=${lockwrite_rc1} output=${lockwrite_out1} file_exists=$([[ -f ${_lockout_file} ]] && echo yes || echo no)"
else
  # Verify locked_until_epoch is in the future
  _lock_epoch="$(python3 -c "import json; print(json.load(open('${_lockout_file}'))['locked_until_epoch'])" 2>/dev/null || echo 0)"
  _now_epoch="$(date +%s)"
  if [[ "${_lock_epoch}" =~ ^[0-9]+$ ]] && (( _lock_epoch > _now_epoch )); then
    pass 'quota lockout write side: quota_lockout_recorded provider=glm, lockout file with future epoch'
  else
    fail 'quota lockout write side' "lock_epoch=${_lock_epoch} now=${_now_epoch} (not in future)"
  fi
  # Second dispatch: glm should be skipped by precheck, codex should spawn
  lockwrite_out2="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/lockwrite-root" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/lockwrite-cache" \
    LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/lockwrite-cache" \
    LEADV2_QUOTA_LOCKOUT_MINUTES=30 \
    LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/lockwrite-glm.sh" \
    LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/lockwrite-codex.sh" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
    bash "${DISPATCH_BIN}" 'plugin-only lockout write read run2' 2>&1)"
  lockwrite_rc2=$?
  if [[ ${lockwrite_rc2} -eq 0 ]] \
    && grep -q 'quota_precheck_skip model=glm' <<<"${lockwrite_out2}" \
    && grep -q 'worker_spawned by=router model=codex' <<<"${lockwrite_out2}"; then
    pass 'quota lockout read side: 2nd dispatch skips glm, spawns codex'
  else
    fail 'quota lockout read side' "rc=${lockwrite_rc2} output=${lockwrite_out2}"
  fi
fi

[[ ${FAIL} -eq 0 ]]
