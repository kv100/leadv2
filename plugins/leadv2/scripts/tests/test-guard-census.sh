#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-guard-census.sh leadv2-guard-verdict.sh
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
# Negative controls point LEADV2_CENSUS_UNDER_TEST at a mutated scratch copy
# of the census; the suite must go red against it (round 3 mutations).
CENSUS="${LEADV2_CENSUS_UNDER_TEST:-$SCRIPT_DIR/../leadv2-guard-census.sh}"
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
fixcol_of() { row_of "$1" | cut -f9; }
dflt_of() { row_of "$1" | cut -f7; }

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
case "$(printf '%s\n' "$MUT_OUT" | awk -F'\t' '$2=="fx-always-block.sh"' | cut -f9)" in
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

# ── case 9: degrade-wrapped entry ("cmd"; r=$?; if …; printf …) parses ──────
# fx-degrade-wrapped.sh is wired via the same "; r=$?; …" shape used by ~34
# real hooks.json entries. Locks GUARD-CENSUS-IS-WRONG-01's root cause: the
# old ltrimstr/split(" ")[0]/rtrimstr("\"") pipeline left a trailing `";` on
# the guard name, so an existing file was reported "missing".
assert_eq "case9 fx-degrade-wrapped state" "$(state_of fx-degrade-wrapped.sh)" "never-ran"
case "$(state_of fx-degrade-wrapped.sh)" in
  missing) fail "case9 degrade-wrapped guard falsely reported missing" ;;
  *) pass "case9 degrade-wrapped guard not falsely reported missing" ;;
esac

# ── case 9 mutation: reintroduce the old parser ⇒ case9 must go red ────────
OLDPARSE_CENSUS="$TMP/census-oldparse.sh"
python3 - "$CENSUS" "$OLDPARSE_CENSUS" <<'PY'
import sys
new_line = '       [(.command // "" | capture("(?<n>[A-Za-z0-9_.-]+\\\\.sh)"; "").n // ""), $e]\n'
old_line = '       [(.command | ltrimstr("\\"") | split(" ")[0] | split("/")[-1] | rtrimstr("\\"")), $e]\n'
src, dst = sys.argv[1], sys.argv[2]
with open(src) as fh:
    text = fh.read()
assert new_line in text, "fixture assumption stale: new jq line not found verbatim"
text = text.replace(new_line, old_line, 1)
with open(dst, "w") as fh:
    fh.write(text)
PY
OLDPARSE_OUT="$(bash "$OLDPARSE_CENSUS" --hooks-json "$FIXROOT/hooks.json" --hook-dir "$FIXROOT/hook-dir" \
  --journal-dir "$JDIR" --fixtures-dir "$FIXROOT/fixtures" --gv-lib "$GV_LIB" \
  --sandbox-dir "$TMP/sbx-oldparse" --timeout 3 --format tsv 2>/dev/null)"
# The old parser mangles the guard name itself (trailing `";`), so it no
# longer matches "fx-degrade-wrapped.sh" at all — it shows up as a
# differently-named "missing" row instead of correctly-named.
case "$(printf '%s\n' "$OLDPARSE_OUT" | awk -F'\t' '$2 ~ /^fx-degrade-wrapped\.sh/')" in
  *'missing'*) pass "case9-mutation: reverting the parser fix turns fx-degrade-wrapped missing (kills the fix)" ;;
  *) fail "case9-mutation: old-parser census did not reproduce the missing bug — mutation not caught" ;;
esac

# ── case 10: dispatcher-followed guard is wired, not not-wired ─────────────
# fx-dispatched.sh appears ONLY inside fx-dispatcher.sh's MANIFEST, never as
# a top-level hooks.json entry — exactly the leadv2-block-bash-heredoc.sh /
# leadv2-bash-pre-dispatch.sh shape from the brief.
assert_eq "case10 fx-dispatched state (wired via dispatcher)" "$(state_of fx-dispatched.sh)" "never-ran"
case "$(state_of fx-dispatched.sh)" in
  not-wired) fail "case10 dispatcher-routed guard falsely reported not-wired" ;;
  *) pass "case10 dispatcher-routed guard correctly seen as wired" ;;
