#!/usr/bin/env bash
# test-mktemp-guard.sh — unit tests for plugins/leadv2/scripts/lib/mktemp-guard.sh
# (CI-SUITES-ARE-MACOS-ONLY-01).
#
# The incident: `mktemp -d -t <name>` (no XXX in the template) is a BSD-only
# form. GNU coreutils (the CI/Docker Linux hosts) reads `-t <name>` as a
# template that must contain XXX, refuses it, prints to stderr, and returns
# empty on stdout -- so `FIX="$(mktemp -d -t name)"` silently becomes
# `FIX=""` and every downstream path built from it resolves against the
# filesystem root (`/cache/...`, `/ledgers/...`, `/handoff/...`).
#
# Coverage:
#   R1: guard fires on bare `mktemp -t name` (no XXX)
#   R2: guard fires on `mktemp -d -t name` (the actual incident pattern --
#       this is the shape the pre-fix regex in mktemp-guard.sh missed)
#   R3: guard is silent on the portable form `mktemp -d "$TMPDIR/name.XXXXXX"`
#   R4: guard is silent on `mktemp -t name.XXXXXX.json` (XXX present in -t template)
#   R5: guard does not trip a caller's `set -e` on the clean (no-violation) path
#   R6: MUTATION CONTROL -- revert mktemp-guard.sh's detection regex to the
#       historic pre-fix pattern (bare `-t` only, never `-d -t`) and prove it
#       goes blind on the R2 fixture: baseline_rc=1 (real guard catches it),
#       mutated_rc=0 (reverted guard misses it). baseline_rc must differ from
#       mutated_rc, and the mutant creation itself is verified (not assumed)
#       before the comparison is trusted.
#   R7: guard fires on the bare suffixed template `mktemp /tmp/foo-XXXXXX.json`
#       (no -t; the X-run is not final in the word). Measured on macOS: BSD
#       returns that template LITERALLY, the name is fixed and shared, and the
#       second caller at that site gets rc=1 + an empty path. GNU substitutes,
#       so the defect is macOS-only, but the check fires everywhere because
#       lanes run on macOS. BSD does not substitute; GNU does.
#   R8: guard is silent on the portable bare form `mktemp /tmp/foo-XXXXXX`
#   R9: guard is silent on `mktemp -t sp.XXXXXX.json` for detection 2 as well
#       (detection 2 skips lines carrying -t, so R4's verdict is unchanged)
#   R10: MUTATION CONTROL for detection 2 -- revert _mkg_flag_word()'s
#       final-run test to the naive form and prove the R8 fixture goes red:
#       baseline_rc=0 (real guard silent on the portable form), mutated_rc=1
#       (mutant flags it). Mutant creation verified, not assumed (as R6).
#
# DECLARED MUTATION (R10, negative control, executed on every suite run):
#   inside _mkg_flag_word()'s body, replace
#       (( off + ${#m} == ${#w} )) || return 0
#   with the naive form
#       printf '%s' "$w" | grep -qE 'X{3,}[A-Za-z0-9._-]' && return 0
#   on a COPY of the guard. The naive regex matches the FOURTH X of a run
#   (X is in the class), so it flags every template, portable ones included
#   -- under it, case R8 goes red. A green run under that mutant is the
#   lying-green disease. The bare-form scan itself is ported from
#   persona-engine tests/unit/test-mktemp-suffixed-template.sh
#   (MKTEMP-SUFFIXED-TEMPLATE-RETURNS-A-LITERAL-PATH-01, green on main).
#
# run-all-triggers: mktemp-guard.sh
# Run: bash plugins/leadv2/scripts/tests/test-mktemp-guard.sh
# Exit 0 = all pass; non-zero = failures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${SCRIPTS_DIR}/lib/mktemp-guard.sh"

if [[ ! -f "$GUARD" ]]; then
  echo "Error: mktemp-guard.sh not found at $GUARD" >&2
  exit 1
fi

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-mktemp-guard.XXXXXX")" || {
  echo "Error: could not create sandbox dir" >&2
  exit 1
}
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ── bash -n on the guard itself ─────────────────────────────────────────────
if bash -n "$GUARD" 2>/dev/null; then
  pass "bash -n: mktemp-guard.sh"
