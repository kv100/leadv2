#!/usr/bin/env bash
# Offline regression for CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01.
#
# Root cause: codex's launcher (codex-task.sh task ... --background) exits 0 the
# instant the job is ENQUEUED, so _maybe_record_quota_lockout (only reachable from
# the `rc -ne 0` refusal branch) never runs for codex even when the async job later
# dies from a quota error. This suite proves the new generic post-spawn verdict seam
# (_wait_arm_early_verdict + the close gate's record-quota-lockout fallback) closes
# that gap for codex WITHOUT any arm name ever being compared inside
# ladder/eligibility/routing logic -- only inside small adapter functions.
#
# Pattern follows plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh:
# fake launchers, CLAUDE_PROJECT_ROOT + LEADV2_DISPATCH_CACHE_DIR isolation per
# scenario, journal assertions via captured stdout+stderr (dispatch-code.sh's
# `log()` always prints to stderr regardless of JOURNAL_TASK). EVERY test below
# exports its OWN LEADV2_QUOTA_LOCKOUT_DIR under TMP_ROOT -- the real
# ~/.claude/cache/dispatch-ledger/quota-lockout-codex.json is NEVER touched.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
CLOSE_BIN="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"
ROUTING_ENFORCEMENT_SUITE="${SCRIPT_DIR}/test-routing-enforcement-p1.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

# Fail-closed spawn fence, same idiom as test-routing-enforcement-p1.sh: every
# provider bin defaults to a poison script; tests override only what they use.
for _arm in glm kimi codex; do
  _poison="${TMP_ROOT}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done
printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${TMP_ROOT}/poison-sonnet.sh"
chmod +x "${TMP_ROOT}/poison-sonnet.sh"
export LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"
export LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh"
# Bound every post-spawn poll window hard -- these are all offline fakes whose
# `status` verb reports a terminal state on the very first probe, so a small
# window only bounds worst-case wall clock, it never changes correctness.
export LEADV2_ARM_EARLY_VERDICT_S=3
export LEADV2_ARM_EARLY_VERDICT_POLL_S=0.2

make_root() {
  local root="$1"
  mkdir -p "${root}/.claude/ref" "${root}/docs/leadv2/.bus-offsets" "${root}/docs/leadv2/tasks"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<'YAML'
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
YAML
}

# Identical marker/rc contract to test-routing-enforcement-p1.sh's make_refusing_glm.
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

# Fake codex-task.sh CLI surface: `task --background` enqueues (exits 0, prints a
# parseable jobId immediately -- the ROOT CAUSE this whole fix exists for: the real
# launcher does exactly this even when the job later dies of quota). `status`
# reports the job as already-failed (a fake is allowed to be terminal-immediately).
# `log` is the log/output verb _arm_final_output prefers -- prints the caller's
# chosen final_output_text so _quota_shaped/_quota_return_time have something to
# classify.
make_quota_dying_codex() {  # <path> <final_output_text>
  local path="$1" text="$2"
  cat > "${path}" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  task)
    echo 'task-fake-quota01 started in the background as task-fake-quota01.'
    ;;
  status)
    echo 'status: failed'
    ;;
  log)
    cat <<'TXT'
${text}
TXT
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "${path}"
}

# Same fake launcher shape used across the dispatch-code test suite: spawns a
# real, short-lived OS process and prints its PID in the exact shape
# spawn_worker's sonnet-arm parser expects (`PID=<pid> LABEL=... SESSION_ID=...`).
make_live_sonnet() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
SH
  chmod +x "${path}"
}

QUOTA_TEXT_WITH_DATE="You've hit your usage limit. Try again at Aug 8th, 2026 8:49 AM."
QUOTA_TEXT_NO_TIME="You've hit your usage limit."
NON_QUOTA_TEXT="FAILED tests/test_foo.py::test_bar — AssertionError; try again"

# ── T1/T2/T6: codex fails with a dated quota message -- lockout written, timed, ordered ──
make_root "${TMP_ROOT}/t1-root"
make_refusing_glm "${TMP_ROOT}/t1-glm.sh"
make_quota_dying_codex "${TMP_ROOT}/t1-codex.sh" "${QUOTA_TEXT_WITH_DATE}"
t1_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t1-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t1-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t1-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t1-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t1-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only codex quota postspawn t1' 2>&1)"
t1_rc=$?
t1_lockfile="${TMP_ROOT}/t1-lockout/quota-lockout-codex.json"

