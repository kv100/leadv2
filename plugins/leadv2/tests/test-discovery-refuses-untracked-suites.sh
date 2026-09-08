#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-suite-discovery
# plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh — C5, GATE-DISCOVERS-246-UNTRACKED-SUITES-01
#
# A suite runs only if something tracked admits it. Measured 2026-09-09:
# .claude/scripts/tests in the main checkout holds 246 test-*.sh absent
# from git ls-files and zero trigger rows — --scope all executed all of
# them. The admission contract lives in
# plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh; tests/run-all.sh
# wires it in (B2 owns that file — the wiring patch is the lane's finding,
# and this suite applies that exact patch to a scratch COPY of the real
# run-all.sh, so the control proves the shipped pair: lib + wiring).
#
# Method (test-gate-reaches-a-verdict-inside-budget.sh's): a scratch git
# repo carries the REAL tests/run-all.sh (patched with the wiring lines) +
# planted suites. No real suite runs; every case is seconds-fast.
# Assertions are on VALUES (exit codes, [RUN]/[SELECT] rows, skip lines),
# never prose.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to marker lines INSIDE the lib's function
# bodies (never at top level). Both must turn THIS suite red:
#   M1 c5-mut-1 — gate disabled (untracked executes again):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
#       plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh \
#       's|1) return 1 ;;  # c5-mut-1: untracked -> refused|1) return 0 ;;|'
#     -> case 1 goes RED: the planted poison suite executes (marker file
#        present, run-all exits 1, [UNTRACKED-SKIP] lines gone).
#   M2 c5-mut-2 — refuse everything (the green-that-runs-nothing):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
#       plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh \
#       's|0) return 0 ;;  # c5-mut-2: tracked -> admitted|0) return 1 ;;|'
#     -> cases 2/3 go RED: zero [SELECT]/[RUN] rows for tracked suites and
#        the tracked trigger rows vanish — a green that ran nothing is the
#        failure this control exists to catch.
#
# Portable: bash 3.2, scratch fixtures only. Run from anywhere:
#   bash plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh
set -uo pipefail
export LEADV2_TEST_CONTEXT="${LEADV2_TEST_CONTEXT:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUN_ALL="${LEADV2_TEST_RUN_ALL:-$ROOT/tests/run-all.sh}"
LIB="${LEADV2_TEST_DISCOVERY_LIB:-$ROOT/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh}"
[[ -f "$RUN_ALL" ]] || { echo "FAIL: run-all not found at $RUN_ALL" >&2; exit 1; }
[[ -f "$LIB" ]] || { echo "FAIL: discovery lib not found at $LIB" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

if bash -n "$LIB"; then pass "bash -n clean (lib)"; else fail "bash -n lib"; fi
if bash -n "$RUN_ALL"; then pass "bash -n clean (tests/run-all.sh)"; else fail "bash -n tests/run-all.sh"; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/c5-discovery.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
SCRATCH="$TMP/repo"
mkdir -p "$SCRATCH/tests" "$SCRATCH/plugins/leadv2/tests" "$SCRATCH/.claude/scripts/tests"
git init -q "$SCRATCH" 2>/dev/null
git -C "$SCRATCH" config user.email t@t.invalid
git -C "$SCRATCH" config user.name t

# Tracked, admitted suites (two roots): pass instantly, self-register rows.
printf '%s\n' '#!/usr/bin/env bash' '# run-all-triggers: alpha-stem' 'echo alpha-ok' 'exit 0' \
  > "$SCRATCH/tests/test-alpha-tracked.sh"
printf '%s\n' '#!/usr/bin/env bash' '# run-all-triggers: beta-stem' 'echo beta-ok' 'exit 0' \
  > "$SCRATCH/plugins/leadv2/tests/test-beta-tracked.sh"
# Untracked poison: executes -> touches the marker AND fails the sweep.
printf '%s\n' '#!/usr/bin/env bash' "touch '$TMP/poison.marker'" 'exit 1' \
  > "$SCRATCH/.claude/scripts/tests/test-poison-untracked.sh"
# Untracked with a trigger header: must NOT inject a trigger row.
printf '%s\n' '#!/usr/bin/env bash' '# run-all-triggers: ghost-stem' 'exit 0' \
  > "$SCRATCH/.claude/scripts/tests/test-ghost-untracked.sh"

git -C "$SCRATCH" add tests/test-alpha-tracked.sh plugins/leadv2/tests/test-beta-tracked.sh
git -C "$SCRATCH" commit -q -m "fixture: tracked suites only" || { echo "FAIL: fixture commit" >&2; exit 1; }

# The real run-all, carrying the exact wiring patch the lead applies
# (C5 finding; B2 owns tests/run-all.sh). Python asserts each anchor
# occurs exactly once before replacing — drift in run-all reddens HERE,
# loudly, instead of testing a stale carrier.
cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"
if ! python3 - "$SCRATCH/tests/run-all.sh" "$LIB" <<'PY'
import sys
path, lib = sys.argv[1], sys.argv[2]
s = open(path).read()
scan_old = '    done < <(find "${_dir}" -maxdepth 1 -type f -name \'test-*.sh\' 2>/dev/null | sort)'
scan_new = '    done < <(bash "%s" --root "${ROOT}" --dir "${_dir}" --skip-report=count)' % lib
all_old = ('    find "${ROOT}/plugins/leadv2/scripts/tests" "${ROOT}/.claude/scripts/tests" '
           '"${ROOT}/plugins/leadv2/tests" "${ROOT}/tests" \\\n'
           '      -maxdepth 1 -type f -name \'test-*.sh\' 2>/dev/null | sort')
all_new = '    bash "%s" --root "${ROOT}"' % lib
for name, old, new in (("scan-anchor", scan_old, scan_new), ("scope-all-anchor", all_old, all_new)):
    n = s.count(old)
    if n != 1:
        print("FAIL: wiring anchor %s found %d times (expected 1) — tests/run-all.sh drifted; re-pin the patch" % (name, n))
        sys.exit(1)
    s = s.replace(old, new)
open(path, "w").write(s)
PY
then
  echo "FAIL: wiring patch did not apply to the run-all copy" >&2
  exit 1
fi
pass "wiring patch applied (both anchors, exactly once)"

# Invoke the fixture run-all the way the product gates see it: clean env
# (env -i) so the `pwd` in run-all's HERE resolution answers physically —
# the root_escape guard compares that against git's physical toplevel, and
# on macOS /var/folders vs /private/var/folders FATALs any scratch run
# invoked from a dirty environment (the same wall
# test-gate-reaches-a-verdict-inside-budget.sh solves with env -i). Case
# vars ride as positional VAR=VAL words — prefix assignments on a function
# call never reach the callee (B2's comment, measured).
scratch_run_all() { # <outfile> <errfile> [VAR=VAL...] -- [run-all args...]
  local _out="$1" _err="$2"; shift 2
  local -a _env=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do _env+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  ( cd "$SCRATCH" && exec env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
      ${_env[@]+"${_env[@]}"} bash tests/run-all.sh "$@" ) >"$_out" 2>"$_err"
}
# bash-guard: allow

# ── case 1: the symptom — --scope all must NOT execute untracked suites ───
# and must say so by name, counted. (M1 c5-mut-1 reddens this case.)
out="$TMP/all.out"; err="$TMP/all.err"
scratch_run_all "$out" "$err" -- --scope all
rc=$?
[[ $rc -eq 0 ]] && pass "case1 rc=0 (tracked pass, untracked refused)" \
  || fail "case1 rc=$rc (expected 0)"
[[ ! -f "$TMP/poison.marker" ]] && pass "case1 poison suite NOT executed (marker absent)" \
  || fail "case1 poison marker EXISTS — untracked suite executed"
runs="$(grep -c '^\[RUN\]' "$out" || true)"
[[ "$runs" -eq 2 ]] && pass "case1 ran exactly the 2 tracked suites" \
  || fail "case1 [RUN] rows = ${runs} (expected 2)"
grep -q '^\[RUN\] .*tests/test-alpha-tracked.sh$' "$out" && pass "case1 alpha ran" || fail "case1 alpha missing from [RUN]"
grep -q '^\[RUN\] .*plugins/leadv2/tests/test-beta-tracked.sh$' "$out" && pass "case1 beta ran" || fail "case1 beta missing from [RUN]"
grep -q 'test-poison-untracked' "$out" && fail "case1 poison in [RUN] stdout" || pass "case1 poison absent from stdout"
grep -qF 'suite-discovery: [UNTRACKED-SKIP] .claude/scripts/tests/test-poison-untracked.sh' "$err" \
  && pass "case1 poison named in [UNTRACKED-SKIP]" || fail "case1 poison not named by name"
grep -qF 'suite-discovery: [UNTRACKED-SKIP] .claude/scripts/tests/test-ghost-untracked.sh' "$err" \
  && pass "case1 ghost named in [UNTRACKED-SKIP]" || fail "case1 ghost not named by name"
grep -qF '2 suite file(s) refused' "$err" && pass "case1 skip count reported (2)" || fail "case1 skip count missing"

# ── case 2: the trigger map — tracked rows survive, untracked rows don't ──
# (M2 c5-mut-2 reddens this case: tracked rows vanish.)
out="$TMP/map.out"; err="$TMP/map.err"
scratch_run_all "$out" "$err" LEADV2_RUN_ALL_LIST_TRIGGERS=1 --
rc=$?
[[ $rc -eq 0 ]] && pass "case2 LIST_TRIGGERS rc=0" || fail "case2 rc=$rc"
grep -qF 'alpha-stem:tests/test-alpha-tracked.sh' "$out" && pass "case2 tracked alpha row present" \
  || fail "case2 alpha trigger row lost — tracked suite deselected"
grep -qF 'beta-stem:plugins/leadv2/tests/test-beta-tracked.sh' "$out" && pass "case2 tracked beta row present" \
  || fail "case2 beta trigger row lost — tracked suite deselected"
grep -q 'ghost-stem' "$out" && fail "case2 untracked ghost row injected into the map" \
  || pass "case2 ghost row refused"
grep -qF '2 suite file(s) refused' "$err" && pass "case2 scan-side refusal counted (count mode)" \
  || fail "case2 scan-side count line missing"
grep -q 'test-poison-untracked' "$err" && fail "case2 count mode leaked per-name lines" \
  || pass "case2 count mode proportional (no name spam)"

# ── case 3: the guard — a green that ran nothing is a failure ──────────────
# (M2 c5-mut-2 reddens this case: zero selects.)
out="$TMP/sel.out"; err="$TMP/sel.err"
scratch_run_all "$out" "$err" LEADV2_RUN_ALL_SELECT_ONLY=1 -- --scope all
sel="$(grep -c '^\[SELECT\]' "$out" || true)"
[[ "$sel" -eq 2 ]] && pass "case3 selected exactly the 2 tracked suites" \
  || fail "case3 [SELECT] rows = ${sel} (expected 2 — green-on-nothing guard)"
grep -q 'test-alpha-tracked' "$out" && grep -q 'test-beta-tracked' "$out" \
  && pass "case3 both tracked suites selected" || fail "case3 a tracked suite not selected"

# ── case 4: the lib's own contract, invoked directly ───────────────────────
lout="$(bash "$LIB" --root "$SCRATCH" 2>"$TMP/lib.err")"; rc=$?
[[ $rc -eq 0 ]] && pass "case4 lib rc=0 on a git root" || fail "case4 lib rc=$rc"
ln="$(printf '%s\n' "$lout" | grep -c 'test-.*tracked\.sh' || true)"
[[ "$ln" -eq 2 ]] && pass "case4 lib lists exactly the 2 tracked suites" \
  || fail "case4 lib admitted ${ln} (expected 2)"
grep -qF 'test-poison-untracked.sh' "$TMP/lib.err" && pass "case4 names mode names the refused" \
  || fail "case4 names mode silent"
bash "$LIB" --root "$SCRATCH" --skip-report=count >"$TMP/libc.out" 2>"$TMP/libc.err"; rc=$?
[[ $rc -eq 0 ]] && pass "case4 count-mode rc=0" || fail "case4 count-mode rc=$rc"
grep -q 'test-poison-untracked' "$TMP/libc.err" && fail "case4 count mode leaked names" \
  || pass "case4 count mode summary-only"
bash "$LIB" >"$TMP/u1.out" 2>"$TMP/u1.err"; [[ $? -eq 2 ]] && pass "case4 no --root refused (rc 2)" || fail "case4 missing root not refused"
bash "$LIB" --root "$SCRATCH" --skip-report=bogus >/dev/null 2>&1; [[ $? -eq 2 ]] && pass "case4 bad --skip-report refused (rc 2)" || fail "case4 bogus mode accepted"
bash "$LIB" --root "$TMP" >/dev/null 2>"$TMP/u3.err"; [[ $? -eq 2 ]] && grep -q 'not_a_git_work_tree' "$TMP/u3.err" \
  && pass "case4 non-git root refused by name (rc 2)" || fail "case4 non-git root not named-refused"

printf 'c5-discovery: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
# bash-guard: allow
