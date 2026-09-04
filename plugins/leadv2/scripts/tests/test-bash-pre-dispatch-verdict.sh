#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# GUARD-CENSUS-IS-WRONG-01 round 2: the dispatcher hook had NO suite at all —
# every verdict-kind/rotation line was untested until this mapping.
# run-all-triggers: leadv2-bash-pre-dispatch.sh leadv2-guard-census.sh leadv2-guard-verdict.sh
# test-bash-pre-dispatch-verdict.sh — GUARD-CENSUS-IS-WRONG-01 round 2
#
# Runs the REAL plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh (copied into
# a sandbox dir so its MANIFEST resolves to stub guards) against a fake
# LEADV2_GUARD_VERDICT_DIR — never the real journal, never the real hook tree.
#
# Locked contract — the recorded verdict KIND is the guard's CONTRACT, not its
# chatter (round-1 bug: "any stdout/stderr bytes = log fire" permanently
# recorded quiet-pass guards as fires-log-only):
#   (a) exit 0 + stderr text      -> recorded `pass`, never a fire
#   (b) exit 2                    -> recorded `block`, hook exits 2
#   (c) exit 0 + hookSpecificOutput/additionalContext JSON -> recorded `inject`
#   (d) rotation fires at the cap (journal.tsv -> .1, keep 2 generations) and
#       the census still sees the rotated rows
#   (e) the records survive to the census table (state / LAST-FIRED columns)
#
# Mutation negative controls (each RUN and asserted to be caught):
#   (ma) restore "any bytes = log fire"   -> case (a) assertion goes red
#   (mb) remove the rotation call          -> case (d) assertion goes red
#
# Bash 3.2 only; every ${arr[@]} guarded under set -u.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/../../hooks/leadv2-bash-pre-dispatch.sh"
CENSUS="$SCRIPT_DIR/../leadv2-guard-census.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() { # $1 what  $2 actual  $3 want
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-bash-pre-dispatch.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

[ -f "$HOOK_SRC" ] || { echo "FATAL: real hook not found: $HOOK_SRC" >&2; exit 66; }

INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'

# Stub guards (named for the dispatcher manifest's ALWAYS entry so exactly one
# guard runs per invocation in the sandbox dir).
STUB_PASS="$TMP/stub-pass.sh";   cat > "$STUB_PASS" <<'EOF'
#!/usr/bin/env bash
echo "env-audit: skipping (placeholder)" >&2
exit 0
EOF
STUB_BLOCK="$TMP/stub-block.sh"; cat > "$STUB_BLOCK" <<'EOF'
#!/usr/bin/env bash
echo "stub guard: blocked" >&2
exit 2
EOF
STUB_INJECT="$TMP/stub-inject.sh"; cat > "$STUB_INJECT" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "stub note"}}'
exit 0
EOF
chmod +x "$STUB_PASS" "$STUB_BLOCK" "$STUB_INJECT" 2>/dev/null

make_hookdir() { # $1 dst  $2 stub guard
  mkdir -p "$1"
  cp "$HOOK_SRC" "$1/leadv2-bash-pre-dispatch.sh"
  cp "$2" "$1/leadv2-env-audit-pre-gate.sh"
  chmod +x "$1/leadv2-bash-pre-dispatch.sh" "$1/leadv2-env-audit-pre-gate.sh"
}

run_hook() { # $1 hookdir  $2 journal-dir ; -> hook rc ; streams in $TMP/out $TMP/err
  printf '%s' "$INPUT" \
    | LEADV2_GUARD_VERDICT_DIR="$2" bash "$1/leadv2-bash-pre-dispatch.sh" \
    > "$TMP/out" 2> "$TMP/err"
  echo $?
}

kinds_of() { # $1 journal-dir -> recorded verdict kinds (oldest first)
  awk -F'\t' '$4=="verdict" { print $5 }' "$1/journal.tsv" "$1/journal.tsv.1" 2>/dev/null
}

# ── case (a): exit 0 + stderr text → `pass`, never a fire ──────────────────
HA="$TMP/hook-a"; make_hookdir "$HA" "$STUB_PASS"
JA="$TMP/j-a"
rc="$(run_hook "$HA" "$JA")"
assert_eq "case a hook exit 0" "$rc" "0"
assert_eq "case a verdict kind is pass" "$(kinds_of "$JA" | tail -1)" "pass"
case "$(kinds_of "$JA")" in
  *log*) fail "case a quiet-pass guard recorded as a log fire" ;;
  *)     pass "case a no log-fire row for stderr-only guard" ;;
esac
ran_rows="$(awk -F'\t' '$4=="ran"' "$JA/journal.tsv" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "case a ran row recorded" "$ran_rows" "1"

