#!/usr/bin/env bash
# test-guard-census.sh — GUARDS-MUST-PROVE-THEY-FIRE-01
#
# Locks the guard census against fixture guards + a fixture hooks.json —
# NEVER the real ~/.claude, NEVER the real hook tree, NEVER the real journals.
#
# Named mutation this suite must kill (Rules: "Removing the fixture-proof
# step must turn case 5 red"): in leadv2-guard-census.sh, deleting the
# fixture-run loop (`for f in "$FIXTURES_DIR"/*.fixture.sh; do ... done`)
# silences the only observer that notices a guard stopped being able to fire —
# case 5 (fixture no longer fires the guard ⇒ REGRESSION + non-zero exit)
# then sees rc=0 and no REGRESSION line, and this suite goes red.
#
# Bash 3.2 only; every ${arr[@]} guarded under set -u.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXROOT="$SCRIPT_DIR/fixtures/guards"
CENSUS="$SCRIPT_DIR/../leadv2-guard-census.sh"
GV_LIB="$SCRIPT_DIR/../../hooks/lib/leadv2-guard-verdict.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() { # $1 what  $2 actual  $3 want
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
assert_contains() { # $1 what  $2 haystack  $3 needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in: $2)" ;; esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-census.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

JDIR="$TMP/journal"; mkdir -p "$JDIR"
SBX="$TMP/sandbox";  mkdir -p "$SBX"

# Preseed the LIVE-side fixture journal (this is a temp fixture journal, never
# a real one): fx-nofix has executed before (case 4a: ran-never-fired).
printf '2026-09-01T00:00:00Z\tfx-nofix.sh\tStop\tran\t-\n' > "$JDIR/journal.tsv"

# Snapshot what the census must never mutate (case 8).
snap_hook="$(mktemp "$TMP/snapXXXX")"; snap_journal="$(mktemp "$TMP/snapXXXX")"
tar -cf "$snap_hook" -C "$FIXROOT" hook-dir hooks.json fixtures
cp "$JDIR/journal.tsv" "$snap_journal"

run_census_tsv() { # $1 hook-dir  $2 journal-dir  $3 sandbox-dir
  bash "$CENSUS" \
    --hooks-json "$FIXROOT/hooks.json" \
    --hook-dir "$1" \
    --journal-dir "$2" \
    --fixtures-dir "$FIXROOT/fixtures" \
    --gv-lib "$GV_LIB" \
    --sandbox-dir "$3" \
    --timeout 3 \
    --format tsv 2> "$TMP/stderr.txt"
}

TSV="$(run_census_tsv "$FIXROOT/hook-dir" "$JDIR" "$SBX")"
RC=$?

row_of() { printf '%s\n' "$TSV" | awk -F'\t' -v g="$1" '$2==g'; }
state_of() { row_of "$1" | cut -f4; }
fixcol_of() { row_of "$1" | cut -f7; }

# ── case 0: census itself is green on a healthy fixture tree ────────────────
assert_eq "census exit 0 on healthy fixtures" "$RC" "0"

# ── case 1: wired + firing ⇒ blocking, fixture-proven ───────────────────────
assert_eq "case1 fx-always-block state" "$(state_of fx-always-block.sh)" "blocking"
assert_eq "case1 fx-always-block fixture" "$(fixcol_of fx-always-block.sh)" "yes"
case "$(state_of fx-always-block.sh)" in
  blocking) pass "case1 guard counted blocking" ;;
  *) fail "case1 guard not blocking" ;;
esac

# ── case 2: wired, flag off by default ⇒ disabled, never blocking ───────────
assert_eq "case2 fx-disabled state" "$(state_of fx-disabled.sh)" "disabled"
case "$(state_of fx-disabled.sh)" in
  blocking) fail "case2 disabled guard misreported blocking" ;;
  *) pass "case2 disabled guard never reported blocking" ;;
esac

# ── case 3: journals but never blocks ⇒ fires-log-only (promise-guard shape) ─
assert_eq "case3 fx-logonly state" "$(state_of fx-logonly.sh)" "fires-log-only"

# ── case 4: never-ran distinct from ran-never-fired ──────────────────────────
assert_eq "case4a wired+journal-ran ⇒ ran-never-fired" "$(state_of fx-nofix.sh)" "ran-never-fired"
assert_eq "case4b wired+no evidence ⇒ never-ran" "$(state_of fx-quiet.sh)" "never-ran"

# ── case 5: fixture no longer makes the guard fire ⇒ REGRESSION, rc != 0 ────
MUT="$TMP/hook-mutated"; cp -R "$FIXROOT/hook-dir" "$MUT"
# The mutation: kill fx-always-block's block emission (no decision JSON, no
# exit 2) — its fixture then observes nap where block was expected.
sed '/"decision":"block"/d' "$MUT/fx-always-block.sh" > "$TMP/mut.tmp" \
  && mv "$TMP/mut.tmp" "$MUT/fx-always-block.sh"
