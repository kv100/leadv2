#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-review-run.sh leadv2-suite-falsifiable
# test-suite-falsifiable.sh — SUITE-THAT-CANNOT-FAIL-01.
#
# Tests leadv2-suite-falsifiable.sh (the behavioural falsifiability checker)
# and its wiring into leadv2-review-run.sh, against FIXTURE suites only —
# never a real lane, never the real review.
#
# Cases (mirroring the lane's acceptance list):
#   1. honest suite with real assertions            ⇒ falsifiable (rc 0)
#   2. prints FAIL: but always exits 0              ⇒ NOT falsifiable (rc 1)
#   3. test-resume-lane-arg-shapes.sh's exact shape ⇒ NOT falsifiable (rc 1)
#   4. red at baseline (missing dependency)         ⇒ could-not-determine (rc 2)
#   5. review-run, changed suite not falsifiable    ⇒ verdict is NOT pass
#   6. review-run, changed suite falsifiable        ⇒ verdict path unchanged
#   7. review-run, no suite in the diff             ⇒ gate does not fire
#   8. self-application: this suite must itself be reported falsifiable
#   9. PPC-G1: default watchdog timeout (no env override) must be >=120s —
#      the 60s default produced a false "timed out" verdict on a suite that
#      took 71s under concurrent-lane load (BEAT-LOOP-ORPHANS-01 incident)
#  10. PPC-G1: a suite that genuinely hangs past the (overridden, small)
#      timeout is still killed and reported "timed out" — the watchdog must
#      not become toothless just because the default grew
#  11. PPC-G1: a suite that finishes with margin under the timeout still gets
#      a real (non-timeout) verdict — the raised default must not itself
#      break the case it exists to protect
#
# Every case asserts on exit codes / artifact contents; a failed case makes
# the whole suite exit non-zero. A printed FAIL: line that leaves $? at 0 is
# not an assertion — this suite obeys the rule it enforces.
#
# Bash 3.2 compatible; arrays guarded under set -u.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${SCRIPT_DIR}/../leadv2-suite-falsifiable.sh"
REVIEW_RUN="${SCRIPT_DIR}/../leadv2-review-run.sh"
RUN_ALL="${SCRIPT_DIR}/../../../../tests/run-all.sh"

PASS=0
FAIL=0
declare -a CLEANUP_PATHS=()
cleanup() {
  local p
  for p in "${CLEANUP_PATHS[@]:-}"; do
    [[ -n "${p}" ]] && rm -rf "${p}"
  done
  # A nested run must NEVER delete the guard file: it belongs to the outer
  # run that created it (a nested deletion re-opens recursion for the outer
  # run's later probes).
  [[ "${NESTED:-0}" == "1" ]] || rm -f "${GUARD_FILE:-/dev/null}" 2>/dev/null
}
trap cleanup EXIT

log() { printf '%s\n' "$*"; }
ok()  { PASS=$((PASS + 1)); log "PASS: $*"; }
no()  { FAIL=$((FAIL + 1)); log "FAIL: $*"; }

check() { # <label> <expected-rc> <actual-rc>
  if [[ "$3" == "$2" ]]; then ok "$1 (rc=$3)"; else no "$1 (expected rc=$2, got rc=$3)"; fi
}

# Recursion guard for case 8 (set there, inherited by nested runs). A nested
# run still executes the checker cases 1-4 — they carry real assertions, so
# the checker probing this suite can still observe it going red — but skips
# the expensive review-run cases 5-7 and case 8 itself.
# The guard is BOTH an env var and a TMPDIR sentinel file: the checker's
# stripped_env probe (env -i) deletes every environment variable, so the env
# var alone would let recursion restart under that probe — the file survives
# it (TMPDIR is preserved). Fixed name is deliberate: nested processes must
# find it without being told its path.
GUARD_FILE="${TMPDIR:-/tmp}/leadv2-test-suite-falsifiable-selfguard"
if [[ "${LEADV2_SSF_SELF_GUARD:-0}" == "1" || -f "${GUARD_FILE}" ]]; then
  NESTED=1