# ── case (b): exit 2 → `block`, hook exits 2 ────────────────────────────────
HB="$TMP/hook-b"; make_hookdir "$HB" "$STUB_BLOCK"
JB="$TMP/j-b"
rc="$(run_hook "$HB" "$JB")"
assert_eq "case b hook exit 2" "$rc" "2"
assert_eq "case b verdict kind is block" "$(kinds_of "$JB" | tail -1)" "block"
case "$(cat "$TMP/err")" in
  *blocked*) pass "case b block reason reaches stderr" ;;
  *)         fail "case b stderr lost (got: $(cat "$TMP/err"))" ;;
esac

# ── case (c): exit 0 + hookSpecificOutput JSON → `inject` ──────────────────
HC="$TMP/hook-c"; make_hookdir "$HC" "$STUB_INJECT"
JC="$TMP/j-c"
rc="$(run_hook "$HC" "$JC")"
assert_eq "case c hook exit 0" "$rc" "0"
assert_eq "case c verdict kind is inject" "$(kinds_of "$JC" | tail -1)" "inject"
case "$(cat "$TMP/out")" in
  *hookSpecificOutput*) pass "case c inject JSON passes through stdout" ;;
  *)                    fail "case c stdout JSON lost (got: $(cat "$TMP/out"))" ;;
esac

# ── case (d): rotation at the cap; census still sees rotated rows ───────────
make_rot_fixture() { # $1 root ; seeds journal with 12 old rot-guard rows
  mkdir -p "$1/hooks" "$1/j"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/hooks/rot-guard.sh"
  chmod +x "$1/hooks/rot-guard.sh"
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/rot-guard.sh"}]}]}}\n' \
    > "$1/hooks.json"
  i=0
  while [ "$i" -lt 12 ]; do
    printf '2026-08-01T00:00:%02dZ\trot-guard.sh\tStop\tran\t-\n' "$i" >> "$1/j/journal.tsv"
    i=$((i + 1))
  done
}
make_hookdir_rot() { # $1 dst : hook + stub in a dir WITHOUT rot-guard.sh
  mkdir -p "$1"
  cp "$HOOK_SRC" "$1/leadv2-bash-pre-dispatch.sh"
  cp "$STUB_PASS" "$1/leadv2-env-audit-pre-gate.sh"
  chmod +x "$1/leadv2-bash-pre-dispatch.sh" "$1/leadv2-env-audit-pre-gate.sh"
}
HD="$TMP/hook-d";     make_hookdir_rot "$HD";     make_rot_fixture "$TMP/rot"
JD="$TMP/rot/j"
printf '%s' "$INPUT" \
  | LEADV2_GUARD_VERDICT_DIR="$JD" LEADV2_GUARD_VERDICT_MAX_ROWS=10 LEADV2_GUARD_VERDICT_MAX_BYTES=100000 \
    bash "$HD/leadv2-bash-pre-dispatch.sh" > /dev/null 2>&1
[ -f "$JD/journal.tsv.1" ] && pass "case d rotation created journal.tsv.1" \
  || fail "case d no rotation at cap (journal.tsv.1 missing)"
seeded="$(awk -F'\t' '$2=="rot-guard.sh"' "$JD/journal.tsv.1" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "case d seeded rows preserved in .1" "$seeded" "12"
live_rows="$(wc -l < "$JD/journal.tsv" | tr -d ' ')"
[ "$live_rows" -le 3 ] && pass "case d fresh journal.tsv small after rotate ($live_rows rows)" \
  || fail "case d journal.tsv not rotated ($live_rows rows remain)"
CENSUS_TSV="$(bash "$CENSUS" --hooks-json "$TMP/rot/hooks.json" --hook-dir "$TMP/rot/hooks" \
  --journal-dir "$JD" --format tsv 2>/dev/null)"
rot_row="$(printf '%s\n' "$CENSUS_TSV" | awk -F'\t' '$2=="rot-guard.sh"')"
assert_eq "case d census state for rotated-only evidence" "$(printf '%s' "$rot_row" | cut -f4)" "ran-never-fired"
case "$(printf '%s' "$rot_row" | cut -f5)" in
  2026-08-01*) pass "case d census LAST-RAN from rotated .1" ;;
  *) fail "case d census lost rotated rows (row: $rot_row)" ;;
esac