else
  fail "bash -n: mktemp-guard.sh"
fi

# ── fixture writer ───────────────────────────────────────────────────────────
# Writes a standalone fixture script that sources $1 (a copy of the guard,
# real or mutated) and calls mktemp_guard, so BASH_SOURCE[1] inside the guard
# resolves to the fixture -- exactly how every real caller uses it.
write_fixture() {
  local path="$1" guard_path="$2" body="$3" trailer="${4:-}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'source %q\n' "$guard_path"
    printf 'mktemp_guard\n'
    printf '%s\n' "$body"
    [[ -n "$trailer" ]] && printf '%s\n' "$trailer"
  } > "$path"
  chmod +x "$path"
}

# Feed captured output directly to grep: with pipefail, echo | grep -q can
# report failure when grep matches early and echo receives SIGPIPE.

# ── R1: bare `mktemp -t name` (no XXX) must be caught ───────────────────────
FIX_BARE="$WORK/fix-bare.sh"
write_fixture "$FIX_BARE" "$GUARD" 'x="$(mktemp -t leadv2-ss-mini)"; echo "reached-end"'
out=$(bash "$FIX_BARE" 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "Error:.*without XXX" <<< "$out"; then
  pass "R1: guard fires on bare 'mktemp -t name'"
else
  fail "R1: guard fires on bare 'mktemp -t name' (rc=$rc, out='$out')"
fi

# ── R2: `mktemp -d -t name` (the actual incident pattern) must be caught ────
FIX_DT="$WORK/fix-dt.sh"
write_fixture "$FIX_DT" "$GUARD" 'x="$(mktemp -d -t leadv2-batch01)"; echo "reached-end"'
out=$(bash "$FIX_DT" 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "Error:.*without XXX" <<< "$out"; then
  pass "R2: guard fires on 'mktemp -d -t name' (incident pattern)"
else
  fail "R2: guard fires on 'mktemp -d -t name' (incident pattern) (rc=$rc, out='$out')"
fi

# ── R3: portable form is silent ─────────────────────────────────────────────
FIX_GOOD="$WORK/fix-good.sh"
write_fixture "$FIX_GOOD" "$GUARD" 'x="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-batch01.XXXXXX")"; echo "reached-end"; rm -rf "$x"'
out=$(bash "$FIX_GOOD" 2>&1); rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "reached-end" <<< "$out"; then
  pass "R3: guard is silent on the portable form"
else
  fail "R3: guard is silent on the portable form (rc=$rc, out='$out')"
fi

# ── R4: `-t` template that DOES contain XXX is silent ───────────────────────
FIX_TXXX="$WORK/fix-t-xxx.sh"
write_fixture "$FIX_TXXX" "$GUARD" 'x="$(mktemp -t sp.XXXXXX.json)"; echo "reached-end"; rm -f "$x"'
out=$(bash "$FIX_TXXX" 2>&1); rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "reached-end" <<< "$out"; then
  pass "R4: guard is silent on '-t name.XXXXXX.json'"
else
  fail "R4: guard is silent on '-t name.XXXXXX.json' (rc=$rc, out='$out')"
fi

# ── R5: guard must not trip a caller's `set -e` on the clean path ──────────
# This is the second historic bug: `line=$(pipeline)` outside an `if` trips
# `set -e` on the common no-violation case (grep finds nothing -> nonzero),
# killing the suite with zero output, before it ever gets to its own tests.
FIX_SETE="$WORK/fix-sete.sh"
# set -e must be BEFORE mktemp_guard is called, so write_fixture (which puts
# the caller body after the mktemp_guard call) can't express this ordering.
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -e\n'
  printf 'source %q\n' "$GUARD"
  printf 'mktemp_guard\n'
  printf 'x="$(mktemp -d "%s/leadv2-sete.XXXXXX")"\n' "${TMPDIR:-/tmp}"
  printf 'echo "reached-end"\n'
  printf 'rm -rf "$x"\n'
} > "$FIX_SETE"
chmod +x "$FIX_SETE"
out=$(bash "$FIX_SETE" 2>&1); rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "reached-end" <<< "$out"; then
  pass "R5: guard does not trip caller's 'set -e' on the clean path"
else
  fail "R5: guard does not trip caller's 'set -e' on the clean path (rc=$rc, out='$out')"
fi

# ── R6: MUTATION CONTROL ─────────────────────────────────────────────────────
# Revert the guard's detection regex to the historic pre-fix pattern that
# matched bare `mktemp -t` but never `mktemp -d -t` -- the exact blind spot
# that let the incident pattern ship. Applied INSIDE the function body via a
# literal (non-regex) string replace of the real fixed line, done in python3
# rather than sed -- the line itself is a regex full of metacharacters
# ([, ], (, ), $, \b), so using sed to pattern-match it would need its own
# fragile regex-of-a-regex. A python3 literal-string swap on the exact
# current line means a future edit to that line makes this control fail
# loud (control_not_applied) instead of silently no-op'ing.
MUTANT_GUARD="$WORK/mktemp-guard-mutant.sh"
_mutation_applied=1
python3 - "$GUARD" "$MUTANT_GUARD" <<'PYEOF' || _mutation_applied=0
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    content = f.read()
old = "    line=$(grep -E '\\bmktemp\\b([^#]*[[:space:]])?-t([[:space:]]|$)' \"$script\" | grep -vE '^[[:space:]]*#' | head -1 || true)\n"
new = "    line=$(grep -E '\\bmktemp\\b[[:space:]]+-t([[:space:]]|$)' \"$script\" | grep -vE '^[[:space:]]*#' | head -1 || true)\n"
if old not in content:
    sys.exit(1)
with open(dst, "w") as f:
    f.write(content.replace(old, new, 1))
PYEOF

if [[ "$_mutation_applied" -ne 1 ]] || [[ ! -s "$MUTANT_GUARD" ]] || diff -q "$GUARD" "$MUTANT_GUARD" >/dev/null 2>&1; then
  fail "R6 MUTATION CONTROL: control_not_applied -- literal anchor line not found, mutant is identical to the real guard"
else
  # baseline: the REAL (fixed) guard against the R2 incident-pattern fixture.
  fix_baseline="$WORK/fix-r6-baseline.sh"
  write_fixture "$fix_baseline" "$GUARD" 'x="$(mktemp -d -t leadv2-batch01)"; echo "reached-end"'
  bash "$fix_baseline" >/dev/null 2>&1
  baseline_rc=$?

  # mutated: the REVERTED (pre-fix) guard against the SAME fixture.
  fix_mutated="$WORK/fix-r6-mutated.sh"
  write_fixture "$fix_mutated" "$MUTANT_GUARD" 'x="$(mktemp -d -t leadv2-batch01)"; echo "reached-end"'
  bash "$fix_mutated" >/dev/null 2>&1
  mutated_rc=$?

  log "R6 MUTATION CONTROL: baseline_rc=${baseline_rc} mutated_rc=${mutated_rc}"
  if [[ "$baseline_rc" -eq 1 && "$mutated_rc" -eq 0 ]]; then
    pass "R6 MUTATION CONTROL: mutant (bare -t only regex) goes blind on 'mktemp -d -t' -- baseline_rc=1 mutated_rc=0, control proven red-capable"
  else
    fail "R6 MUTATION CONTROL: expected baseline_rc=1/mutated_rc=0, got baseline_rc=${baseline_rc}/mutated_rc=${mutated_rc} -- control did not diverge as expected"
  fi
fi

# ── R7: bare suffixed template (no -t) must be caught ───────────────────────
FIX_BARE_SUFFIX="$WORK/fix-bare-suffix.sh"
write_fixture "$FIX_BARE_SUFFIX" "$GUARD" '_a=$(mktemp /tmp/foo-XXXXXX.json); echo "reached-end"'
out=$(bash "$FIX_BARE_SUFFIX" 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "X-run is not final" <<< "$out"; then
  pass "R7: guard fires on bare 'mktemp /tmp/foo-XXXXXX.json' (X-run not final)"
else
  fail "R7: guard fires on bare 'mktemp /tmp/foo-XXXXXX.json' (X-run not final) (rc=$rc, out='$out')"
fi

# ── R8: portable bare form (X-run final) is silent ──────────────────────────
FIX_BARE_OK="$WORK/fix-bare-ok.sh"
write_fixture "$FIX_BARE_OK" "$GUARD" '_a=$(mktemp /tmp/foo-XXXXXX); echo "reached-end"; rm -f "$_a"'
out=$(bash "$FIX_BARE_OK" 2>&1); rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "reached-end" <<< "$out"; then
  pass "R8: guard is silent on the portable bare form 'mktemp /tmp/foo-XXXXXX'"
else
  fail "R8: guard is silent on the portable bare form 'mktemp /tmp/foo-XXXXXX' (rc=$rc, out='$out')"
fi

# ── R9: detection 2 must never see `-t` lines (R4's shape, unchanged) ───────
FIX_T_DISJOINT="$WORK/fix-t-disjoint.sh"
write_fixture "$FIX_T_DISJOINT" "$GUARD" '_a=$(mktemp -t sp.XXXXXX.json); echo "reached-end"; rm -f "$_a"'
out=$(bash "$FIX_T_DISJOINT" 2>&1); rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "reached-end" <<< "$out"; then
  pass "R9: detection 2 is silent on 'mktemp -t sp.XXXXXX.json' (R4 boundary)"
else
  fail "R9: detection 2 is silent on 'mktemp -t sp.XXXXXX.json' (R4 boundary) (rc=$rc, out='$out')"
fi

# ── R10: MUTATION CONTROL for detection 2 ───────────────────────────────────
# Revert _mkg_flag_word()'s final-run test to the naive form declared in the
# header: X{3,}[A-Za-z0-9._-] matches the FOURTH X of a run, so the mutant
# flags the portable form too. Applied INSIDE the function body via a
# literal (non-regex) python3 swap of the exact current line -- same
# control_not_applied contract as R6: a future edit to that line makes this
# control fail loud instead of silently no-op'ing.
MUTANT_GUARD2="$WORK/mktemp-guard-mutant2.sh"
_mutation2_applied=1
python3 - "$GUARD" "$MUTANT_GUARD2" <<'PYEOF' || _mutation2_applied=0
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    content = f.read()
old = "    (( off + ${#m} == ${#w} )) || return 0\n"
new = "    printf '%s' \"$w\" | grep -qE 'X{3,}[A-Za-z0-9._-]' && return 0\n"
if old not in content:
    sys.exit(1)
with open(dst, "w") as f:
    f.write(content.replace(old, new, 1))
PYEOF

if [[ "$_mutation2_applied" -ne 1 ]] || [[ ! -s "$MUTANT_GUARD2" ]] || diff -q "$GUARD" "$MUTANT_GUARD2" >/dev/null 2>&1; then
  fail "R10 MUTATION CONTROL: control_not_applied -- final-run-test anchor line not found in _mkg_flag_word(), mutant identical to the real guard"
else
  # baseline: the REAL guard stays silent on the R8 portable-form fixture.
  fix2_baseline="$WORK/fix-r10-baseline.sh"
  write_fixture "$fix2_baseline" "$GUARD" '_a=$(mktemp /tmp/foo-XXXXXX); echo "reached-end"; rm -f "$_a"'
  bash "$fix2_baseline" >/dev/null 2>&1
  baseline2_rc=$?

  # mutated: the NAIVE-form guard flags the SAME fixture (case R8 goes red).
  fix2_mutated="$WORK/fix-r10-mutated.sh"
  write_fixture "$fix2_mutated" "$MUTANT_GUARD2" '_a=$(mktemp /tmp/foo-XXXXXX); echo "reached-end"; rm -f "$_a"'
  bash "$fix2_mutated" >/dev/null 2>&1
  mutated2_rc=$?

  log "R10 MUTATION CONTROL: baseline_rc=${baseline2_rc} mutated_rc=${mutated2_rc}"
  if [[ "$baseline2_rc" -eq 0 && "$mutated2_rc" -eq 1 ]]; then
    pass "R10 MUTATION CONTROL: naive X{3,} mutant flags the portable form -- baseline_rc=0 mutated_rc=1, control proven red-capable"
  else
    fail "R10 MUTATION CONTROL: expected baseline_rc=0/mutated_rc=1, got baseline_rc=${baseline2_rc}/mutated_rc=${mutated2_rc} -- control did not diverge as expected"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
log "----"
log "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
