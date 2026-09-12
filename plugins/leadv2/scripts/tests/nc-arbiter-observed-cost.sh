#!/usr/bin/env bash
# Negative controls for ARBITER-LEARNS-WHAT-WORK-COSTS-01 — the observed-cost
# multiplier in lib/leadv2-route-arbiter.sh.
# run-all-triggers: leadv2-route-arbiter
#
# Two mutations, both ANCHORED (make_mutant asserts the exact source string
# appears exactly once before replacing — an unanchored replace that matches
# nothing is a silent no-op, and two controls in this repo rotted exactly
# that way in one week):
#   (a) prices-but-never-applies: the multiplier is called (so the
#       cost_actuals= token still renders) but raised to the 0th power — the
#       matrix price decides alone, exactly the pre-fix disease the founder
#       named. THE acceptance case (2) of test-arbiter-uses-observed-cost.sh
#       must go RED: the arm must NOT move to glm under burn history.
#   (b) min_rows bypass: `len(_rows)<OBS_MIN_ROWS` guard dropped, so TWO rows
#       re-price an arm. Case (5) must go RED: thin history must not move the
#       arm (a lucky pair of rows is no basis — the same rule the forecast's
#       FORECAST_MIN_ROWS sets).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/../lib/leadv2-route-arbiter.sh"
TEST="${HERE}/test-arbiter-uses-observed-cost.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-nc-arbiter-observed-cost.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

make_mutant() { # <needle> <replacement> <out>
  local needle="$1" replacement="$2" out="$3"
  python3 - "$SRC" "$needle" "$replacement" "$out" <<'PY'
import pathlib, sys
src, needle, replacement, out = map(pathlib.Path, (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]))
text = src.read_text()
if text.count(str(needle)) != 1:
    raise SystemExit('NC-SETUP-FAIL: mutation pattern missing or ambiguous (count=%d): %s' % (text.count(str(needle)), needle))
pathlib.Path(out).write_text(text.replace(str(needle), str(replacement), 1))
PY
}

# (a) Must APPLY the observed price, not only print it.
mut_a="$TMP/prices-never-applies.sh"
make_mutant '_base*=_observed_rounds(c)' '_base*=(_observed_rounds(c)**0)  # NC-MUTATION-PRICES-BUT-NEVER-APPLIES' "$mut_a"
set +e
LEADV2_TEST_ARBITER_BIN="$mut_a" bash "$TEST" >"$TMP/a.out" 2>&1
rc_a=$?
set -e
if [[ $rc_a -eq 0 ]]; then
  echo 'NC-FAIL: case suite stayed green with the observed price raised to the 0th power' >&2
  grep -E '^(FAIL|SUMMARY)' "$TMP/a.out" >&2 || true
  exit 1
fi
grep -q 'FAIL: (2)' "$TMP/a.out" || { echo 'NC-FAIL: mutation (a) reddened the wrong case' >&2; grep -E '^(FAIL|SUMMARY)' "$TMP/a.out" >&2; exit 1; }
echo 'NC-PASS: (a) prices-but-never-applies -> acceptance case (2) red: arm no longer moves under burn history'

# (b) Must require OBS_MIN_ROWS rows before re-pricing an arm.
mut_b="$TMP/min-rows-bypass.sh"
make_mutant 'if not _rows or len(_rows)<OBS_MIN_ROWS: return 1.0' 'if not _rows: return 1.0  # NC-MUTATION-MIN-ROWS-BYPASS' "$mut_b"
set +e
LEADV2_TEST_ARBITER_BIN="$mut_b" bash "$TEST" >"$TMP/b.out" 2>&1
rc_b=$?
set -e
if [[ $rc_b -eq 0 ]]; then
  echo 'NC-FAIL: case suite stayed green with the min_rows guard dropped' >&2
  grep -E '^(FAIL|SUMMARY)' "$TMP/b.out" >&2 || true
  exit 1
fi
grep -q 'FAIL: (5)' "$TMP/b.out" || { echo 'NC-FAIL: mutation (b) reddened the wrong case' >&2; grep -E '^(FAIL|SUMMARY)' "$TMP/b.out" >&2; exit 1; }
echo 'NC-PASS: (b) min_rows bypass -> case (5) red: two rows re-priced an arm'