# ── case (e): records survive to the census table (fired / last-fired) ─────
make_tbl_fixture() { # $1 root
  mkdir -p "$1/hooks"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/hooks/leadv2-env-audit-pre-gate.sh"
  chmod +x "$1/hooks/leadv2-env-audit-pre-gate.sh"
  printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-env-audit-pre-gate.sh"}]}]}}\n' \
    > "$1/hooks.json"
}
census_row() { # $1 root  $2 journal-dir
  bash "$CENSUS" --hooks-json "$1/hooks.json" --hook-dir "$1/hooks" \
    --journal-dir "$2" --format tsv 2>/dev/null \
    | awk -F'\t' '$2=="leadv2-env-audit-pre-gate.sh"'
}
# e1: inject record → census shows a FIRE (fires-log-only) with last-fired set
make_tbl_fixture "$TMP/tbl-e1"
run_hook "$HC" "$TMP/j-e1" > /dev/null   # rerun stub-inject into a fresh journal
e1="$(census_row "$TMP/tbl-e1" "$TMP/j-e1")"
assert_eq "case e1 inject verdict -> census fire state" "$(printf '%s' "$e1" | cut -f4)" "fires-log-only"
case "$(printf '%s' "$e1" | cut -f6)" in
  -|"") fail "case e1 census LAST-FIRED empty (row: $e1)" ;;
  *)    pass "case e1 census LAST-FIRED populated" ;;
esac
# e2: pass-only record → census shows ran-never-fired, LAST-FIRED stays "-"
make_tbl_fixture "$TMP/tbl-e2"
run_hook "$HA" "$TMP/j-e2" > /dev/null   # stderr-only stub into a fresh journal
e2="$(census_row "$TMP/tbl-e2" "$TMP/j-e2")"
assert_eq "case e2 pass verdict -> census ran-never-fired" "$(printf '%s' "$e2" | cut -f4)" "ran-never-fired"
assert_eq "case e2 census LAST-FIRED stays '-'" "$(printf '%s' "$e2" | cut -f6)" "-"

# ── mutation negative control (ma): "any bytes = log fire" → case (a) red ──
MUT_A="$TMP/hook-mut-a"
mkdir -p "$MUT_A"
python3 - "$HOOK_SRC" "$MUT_A/leadv2-bash-pre-dispatch.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
anchor = '_lv2_gv_kind="pass"\n'
mutation = '_lv2_gv_kind="log"\n'
with open(src) as fh:
    text = fh.read()
assert anchor in text, "fixture assumption stale: pass-kind anchor not found"
text = text.replace(anchor, mutation, 1)
with open(dst, "w") as fh:
    fh.write(text)
PY
cp "$STUB_PASS" "$MUT_A/leadv2-env-audit-pre-gate.sh"
chmod +x "$MUT_A/leadv2-bash-pre-dispatch.sh" "$MUT_A/leadv2-env-audit-pre-gate.sh"
JMA="$TMP/j-mut-a"
run_hook "$MUT_A" "$JMA" > /dev/null 2>&1
assert_eq "mutation ma: any-bytes=log records 'log' (case a would fail)" \
  "$(kinds_of "$JMA" | tail -1)" "log"

# ── mutation negative control (mb): remove rotation → case (d) red ─────────
MUT_B="$TMP/hook-mut-b"
mkdir -p "$MUT_B"
python3 - "$HOOK_SRC" "$MUT_B/leadv2-bash-pre-dispatch.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
anchor = "_lv2_gv_rotate_journal 2>/dev/null || true\n"
with open(src) as fh:
    lines = fh.readlines()
assert anchor in lines, "fixture assumption stale: rotation call not found"
with open(dst, "w") as fh:
    fh.write("".join(l for l in lines if l != anchor))
PY
cp "$STUB_PASS" "$MUT_B/leadv2-env-audit-pre-gate.sh"
chmod +x "$MUT_B/leadv2-bash-pre-dispatch.sh" "$MUT_B/leadv2-env-audit-pre-gate.sh"
JMB="$TMP/rot-mutb/j"; make_rot_fixture "$TMP/rot-mutb"
printf '%s' "$INPUT" \
  | LEADV2_GUARD_VERDICT_DIR="$JMB" LEADV2_GUARD_VERDICT_MAX_ROWS=10 LEADV2_GUARD_VERDICT_MAX_BYTES=100000 \
    bash "$MUT_B/leadv2-bash-pre-dispatch.sh" > /dev/null 2>&1
[ -f "$JMB/journal.tsv.1" ] && fail "mutation mb: rotation still fired without the call — control catches nothing" \
  || pass "mutation mb: no rotation without the call (case d would fail)"

printf '\n%s\n' "----------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  printf 'ALL PASS: %s checks passed\n' "$PASS"
  exit 0
fi
printf 'SUITE RED: %s passed, %s FAILED\n' "$PASS" "$FAIL"
exit 1