esac

# ── case 10 mutation: drop dispatcher-follow ⇒ fx-dispatched goes not-wired ─
# (round 3, L3): the old awk deleted to the FIRST column-0 `fi`, so a future
# bare `fi` inside the dispatcher-follow block would silently truncate the
# mutation into a no-op. Now the deleted region is verified to contain the
# block's actual effect (`cat "$DISPATCHED" >> "$WIRED"`) or the case fails.
NODISPATCH_CENSUS="$TMP/census-nodispatch.sh"
python3 - "$CENSUS" "$NODISPATCH_CENSUS" <<'PY' || { fail "case10-mutation: dispatcher-follow block not found — mutation is a no-op"; }
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).readlines()
start = end = None
for i, l in enumerate(lines):
    if l.startswith('DISPATCHED="$TMP/dispatched.tsv"'):
        start = i
    elif start is not None and l.rstrip('\n') == 'fi':
        end = i
        break
assert start is not None and end is not None, "dispatcher-follow block not found"
chunk = ''.join(lines[start:end + 1])
assert 'cat "$DISPATCHED" >> "$WIRED"' in chunk, \
    "deleted region lacks the WIRED append — block layout changed, anchor stale"
open(dst, 'w').writelines(lines[:start] + lines[end + 1:])
PY
NODISPATCH_OUT="$(bash "$NODISPATCH_CENSUS" --hooks-json "$FIXROOT/hooks.json" --hook-dir "$FIXROOT/hook-dir" \
  --journal-dir "$JDIR" --fixtures-dir "$FIXROOT/fixtures" --gv-lib "$GV_LIB" \
  --sandbox-dir "$TMP/sbx-nodispatch" --timeout 3 --format tsv 2>/dev/null)"
case "$(printf '%s\n' "$NODISPATCH_OUT" | awk -F'\t' '$2=="fx-dispatched.sh"' | cut -f4)" in
  not-wired) pass "case10-mutation: removing dispatcher-follow turns fx-dispatched not-wired (kills the fix)" ;;
  *) fail "case10-mutation: no-dispatch-follow census did not reproduce not-wired — mutation not caught" ;;
esac

# ── case 11: DEFAULT column parses EVERY gate shape (round 3 high#2) ────────
# The old regex `\$\{LEADV2_X:-[01]\}` printed `always` for guards gated in
# any other shape. Each fixture guard carries one shape; the census must
# echo that shape verbatim on the founder-facing column.
assert_eq "case11 shape :\"\" (empty default)"      "$(dflt_of fx-gate-empty.sh)"    '${LEADV2_FX_EMPTY:-}'
assert_eq "case11 shape :-0"                        "$(dflt_of fx-gate-dflt0.sh)"    '${LEADV2_FX_GATE0:-0}'
assert_eq "case11 shape :-1"                        "$(dflt_of fx-gate-dflt1.sh)"    '${LEADV2_FX_GATE1:-1}'
assert_eq "case11 shape :=0"                        "$(dflt_of fx-gate-assign.sh)"   '${LEADV2_FX_ASSIGN:=0}'
assert_eq "case11 shape -1 (bare dash)"             "$(dflt_of fx-gate-baredash.sh)" '${LEADV2_FX_BARE-1}'
assert_eq "case11 shape quoted :-\"1\""             "$(dflt_of fx-gate-quoted.sh)"   '${LEADV2_FX_QUOTED:-"1"}'
assert_eq "case11 shape [[ \"\${X:-0}\" == 1 ]]"    "$(dflt_of fx-gate-bracket.sh)"  '${LEADV2_FX_BRACKET:-0}'
assert_eq "case11 nested default is brace-balanced" "$(dflt_of fx-gate-nested.sh)"   '${LEADV2_FX_NESTED:-${TMPDIR:-/tmp}}'