chmod +x "$MUT/fx-always-block.sh"
MUT_OUT="$(run_census_tsv "$MUT" "$JDIR" "$TMP/sbx-mut")"
MUT_RC=$?
[ "$MUT_RC" -ne 0 ] && pass "case5 census exits non-zero on regression" \
  || fail "case5 census exited 0 despite fixture regression"
REG_LINE="$(cat "$TMP/stderr.txt")"
case "$REG_LINE" in
  *REGRESSION*fx-always-block*) pass "case5 REGRESSION names the dead guard" ;;
  *) fail "case5 no REGRESSION line for fx-always-block (stderr: $REG_LINE)" ;;
esac
case "$(printf '%s\n' "$MUT_OUT" | awk -F'\t' '$2=="fx-always-block.sh"' | cut -f7)" in
  REGRESSION) pass "case5 table marks fixture REGRESSION" ;;
  *) fail "case5 fixture column not REGRESSION" ;;
esac

# ── case 6: a bail on timeout is recorded with its reason, not absent ───────
assert_eq "case6 fx-hang state" "$(state_of fx-hang.sh)" "bail:timeout"
BAILREC="$(cat "$SBX/census-bail.fx-hang.sh.tsv" 2>/dev/null)"
case "$BAILREC" in
  *bail*timeout-after-3s*) pass "case6 bail recorded with reason" ;;
  *) fail "case6 bail record missing/wrong (got: $BAILREC)" ;;
esac

# ── case 7: absent from hooks.json ⇒ not-wired ───────────────────────────────
assert_eq "case7 fx-unwired state" "$(state_of fx-unwired.sh)" "not-wired"

# ── case 8: the census never mutates the hook tree or the journal ───────────
tar -cf "$TMP/snapafter" -C "$FIXROOT" hook-dir hooks.json fixtures
cmp -s "$snap_hook" "$TMP/snapafter" \
  && pass "case8 fixture hook tree byte-identical after census" \
  || fail "case8 census mutated the fixture hook tree"
cmp -s "$snap_journal" "$JDIR/journal.tsv" \
  && pass "case8 journal byte-identical after census" \
  || fail "case8 census wrote to the journal it only reads"

# ── lib unit: the verdict lib records ran / verdict / bail ──────────────────
LIBJ="$TMP/libjournal"; mkdir -p "$LIBJ"
(
  export LEADV2_GUARD_VERDICT_DIR="$LIBJ"
  # shellcheck disable=SC1090
  . "$GV_LIB"
  leadv2_gv_init Stop
  leadv2_gv_verdict block "unit"
  exit 0
)
N_RAN="$(awk -F'\t' '$4=="ran"' "$LIBJ/journal.tsv" | wc -l | tr -d ' ')"
N_BLK="$(awk -F'\t' '$4=="verdict" && $5 ~ /^block/' "$LIBJ/journal.tsv" | wc -l | tr -d ' ')"
assert_eq "lib records ran row" "$N_RAN" "1"
assert_eq "lib records block verdict" "$N_BLK" "1"
(
  export LEADV2_GUARD_VERDICT_DIR="$LIBJ"
  # shellcheck disable=SC1090
  . "$GV_LIB"
  leadv2_gv_init PreToolUse
  exit 7   # no verdict ⇒ EXIT trap must record the bail with the code
)
N_BAIL="$(awk -F'\t' '$4=="bail"' "$LIBJ/journal.tsv" | wc -l | tr -d ' ')"
BAIL_DETAIL="$(awk -F'\t' '$4=="bail"{print $5}' "$LIBJ/journal.tsv" | tail -1)"
assert_eq "lib EXIT trap records bail" "$N_BAIL" "1"
case "$BAIL_DETAIL" in
  *rc=7*) pass "lib bail carries the exit code" ;;
  *) fail "lib bail missing exit code (got: $BAIL_DETAIL)" ;;
esac

# ── human table still renders (founder reads this one) ──────────────────────
TABLE="$(bash "$CENSUS" --hooks-json "$FIXROOT/hooks.json" --hook-dir "$FIXROOT/hook-dir" \
  --journal-dir "$JDIR" --fixtures-dir "$FIXROOT/fixtures" --gv-lib "$GV_LIB" \
  --sandbox-dir "$TMP/sbx2" --timeout 3 --format table 2>/dev/null)"
case "$TABLE" in
  GUARD\ CENSUS*) pass "table renders with header" ;;
  *) fail "table output missing GUARD CENSUS header" ;;
esac
case "$TABLE" in
  *"fires-log-only"*) pass "table shows states in human form" ;;
  *) fail "table missing state column content" ;;
esac

printf '\n%s\n' "----------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  printf 'ALL PASS: %s checks passed\n' "$PASS"
  exit 0
fi
printf 'SUITE RED: %s passed, %s FAILED\n' "$PASS" "$FAIL"
exit 1
