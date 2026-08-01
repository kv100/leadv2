#!/usr/bin/env bash
# tests/test-red-first-gate.sh — RED-FIRST-GATE-01 DoD test for leadv2-red-first-gate.sh.
#
# Exercises every classification branch against real disposable git fixtures
# (never the real leadv2 tree): RED_PROVEN, NOT_RED (blocking), DIFF_BROKEN
# (blocking), regression_only exemption, and the rc=2 setup/isolation-failure
# path. This file is itself new — pre-fix (before leadv2-red-first-gate.sh
# exists) every assertion that shells out to it fails with "No such file or
# directory"; that IS this file's own red-first proof.
#
# Run: bash scripts/tests/test-red-first-gate.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${SCRIPT_DIR}/leadv2-red-first-gate.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${GATE}" 2>/dev/null; then pass "bash -n leadv2-red-first-gate.sh"; else fail "bash -n leadv2-red-first-gate.sh"; fi

mk_fixture_repo() { # -> prints repo path
  local repo; repo="$(lv2_mktemp_dir rfg-fixture)/repo"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q && git config user.email t@t.com && git config user.name t )
  lv2_assert_scratch_repo "$repo"
  printf '%s' "$repo"
}

# leadv2-helpers.sh unconditionally sets LEADV2_HANDOFF_DIR="$LEADV2_PROJECT_ROOT/docs/handoff"
# at source time, BEFORE _lv2_load_paths' "caller override wins" logic runs — so
# pre-exporting LEADV2_HANDOFF_DIR directly is silently clobbered. The established
# pattern in this codebase (test-lane-liveness-authoritative.sh) is to instead
# point LEADV2_PROJECT_ROOT at a scratch directory, so the handoff dir naturally
# resolves under it, fully isolated from any real repo's docs/handoff.
run_probe() { # <repo> <task_id> -> sets GATE_RC, GATE_REPORT
  local repo="$1" task_id="$2"
  GATE_FAKE_ROOT="$(lv2_mktemp_dir rfg-fakeroot)"
  LEADV2_PROJECT_ROOT="${GATE_FAKE_ROOT}" bash "${GATE}" probe --task-id "${task_id}" --repo "${repo}" --base HEAD \
    > "${GATE_FAKE_ROOT}/stdout.log" 2> "${GATE_FAKE_ROOT}/stderr.log"
  GATE_RC=$?
  GATE_REPORT="${GATE_FAKE_ROOT}/docs/handoff/${task_id}/red-first-report.json"
}

# ── Fixture A: RED_PROVEN — a real fix, pre-fix assertion genuinely fails ──
A="$(mk_fixture_repo)"
printf 'add() { echo $(( $1 + $2 )); }\n' > "${A}/lib.sh"
mkdir -p "${A}/tests"
cat > "${A}/tests/test-lib.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$D/lib.sh"
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "$(add 2 3)" "5" "add returns 6"
EOF
chmod +x "${A}/tests/test-lib.sh"
( cd "$A" && git add -A && git commit -qm base )
# The "diff": lib.sh's behaviour changes AND the test file's own assertion
# changes to match (5 -> 6) — both must move together for the test file to
# appear in the diff at all (corpus selection is "test files the diff touches").
printf 'add() { echo $(( $1 + $2 + 1 )); }\n' > "${A}/lib.sh"
cat > "${A}/tests/test-lib.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$D/lib.sh"
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "$(add 2 3)" "6" "add returns 6"
EOF
run_probe "$A" "rfg-a"
if [[ "$GATE_RC" == "0" ]]; then pass "fixture A (genuine fix): probe exits 0"; else fail "fixture A: expected rc=0, got ${GATE_RC}"; fi
if [[ -f "$GATE_REPORT" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['totals']['red_proven']==1 and d['totals']['not_red']==0 else 1)" "$GATE_REPORT"; then
  pass "fixture A: report shows red_proven=1 not_red=0"
else
  fail "fixture A: report totals wrong"
fi

# ── Fixture B: NOT_RED — a tautological assertion, green before AND after ──
B="$(mk_fixture_repo)"
printf 'noop() { :; }\n' > "${B}/lib.sh"
mkdir -p "${B}/tests"
cat > "${B}/tests/test-taut.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "1" "1" "tautology always true"
EOF
chmod +x "${B}/tests/test-taut.sh"
( cd "$B" && git add -A && git commit -qm base )
printf '# unrelated comment change\n' >> "${B}/lib.sh"
# Test file itself must genuinely change (else it never enters the diff/corpus
# at all) — add a second, equally tautological check alongside the first.
cat > "${B}/tests/test-taut.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "1" "1" "tautology always true"
check "2" "2" "tautology always true again"
EOF
run_probe "$B" "rfg-b"
if [[ "$GATE_RC" == "1" ]]; then pass "fixture B (tautology): probe exits 1 (BLOCK)"; else fail "fixture B: expected rc=1, got ${GATE_RC}"; fi
if [[ -f "$GATE_REPORT" ]] && python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if any(b['verdict']=='NOT_RED' for b in d['blocking_labels']) else 1)" "$GATE_REPORT"; then
  pass "fixture B: blocking_labels names the NOT_RED assertion"