# ── case 12: not-wired row never inherits the previous guard's default ──────
# fx-gate-zunwired.sh is absent from hooks.json and sorts directly after
# fx-gate-quoted.sh, whose default is a non-empty gate string. Round 3
# high#1 leaked exactly that into this row (13 wrong rows in the R2
# artifact; live: leadv2-lead-read-guard.sh printed its neighbour's default).
assert_eq "case12 not-wired dflt is '-', never stale" "$(dflt_of fx-gate-zunwired.sh)" '-'
for g in fx-gate-assign.sh fx-gate-baredash.sh fx-gate-bracket.sh fx-gate-dflt0.sh \
         fx-gate-dflt1.sh fx-gate-empty.sh fx-gate-nested.sh fx-gate-quoted.sh; do
  case "$(state_of "$g")" in
    not-wired|missing) fail "case12 precondition: $g must be wired+present" ;;
  esac
done

# ── case 12 mutation: remove the per-row dflt reset ⇒ stale value returns ───
STALE_CENSUS="$TMP/census-stale-dflt.sh"
python3 - "$CENSUS" "$STALE_CENSUS" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
anchor = '  dflt="-"\n  if [ "$wired" -eq 0 ]; then'
with open(src) as fh:
    text = fh.read()
assert anchor in text, "fixture assumption stale: per-row reset not found verbatim"
text = text.replace(anchor, '  if [ "$wired" -eq 0 ]; then', 1)
with open(dst, "w") as fh:
    fh.write(text)
PY
STALE_OUT="$(bash "$STALE_CENSUS" --hooks-json "$FIXROOT/hooks.json" --hook-dir "$FIXROOT/hook-dir" \
  --journal-dir "$JDIR" --sandbox-dir "$TMP/sbx-stale" --timeout 3 --format tsv 2>/dev/null)"
case "$(printf '%s\n' "$STALE_OUT" | awk -F'\t' '$2=="fx-gate-zunwired.sh"' | cut -f7)" in
  '') fail "case12-mutation: mutated census produced no row for fx-gate-zunwired.sh" ;;
  -) fail "case12-mutation: stale-dflt mutation did NOT reproduce the leak — mutation not caught" ;;
  *) pass "case12-mutation: dropping the reset re-leaks the previous guard's default (kills the fix)" ;;
esac

# ── case 11 mutation: narrow the parser back to :-[01] ⇒ `always` returns ──
OLDREGEX_CENSUS="$TMP/census-old-regex.sh"
python3 - "$CENSUS" "$OLDREGEX_CENSUS" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
wide = r'\$\{LEADV2_[A-Za-z0-9_]+[^}]*\}'
narrow = r'\$\{LEADV2_[A-Za-z0-9_]+:-[01]\}'
with open(src) as fh:
    text = fh.read()
assert wide in text, "fixture assumption stale: wide dflt regex not found verbatim"
text = text.replace(wide, narrow, 1)
with open(dst, "w") as fh:
    fh.write(text)
PY
OLDREGEX_OUT="$(bash "$OLDREGEX_CENSUS" --hooks-json "$FIXROOT/hooks.json" --hook-dir "$FIXROOT/hook-dir" \
  --journal-dir "$JDIR" --sandbox-dir "$TMP/sbx-oldregex" --timeout 3 --format tsv 2>/dev/null)"
case "$(printf '%s\n' "$OLDREGEX_OUT" | awk -F'\t' '$2=="fx-gate-empty.sh"' | cut -f7)" in
  always) pass "case11-mutation: old :-[01]-only regex prints gated guard as always (kills the fix)" ;;
  *) fail "case11-mutation: old-regex census did not reproduce 'always' — mutation not caught" ;;
esac

printf '\n%s\n' "----------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  printf 'ALL PASS: %s checks passed\n' "$PASS"
  exit 0
fi
printf 'SUITE RED: %s passed, %s FAILED\n' "$PASS" "$FAIL"
exit 1