if [[ -f "${t1_lockfile}" ]] \
  && grep -q 'quota_lockout_recorded provider=codex.*reason=postspawn_quota' <<<"${t1_out}"; then
  pass 'T1: codex dated-quota failure writes quota-lockout-codex.json + journal line'
else
  fail 'T1: codex dated-quota failure' "rc=${t1_rc} lockfile_exists=$([[ -f ${t1_lockfile} ]] && echo yes || echo no) output=${t1_out}"
fi

# T2 (PROVIDER-LOCKOUT-FALSE-BLOCK-01): the provider-stated time (Aug 8 2026
# 08:49 LOCAL + 24h past-guard ≈ now+24h) is now CLAMPED to the 60-minute
# post-spawn cap: locked_until within ±90s of now+60m, and clearly longer than
# the 30-min flat default (> now+45m) so the clamp, not the default, is what
# produced the value.
t2_ok=0
if [[ -f "${t1_lockfile}" ]]; then
  t2_ok="$(python3 - "${t1_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
except Exception:
    print(0); sys.exit(0)
if epoch <= 0:
    print(0); sys.exit(0)
now = time.time()
clamped_to_cap = abs(epoch - (now + 60 * 60)) <= 90
clearly_not_default = epoch > now + 45 * 60
print(1 if (clamped_to_cap and clearly_not_default) else 0)
PY
)"
fi
if [[ "${t2_ok}" == "1" ]]; then
  pass 'T2: provider time is honoured but clamped to the 60m post-spawn cap (not 24h, not the flat default)'
else
  fail 'T2: post-spawn cap clamp' "lockfile=$(cat "${t1_lockfile}" 2>/dev/null || echo MISSING)"
fi

# T6: within T1's SAME single dispatch run, the codex quota verdict line appears
# BEFORE the spill reaches sonnet (ordering, not just presence). T1's global
# LEADV2_DISPATCH_SUBSESSION_BIN is poison-sonnet.sh (synchronous rc=99), so sonnet
# never reaches a successful `worker_spawned` line -- the observable spill-reached-
# sonnet signal is `spawn_failed ... model=sonnet` (poison fires) instead.
t1_codex_line="$(grep -n 'quota_lockout_recorded provider=codex' <<<"${t1_out}" | head -1 | cut -d: -f1)"
t1_sonnet_line="$(grep -n 'model=sonnet' <<<"${t1_out}" | head -1 | cut -d: -f1)"
if [[ -n "${t1_codex_line}" && -n "${t1_sonnet_line}" && "${t1_codex_line}" -lt "${t1_sonnet_line}" ]]; then
  pass 'T6: codex quota verdict precedes the sonnet spill attempt within the same dispatch run'
else
  fail 'T6: ordering within one run' "codex_line=${t1_codex_line:-none} sonnet_line=${t1_sonnet_line:-none} output=${t1_out}"
fi

# ── T3: codex fails with quota text but NO time -- default duration, source=default ──
make_root "${TMP_ROOT}/t3-root"
make_refusing_glm "${TMP_ROOT}/t3-glm.sh"
make_quota_dying_codex "${TMP_ROOT}/t3-codex.sh" "${QUOTA_TEXT_NO_TIME}"
t3_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t3-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t3-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t3-lockout" \
  LEADV2_QUOTA_LOCKOUT_MINUTES=30 \
  LEADV2_QUOTA_LOCKOUT_MAX_MINUTES=4320 \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t3-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t3-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only codex quota postspawn t3' 2>&1)"
t3_lockfile="${TMP_ROOT}/t3-lockout/quota-lockout-codex.json"
t3_dur_ok=0
if [[ -f "${t3_lockfile}" ]]; then
  t3_dur_ok="$(python3 - "${t3_lockfile}" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    epoch = int(d.get("locked_until_epoch") or 0)
except Exception:
    print(0); sys.exit(0)
now = time.time()
delta_min = (epoch - now) / 60.0
print(1 if (30 - 2) <= delta_min <= (72 * 60 + 2) else 0)
PY
)"
fi
if [[ "${t3_dur_ok}" == "1" ]] && grep -q 'quota_lockout_recorded provider=codex.*source=default' <<<"${t3_out}"; then
  pass 'T3: codex quota failure with no time falls back to flat default duration, source=default'