else
  NESTED=0
fi

fx() { mktemp -d "${TMPDIR:-/tmp}/leadv2-suite-falsifiable-test.XXXXXX"; }

export LEADV2_SUITE_FALSIFIABLE_TIMEOUT="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-20}"

bash -n "${CHECKER}"    && ok "bash -n clean (leadv2-suite-falsifiable.sh)"    || no "bash -n failed (leadv2-suite-falsifiable.sh)"
/bin/bash -n "${CHECKER}" && ok "/bin/bash 3.2 -n clean (checker)"             || no "/bin/bash 3.2 -n failed (checker)"
bash -n "${REVIEW_RUN}" && ok "bash -n clean (leadv2-review-run.sh)"           || no "bash -n failed (leadv2-review-run.sh)"
if [[ -f "${RUN_ALL}" ]]; then
  bash -n "${RUN_ALL}" && ok "bash -n clean (tests/run-all.sh)"                || no "bash -n failed (tests/run-all.sh)"
fi

# ── Fixtures ────────────────────────────────────────────────────────────────
FIX="$(fx)"; CLEANUP_PATHS+=("${FIX}")
mkdir -p "${FIX}/scripts/tests"

# 1. honest suite: real assertion, can go red
cat > "${FIX}/honest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TMP="$(mktemp)"
echo "test content: hello world" > "${TMP}"
if ! grep -q "hello world" "${TMP}"; then
  echo "FAIL: content mismatch"
  rm -f "${TMP}"
  exit 1
fi
rm -f "${TMP}"
echo "PASS"
exit 0
EOF
chmod +x "${FIX}/honest.sh"

# 2. lying suite: prints FAIL: but always exits 0 (zero external dependencies —
# the hard case: no shim ever engages, yet the verdict must be definitive)
cat > "${FIX}/printer.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Running fake suite..."
echo "FAIL: This is a fake failure"
echo "PASS: But we always exit 0"
exit 0
EOF
chmod +x "${FIX}/printer.sh"

# 3. the exact shape of test-resume-lane-arg-shapes.sh (commit 0d61b3c):
# prints commands/exit codes, swallows every failure with `|| true`, ends
# "All tests completed" with no assertion anywhere.
mkdir -p "${FIX}/shape/scripts/tests"
cat > "${FIX}/shape/scripts/tests/test-resume-lane-arg-shapes.sh" <<'EOF'
#!/usr/bin/env bash

# Test script for verifying --resume-lane argument shapes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SCRIPT="${SCRIPT_DIR}/../../leadv2-dispatch-code.sh"

FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_WORKTREE_DIR="${FIXTURE_ROOT}/.claude/worktrees"
mkdir -p "${FIXTURE_WORKTREE_DIR}"

TEST_LANE_NAME="test-lane"
TEST_LANE_WORKTREE="${FIXTURE_WORKTREE_DIR}/${TEST_LANE_NAME}"
mkdir -p "${TEST_LANE_WORKTREE}"

TEST_MISSION_FILE="${FIXTURE_ROOT}/test-mission.md"
echo "# Test Mission" > "${TEST_MISSION_FILE}"

run_dispatch() {
  local args=("${DISPATCH_SCRIPT}" "--mission" "${TEST_MISSION_FILE}" "$@")
  local output
  local rc

  output=$("${args[@]}" 2>&1 || true)
  rc=$?

  echo "Command: ${args[*]}"
  echo "Exit code: $rc"
  echo "Output:"
  echo "$output"
  echo "---"

  return $rc
}

run_dispatch "--resume-lane" "${TEST_LANE_NAME}"
run_dispatch "--resume-lane" "${TEST_LANE_WORKTREE}"
BAD_PATH="/tmp/nonexistent-path"
run_dispatch "--resume-lane" "${BAD_PATH}"
DOUBLED_PATH="${FIXTURE_ROOT}/.claude/worktrees/.claude/worktrees/test-doubled"
run_dispatch "--resume-lane" "${DOUBLED_PATH}"