else
  fail "fixture B: NOT_RED label not named"
fi

# ── Fixture C: DIFF_BROKEN — an assertion that fails post-fix ──
C="$(mk_fixture_repo)"
printf 'sub() { echo $(( $1 - $2 )); }\n' > "${C}/lib.sh"
mkdir -p "${C}/tests"
cat > "${C}/tests/test-sub.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$D/lib.sh"
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "$(sub 5 2)" "3" "sub 5 2 is 3"
EOF
chmod +x "${C}/tests/test-sub.sh"
( cd "$C" && git add -A && git commit -qm base )
printf 'sub() { echo BROKEN; }\n' > "${C}/lib.sh"
# Test file itself must also change (else it never enters the diff/corpus) —
# add a second assertion alongside the one the broken lib.sh will fail.
cat > "${C}/tests/test-sub.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$D/lib.sh"
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
check "$(sub 5 2)" "3" "sub 5 2 is 3"
check "$(sub 9 4)" "5" "sub 9 4 is 5"
EOF
run_probe "$C" "rfg-c"
if [[ "$GATE_RC" == "1" ]]; then pass "fixture C (broken diff): probe exits 1 (BLOCK)"; else fail "fixture C: expected rc=1, got ${GATE_RC}"; fi
if [[ -f "$GATE_REPORT" ]] && python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if any(b['verdict']=='DIFF_BROKEN' for b in d['blocking_labels']) else 1)" "$GATE_REPORT"; then
  pass "fixture C: blocking_labels names the DIFF_BROKEN assertion"
else
  fail "fixture C: DIFF_BROKEN label not named"
fi

# ── Fixture D: declared regression-only exemption is non-blocking ──
D_REPO="$(mk_fixture_repo)"
printf 'noop() { :; }\n' > "${D_REPO}/lib.sh"
mkdir -p "${D_REPO}/tests"
( cd "$D_REPO" && git add -A && git commit -qm base )
cat > "${D_REPO}/tests/test-exempt.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$D/lib.sh"
check() { [[ "$1" == "$2" ]] && printf '[TEST] PASS: %s\n' "$3" || printf '[TEST] FAIL: %s\n' "$3"; }
# red-first: regression-only — pure guard, behaviour intentionally unchanged
check "$(noop; echo ok)" "ok" "noop still returns ok"
EOF
chmod +x "${D_REPO}/tests/test-exempt.sh"
run_probe "$D_REPO" "rfg-d"
if [[ "$GATE_RC" == "0" ]]; then pass "fixture D (declared exemption): probe exits 0"; else fail "fixture D: expected rc=0, got ${GATE_RC}"; fi
if [[ -f "$GATE_REPORT" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['totals']['regression_only']==1 else 1)" "$GATE_REPORT"; then
  pass "fixture D: report counts the exemption in regression_only, not not_red"
else
  fail "fixture D: regression_only count wrong"
fi

# ── Fixture E: setup/isolation failure -> rc=2, nothing classified ──
run_probe "/tmp/leadv2-red-first-does-not-exist-$$" "rfg-e"
if [[ "$GATE_RC" == "2" ]]; then pass "fixture E (missing repo): probe exits 2"; else fail "fixture E: expected rc=2, got ${GATE_RC}"; fi
if [[ ! -f "$GATE_REPORT" ]]; then pass "fixture E: no report.json written on setup failure"; else fail "fixture E: report.json should not exist"; fi

# ── report subcommand round-trips fixture A's result ──
RT_ROOT="$(lv2_mktemp_dir rfg-fakeroot)"
LEADV2_PROJECT_ROOT="${RT_ROOT}" bash "${GATE}" probe --task-id rfg-report-rt --repo "$A" --base HEAD >/dev/null 2>&1
report_out="$(LEADV2_PROJECT_ROOT="${RT_ROOT}" bash "${GATE}" report --task-id rfg-report-rt)"
if grep -q 'verdict=' <<<"$report_out"; then pass "report subcommand prints a verdict line"; else fail "report subcommand missing verdict line"; fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