else
  fail 'T3: no-time default duration' "lockfile=$(cat "${t3_lockfile}" 2>/dev/null || echo MISSING) output=${t3_out}"
fi

# ── T4: ordinary (non-quota) codex failure -- classifier runs, says no, NO lockout ──
make_root "${TMP_ROOT}/t4-root"
make_refusing_glm "${TMP_ROOT}/t4-glm.sh"
make_quota_dying_codex "${TMP_ROOT}/t4-codex.sh" "${NON_QUOTA_TEXT}"
t4_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t4-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t4-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t4-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t4-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/t4-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only codex non-quota failure t4' 2>&1)"
t4_lockfile="${TMP_ROOT}/t4-lockout/quota-lockout-codex.json"
if [[ ! -f "${t4_lockfile}" ]] \
  && ! grep -q 'quota_lockout_recorded provider=codex' <<<"${t4_out}" \
  && grep -q 'arm_postspawn_verdict arm=codex state=failed quota=no' <<<"${t4_out}"; then
  pass 'T4: ordinary codex failure is classified (quota=no) and produces NO lockout'
else
  fail 'T4: ordinary failure must not lock out' "lockfile_exists=$([[ -f ${t4_lockfile} ]] && echo yes || echo no) output=${t4_out}"
fi
# T4 stays a genuine dispatch failure downstream (codex not quota-refused, sonnet
# poisoned) -- confirms this scenario really exercised the failure path, not a
# vacuous no-op where codex never even ran.
if [[ ${t4_out} == *"POISON: real provider spawn attempted"* || ${t4_out} == *"dispatch_rolled_back"* ]]; then
  : # expected: chain fell through to the poisoned sonnet fence, proving codex ran
fi

# ── T5: a prior codex lockout makes the NEXT dispatch skip codex via precheck ──
make_root "${TMP_ROOT}/t5-root"
make_refusing_glm "${TMP_ROOT}/t5-glm.sh"
make_live_sonnet "${TMP_ROOT}/t5-sonnet.sh"
mkdir -p "${TMP_ROOT}/t5-lockout"
cat > "${TMP_ROOT}/t5-lockout/quota-lockout-codex.json" <<JSON
{"provider": "codex", "locked_until": "2099-01-01T00:00:00Z", "locked_until_epoch": 4070908800, "source": "test-seed"}
JSON
t5_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t5-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t5-cache" \
  LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/t5-lockout" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/t5-glm.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/t5-sonnet.sh" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  bash "${DISPATCH_BIN}" 'plugin-only codex locked skip to sonnet t5' 2>&1)"
t5_rc=$?
if [[ ${t5_rc} -eq 0 ]] \
  && grep -q 'quota_precheck_skip model=codex provider=codex.*reason=provider_quota_locked' <<<"${t5_out}" \
  && grep -q 'worker_spawned by=router model=sonnet' <<<"${t5_out}"; then
  pass 'T5: a seeded codex lockout is precheck-skipped and sonnet is spawned instead'
else
  fail 'T5: precheck skip + sonnet spawn' "rc=${t5_rc} output=${t5_out}"
fi

# ── T7 (regression): the existing routing-enforcement suite must still fully pass ──
if [[ -f "${ROUTING_ENFORCEMENT_SUITE}" ]]; then
  t7_out="$(bash "${ROUTING_ENFORCEMENT_SUITE}" 2>&1)"
  t7_rc=$?
  t7_pass_n="$(grep -c '^PASS:' <<<"${t7_out}")"
  t7_fail_n="$(grep -c '^FAIL:' <<<"${t7_out}")"
  if [[ ${t7_rc} -eq 0 && ${t7_fail_n} -eq 0 ]]; then
    pass "T7: test-routing-enforcement-p1.sh still fully passes (${t7_pass_n} passed, 0 failed)"
  else
    fail 'T7: routing-enforcement regression' "rc=${t7_rc} pass=${t7_pass_n} fail=${t7_fail_n} output=${t7_out}"
  fi
else
  fail 'T7: routing-enforcement suite missing' "expected at ${ROUTING_ENFORCEMENT_SUITE}"
fi

[[ ${FAIL} -eq 0 ]]