rm -rf "${FIXTURE_ROOT}"

echo "All tests completed"
EOF
chmod +x "${FIX}/shape/scripts/tests/test-resume-lane-arg-shapes.sh"
cat > "${FIX}/shape/scripts/leadv2-dispatch-code.sh" <<'EOF'
#!/usr/bin/env bash
# stub dispatcher (the real one refuses these shapes with exit 1)
grep -q "^" /dev/null || true
echo "resume-lane: refusing (stub)"
exit 1
EOF
chmod +x "${FIX}/shape/scripts/leadv2-dispatch-code.sh"

# 4. red at baseline: missing dependency
cat > "${FIX}/missing-dep.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Running..."
this-command-does-not-exist-anywhere --some-arg
echo "PASS"
exit 0
EOF
chmod +x "${FIX}/missing-dep.sh"

# ── Checker cases 1-4 ───────────────────────────────────────────────────────
out="$(bash "${CHECKER}" "${FIX}/honest.sh" 2>&1)"; rc=$?
check "case1 honest suite reported falsifiable" 0 "${rc}"
printf '%s\n' "${out}" | grep -q 'verdict: falsifiable' \
  && ok "case1 verdict line says falsifiable" \
  || no "case1 verdict line missing 'verdict: falsifiable'"

out="$(bash "${CHECKER}" "${FIX}/printer.sh" 2>&1)"; rc=$?
check "case2 print-only suite reported NOT falsifiable" 1 "${rc}"
printf '%s\n' "${out}" | grep -q 'NOT FALSIFIABLE' \
  && ok "case2 verdict line says NOT FALSIFIABLE" \
  || no "case2 verdict line missing 'NOT FALSIFIABLE'"

out="$(bash "${CHECKER}" "${FIX}/shape/scripts/tests/test-resume-lane-arg-shapes.sh" 2>&1)"; rc=$?
check "case3 resume-lane exact shape reported NOT falsifiable" 1 "${rc}"
printf '%s\n' "${out}" | grep -q 'NOT FALSIFIABLE' \
  && ok "case3 verdict line says NOT FALSIFIABLE" \
  || no "case3 verdict line missing 'NOT FALSIFIABLE'"

out="$(bash "${CHECKER}" "${FIX}/missing-dep.sh" 2>&1)"; rc=$?
check "case4 baseline-red suite reported could-not-determine" 2 "${rc}"
printf '%s\n' "${out}" | grep -q 'could_not_determine' \
  && ok "case4 verdict line says could_not_determine" \
  || no "case4 verdict line missing 'could_not_determine'"

# usage error paths
bash "${CHECKER}" >/dev/null 2>&1; check "usage with no args exits 3" 3 "$?"
bash "${CHECKER}" "${FIX}/does-not-exist.sh" >/dev/null 2>&1; check "missing suite file exits 3" 3 "$?"

# ── Review-run wiring, cases 5-7 (stub arms, synthetic repo) ────────────────
if [[ "${NESTED}" != "1" ]]; then
STUBS="$(fx)"; CLEANUP_PATHS+=("${STUBS}")
cat > "${STUBS}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${STUBS}/resolver.py"
cat > "${STUBS}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "${role}" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUBS}/architect.sh"
cat > "${STUBS}/codex.sh" <<'SH'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUBS}/codex.sh"
cat > "${STUBS}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${STUBS}/dispatch.sh"

# run_review <label> <repo-root> <diff-file> — runs the real engine over a
# synthetic repo; sets RR_RC and RR_GATE.
run_review() {
  local label="$1" root="$2" diff_file="$3"
  local handoff
  handoff="${root}/repo/docs/handoff/dispatch-SF1"
  mkdir -p "${handoff}" "${root}/repo/.claude/ref" "${root}/repo/plugins/leadv2/scripts/tests"
  RR_GATE="${handoff}/review-gate.md"
  LEADV2_GLM_POLICY_RESOLVER="${STUBS}/resolver.py" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${STUBS}/architect.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${STUBS}/codex.sh" \
  LEADV2_DISPATCH_BIN="${STUBS}/dispatch.sh" \
  LEADV2_REVIEW_FANOUT=1 \
    bash "${REVIEW_RUN}" --task SF1 --root "${root}/repo" --handoff "${handoff}" \
      --diff "${diff_file}" --author glm >"${root}/rr.out" 2>"${root}/rr.err"
  RR_RC=$?
}

