#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-suite-discovery
# plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh — C5b, GATE-DISCOVERS-246-UNTRACKED-SUITES-01
#
# A suite runs only if something tracked admits it. Measured 2026-09-09:
# .claude/scripts/tests in the main checkout holds 246 test-*.sh absent
# from git ls-files and zero trigger rows — --scope all executed all of
# them. The admission contract lives in
# plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh. The live
# tests/run-all.sh routes BOTH discovery vectors through that lib: header
# registration (count-only signal) and --scope all execution (named refusals
# plus count). This suite proves the shipped pair, rather than asserting that
# the superseded proposal patch can still apply.
#
# Method (test-gate-reaches-a-verdict-inside-budget.sh's): a scratch git
# repo carries the REAL tests/run-all.sh and admission library + planted
# suites. No real suite runs; every case is seconds-fast.
# Assertions are on VALUES (exit codes, [RUN]/[SELECT] rows, skip lines),
# never prose.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh only inside function bodies (never at top
# level). Both must turn THIS suite red:
#   M1 c5b-mut-raw-find — restore the pre-wiring raw find in run-all's
#   --scope all branch (untracked executes again):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
#       tests/run-all.sh \
#       's|if ! bash "${ROOT}/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh" --root "${ROOT}" > "${_c5_list}"; then|if ! find "${ROOT}/plugins/leadv2/scripts/tests" "${ROOT}/.claude/scripts/tests" "${ROOT}/plugins/leadv2/tests" "${ROOT}/tests" -maxdepth 1 -type f -name '\''test-*.sh'\'' 2>/dev/null | sort > "${_c5_list}"; then|'
#     -> case 1 goes RED: the planted poison suite executes (marker file
#        present, run-all exits 1, [UNTRACKED-SKIP] lines gone).
#   M2 c5b-mut-admit-all — make the admission predicate unconditionally true:
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
#       plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh \
#       's|git -C "${_root}" ls-files --error-unmatch -- "${_rel}" >/dev/null 2>&1|return 0 # c5b-mut-admit-all: predicate always true|'
#     -> case 1 goes RED: refused count is zero and the poison suite runs.
#        A green which merely says nothing was refused is indistinguishable
#        from the original bug, so this suite requires both refusal signal
#        and non-execution.
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
mkdir -p "$SCRATCH/tests" "$SCRATCH/plugins/leadv2/scripts/tests" \
  "$SCRATCH/plugins/leadv2/tests" "$SCRATCH/.claude/scripts/tests"
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

cp "$RUN_ALL" "$SCRATCH/tests/run-all.sh"
mkdir -p "$SCRATCH/plugins/leadv2/scripts/lib"
cp "$LIB" "$SCRATCH/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh"

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

# Assert the live carrier calls the admission library at each required site.
# This runs after the executable symptom proof above so the raw-find mutation
# first demonstrates the restored failure, not merely a missing source token.
scan_wiring='bash "${ROOT}/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh" --root "${ROOT}" --dir "${_dir}" --skip-report=count'
scope_wiring='bash "${ROOT}/plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh" --root "${ROOT}" > "${_c5_list}"'
scan_n="$(grep -Fc "$scan_wiring" "$RUN_ALL" || true)"
scope_n="$(grep -Fc "$scope_wiring" "$RUN_ALL" || true)"
[[ "$scan_n" -eq 1 ]] && pass "live run-all scan routes through admission lib once" \
  || fail "live run-all scan wiring rows=${scan_n} (expected 1)"
[[ "$scope_n" -eq 1 ]] && pass "live run-all --scope all routes through admission lib once" \
  || fail "live run-all scope-all wiring rows=${scope_n} (expected 1)"

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