# case 5: the lane's diff ships the lying printer suite (case-2 shape) as a
# new suite — the gate must refuse before any reviewer arm is spent.
R5="$(fx)"; CLEANUP_PATHS+=("${R5}")
mkdir -p "${R5}/repo/plugins/leadv2/scripts/tests"
cat > "${R5}/repo/plugins/leadv2/scripts/tests/test-vacuous-lane.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Running vacuous suite..."
echo "FAIL: This is a fake failure"
echo "PASS: But we always exit 0"
exit 0
EOF
cat > "${R5}/diff.patch" <<EOF
diff --git a/plugins/leadv2/scripts/tests/test-vacuous-lane.sh b/plugins/leadv2/scripts/tests/test-vacuous-lane.sh
new file mode 100755
--- /dev/null
+++ b/plugins/leadv2/scripts/tests/test-vacuous-lane.sh
@@ -0,0 +1 @@
+vacuous
EOF
run_review case5 "${R5}" "${R5}/diff.patch"
check "case5 review-run rc for not-falsifiable suite" 7 "${RR_RC}"
if [[ -f "${RR_GATE}" ]] && grep -q '^status: fail' "${RR_GATE}" && grep -q '^reason: suite_not_falsifiable' "${RR_GATE}"; then
  ok "case5 gate says status: fail / suite_not_falsifiable"
else
  no "case5 gate missing status: fail / suite_not_falsifiable (got: $(head -2 "${RR_GATE:-<absent>}" 2>/dev/null | tr '\n' ' '))"
fi
if grep -q 'cannot go red' "${RR_GATE:-/dev/null}" 2>/dev/null && grep -q 'is NOT an assertion' "${RR_GATE:-/dev/null}" 2>/dev/null; then
  ok "case5 refusal message tells the worker what is missing"
else
  no "case5 refusal message lacks worker-facing explanation"
fi

# case 6: the lane's diff ships the honest suite — verdict path unchanged
# (with stub arms returning PASS, the round must reach status: pass).
R6="$(fx)"; CLEANUP_PATHS+=("${R6}")
mkdir -p "${R6}/repo/plugins/leadv2/scripts/tests"
cp "${FIX}/honest.sh" "${R6}/repo/plugins/leadv2/scripts/tests/test-honest-lane.sh"
cat > "${R6}/diff.patch" <<EOF
diff --git a/plugins/leadv2/scripts/tests/test-honest-lane.sh b/plugins/leadv2/scripts/tests/test-honest-lane.sh
new file mode 100755
--- /dev/null
+++ b/plugins/leadv2/scripts/tests/test-honest-lane.sh
@@ -0,0 +1 @@
+honest
EOF
run_review case6 "${R6}" "${R6}/diff.patch"
if [[ "${RR_RC}" == "0" && -f "${RR_GATE}" ]] && grep -q '^status: pass' "${RR_GATE}"; then
  ok "case6 falsifiable suite reaches status: pass (rc=0), path unchanged"
else
  no "case6 expected rc=0 status: pass, got rc=${RR_RC} gate=$(head -2 "${RR_GATE:-<absent>}" 2>/dev/null | tr '\n' ' ')"
fi

# case 7: diff touches no suite at all — the gate must not fire.
R7="$(fx)"; CLEANUP_PATHS+=("${R7}")
mkdir -p "${R7}/repo"
cat > "${R7}/diff.patch" <<EOF
diff --git a/x b/x
--- a/x
+++ b/x
@@ -1 +1 @@
-hello
+goodbye
EOF
run_review case7 "${R7}" "${R7}/diff.patch"
if [[ "${RR_RC}" == "0" && -f "${RR_GATE}" ]] && grep -q '^status: pass' "${RR_GATE}"; then
  ok "case7 no-suite diff reaches status: pass (gate did not fire)"
else
  no "case7 expected rc=0 status: pass, got rc=${RR_RC} gate=$(head -2 "${RR_GATE:-<absent>}" 2>/dev/null | tr '\n' ' ')"
fi

fi

# ── Case 8: self-application — this suite must itself be falsifiable ───────
if [[ "${NESTED}" != "1" ]]; then
# LEADV2_SSF_SELF_GUARD cuts the recursion this case would otherwise create
# (checker -> this suite -> case 8 -> checker ...): exported here, inherited
# by every nested run, checked above. It is set by THIS suite only; the
# checker itself exports no probe marker a lying suite could key on.
export LEADV2_SSF_SELF_GUARD=1
: > "${GUARD_FILE}"
out="$(LEADV2_SUITE_FALSIFIABLE_TIMEOUT=180 bash "${CHECKER}" "${SCRIPT_DIR}/test-suite-falsifiable.sh" 2>&1)"; rc=$?
rm -f "${GUARD_FILE}"
check "case8 this suite is itself reported falsifiable" 0 "${rc}"

fi

# ── Case 9: default timeout (no env override) must be >=120s ───────────────
# PPC-G1: a fixed 60s default died to a real 71s suite under contention.
# Extract the literal default from the source (never invoke it live for 3+
# minutes in a test suite) and assert it carries real margin over the
# measured incident value.
_default_timeout="$(sed -n 's/.*LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-\([0-9][0-9]*\)}.*/\1/p' "${CHECKER}" | head -n1)"
if [[ -n "${_default_timeout}" ]] && [[ "${_default_timeout}" -ge 120 ]]; then
  ok "case9 default timeout is ${_default_timeout}s (>=120s, survives the 71s incident with margin)"
else
  no "case9 default timeout '${_default_timeout:-<none found>}' is not >=120s"
fi

# ── Case 10: a genuinely-hanging suite is still killed under a small
# override timeout — proves the watchdog is not toothless just because the
# default grew. Must NOT use the real (now 180s) default: this asserts the
# mechanism, not the constant.
cat > "${FIX}/hangs.sh" <<'EOF'
#!/usr/bin/env bash
sleep 30
exit 0
EOF
chmod +x "${FIX}/hangs.sh"
out="$(LEADV2_SUITE_FALSIFIABLE_TIMEOUT=2 bash "${CHECKER}" "${FIX}/hangs.sh" 2>&1)"; rc=$?
check "case10 genuinely-hanging suite is killed by the watchdog" 2 "${rc}"
printf '%s\n' "${out}" | grep -q 'timed out' \
  && ok "case10 verdict line says timed out" \
  || no "case10 verdict line missing 'timed out' (watchdog may be toothless)"

# ── Case 11: a suite that finishes with margin under the timeout still gets
# a real (non-timeout) verdict — proves the fix does not mask the "genuinely
# unrunnable" case by simply widening the window over everything.
cat > "${FIX}/finishes-with-margin.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 2
TMP="$(mktemp)"
echo "content" > "${TMP}"
if ! grep -q "content" "${TMP}"; then
  echo "FAIL: content mismatch"
  rm -f "${TMP}"
  exit 1
fi
rm -f "${TMP}"
echo "PASS"
exit 0
EOF
chmod +x "${FIX}/finishes-with-margin.sh"
out="$(LEADV2_SUITE_FALSIFIABLE_TIMEOUT=10 bash "${CHECKER}" "${FIX}/finishes-with-margin.sh" 2>&1)"; rc=$?
check "case11 suite finishing under timeout gets a real verdict (falsifiable)" 0 "${rc}"
printf '%s\n' "${out}" | grep -q 'timed out' \
  && no "case11 verdict wrongly reports timed out for a suite that finished" \
  || ok "case11 verdict line does not mention timed out"

# ── Summary ─────────────────────────────────────────────────────────────────
printf 'test-suite-falsifiable: %d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
exit 0
