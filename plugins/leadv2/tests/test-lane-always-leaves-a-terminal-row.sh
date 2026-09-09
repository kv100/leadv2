#!/usr/bin/env bash
# plugins/leadv2/tests/test-lane-always-leaves-a-terminal-row.sh
#
# LANE-TERMINAL-ROW / E2E-KILLRATE-01 (founder order 2026-09-09): three lanes
# finished mergeable work and died without a journal terminal row -- from the
# outside a finished lane and a crashed lane were indistinguishable, and the
# lead answered `abandon` on lanes whose work was complete. This suite pins
# the two negative controls the mission demanded:
#
#   1. THE SYMPTOM -- a lane whose worker exits normally after committing
#      leaves a journal `dispatch_terminal` row that says it finished.
#      Mutation: drop the _pc_journal_terminal_once call inside _dl_note's
#      body -> cases 1/2/3/6 go RED.
#   2. THE GUARD -- a lane killed with TERM/INT/HUP mid-run still leaves a
#      terminal row, and one that does NOT claim success; when work is
#      present the row names dead_with_unlanded_work + the commit sha,
#      never `landed`. Mutation: make _pc_crash_terminal return the success
#      state unconditionally -> cases 2/3/5/6 go RED.
#
# WHY THE STUB LEDGER (cases 1/2/3/6): the real ledger binary appends the
# journal row itself on a successful write-terminal, so against a healthy
# real ledger a mutation inside product-close could never redden this suite
# -- the ledger would keep providing the row. The stub records every ledger
# invocation and succeeds but never journals, making product-close's own
# journal write the only possible source of the row. Cases 4/5 then run the
# REAL ledger end-to-end and pin the opposite invariant: the backstop must
# stay silent there, so a healthy close still leaves exactly ONE row.
#
# Drives the REAL leadv2-dispatch-product-close.sh (never a reimplementation
# of its trap logic), kill-switches E2E_ON/REVIEW_ON = 0/0 (the sanctioned
# shortcut from test-dispatch-product-close-exit-trap.sh). Journal sandboxed
# via LEADV2_PROJECT_ROOT (TESTS-POLLUTE-REAL-JOURNAL-01: CLAUDE_PROJECT_ROOT
# takes precedence over it, so both are pinned/unset); ledger sandboxed via
# LEADV2_DISPATCH_TERMINAL_LEDGER_FILE; close-owner pidfiles via
# LEADV2_DISPATCH_CACHE_DIR. Never touches the real repo's journal, ledger,
# or cache.
# Run: bash plugins/leadv2/tests/test-lane-always-leaves-a-terminal-row.sh
# run-all-triggers: leadv2-dispatch-product-close
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
PRODUCT_CLOSE_SH="${PLUGIN_ROOT}/scripts/leadv2-dispatch-product-close.sh"
REAL_LEDGER_SH="${PLUGIN_ROOT}/scripts/leadv2-dispatch-ledger.sh"
JOURNAL_SH="${PLUGIN_ROOT}/scripts/leadv2-journal.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }
has() { # <haystack> <needle> -> rc0 when present
  printf '%s' "$1" | grep -qF -- "$2"
}

bash -n "$PRODUCT_CLOSE_SH" || { printf 'FAIL: bash syntax: product-close\nSUMMARY: pass=0 fail=1\n'; exit 1; }
pass "bash syntax: product-close"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-term-row.XXXXXX")"
cd "$TMP"
HOLDERS=()
cleanup() {
  local p
  for p in "${HOLDERS[@]:-}"; do kill "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT
ROOT="$TMP/root"; STATE="$TMP/state"; CACHE="$TMP/cache"
mkdir -p "$ROOT" "$STATE" "$CACHE"
# A dispatched worker can export its own lane root into this test process.
# Cases without a fixture lane must not accidentally classify that ambient,
# dirty checkout as the subject of their crash row.
unset CLAUDE_PROJECT_ROOT CLAUDE_PROJECT_DIR LEADV2_LANE_WORK_ROOT
export LEADV2_PROJECT_ROOT="$ROOT"
export LEADV2_STATE_ROOT="$STATE"
export LEADV2_DISPATCH_CACHE_DIR="$CACHE"
export LEADV2_JOURNAL_BIN="$JOURNAL_SH"
export LEADV2_DISPATCH_TERMINAL_LEDGER=1
# RE-ENTRY GUARD: the close under test runs the builder-selfcheck gate over
# the lane diff (gtimeout <suite>), and this suite + product-close.sh ARE the
# lane diff in the worktree this suite runs from -- without this switch the
# close would launch this very suite again (suite -> close -> selfcheck ->
# suite -> ...). `never` disables only the suite-execution leg; bash -n /
# py_compile still run. This mirrors what a real dispatched lane gets: the
# worker runs its own falsification set BEFORE the close gate ever sees it.
export LEADV2_BUILDER_SELFCHECK=0

# All journal rows for one sig ("" when the journal has none).
jrows() { bash "${JOURNAL_SH}" tail "dispatch-$1" 100000 2>/dev/null || true; }
# Count of dispatch_terminal rows for one sig (dispatch_terminal_dedup does
# not count: the trailing space is load-bearing).
nterm() { jrows "$1" | grep -cF "dispatch_terminal task=$1 " || true; }
hold() { sleep 300 & HOLDERS+=("$!"); disown "$!" 2>/dev/null || true; }

# Stub ledger: records argv, always succeeds, NEVER journals.
STUB_LOG="$TMP/ledger-stub.log"; : > "$STUB_LOG"; export STUB_LOG
STUB_LEDGER="$TMP/stub-ledger.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${STUB_LOG}"\nexit 0\n' > "$STUB_LEDGER"
chmod +x "$STUB_LEDGER"

# Product-close is post-worker code. These fixtures model the worker having
# already committed its deliverable before the close owner starts.
make_committed_lane() { # <path>
  local lane="$1"
  git init -q "$lane"
  git -C "$lane" -c user.name=fixture -c user.email=fixture@localhost commit -q --allow-empty -m "lane anchor"
  LANE_START_SHA="$(git -C "$lane" rev-parse HEAD)"
  printf 'worker fix\n' > "$lane/src.txt"
  git -C "$lane" add src.txt
  git -C "$lane" -c user.name=worker -c user.email=worker@localhost commit -q -m "work"
}

# ── Case 1 (THE SYMPTOM): normal finish after commit -> journal says landed ──────
SIG1="11a1c1a1"
LANE1="$TMP/lane1"; make_committed_lane "$LANE1"
LEADV2_LANE_WORK_ROOT="$LANE1" LEADV2_LANE_START_SHA="$LANE_START_SHA" LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG1" codex "" 0 0 "" >"$TMP/out1.log" 2>&1
rc1=$?
if [[ "$rc1" -eq 0 ]]; then pass "c1: worker exited normally, close exited 0"; else fail "c1: expected rc=0, got ${rc1}" "$(tail -3 "$TMP/out1.log" 2>/dev/null)"; fi
t1="$(jrows "$SIG1")"
if [[ "$(nterm "$SIG1")" -eq 1 ]]; then pass "c1: exactly one dispatch_terminal journal row"; else fail "c1: expected 1 terminal row, got $(nterm "$SIG1")" "$t1"; fi
if has "$t1" "dispatch_terminal task=$SIG1 terminal=landed"; then pass "c1: the row says finished (terminal=landed)"; else fail "c1: row does not say landed" "$t1"; fi
if grep -qF "write-terminal $SIG1" "$STUB_LOG"; then pass "c1: ledger was still consulted (stub recorded write-terminal)"; else fail "c1: ledger never consulted" "$(tail -2 "$STUB_LOG")"; fi

# ── Case 2 (THE GUARD): TERM mid-run, no work -> dead, never success ─────────────
SIG2="22b2c2b2"
hold
LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG2" sonnet "${HOLDERS[0]}" 0 0 "" >"$TMP/out2.log" 2>&1 &
PC2=$!
sleep 1.2
kill -TERM "$PC2" 2>/dev/null
wait "$PC2" 2>/dev/null; rc2=$?
t2="$(jrows "$SIG2")"
if [[ "$rc2" -eq 143 ]]; then pass "c2: TERM converted to exit 143, EXIT trap ran"; else fail "c2: expected rc=143, got ${rc2}" "$(tail -3 "$TMP/out2.log" 2>/dev/null)"; fi
if [[ "$(nterm "$SIG2")" -eq 1 ]]; then pass "c2: exactly one dispatch_terminal journal row"; else fail "c2: expected 1 terminal row, got $(nterm "$SIG2")" "$t2"; fi
if has "$t2" "terminal=dead cause=crashed_unfinished"; then pass "c2: row says dead/crashed_unfinished"; else fail "c2: row is not dead/crashed_unfinished" "$t2"; fi
if has "$t2" "source=exit_trap"; then pass "c2: row carries its provenance (source=exit_trap)"; else fail "c2: no source=exit_trap" "$t2"; fi
if has "$t2" "terminal=landed"; then fail "c2: killed lane claims success (terminal=landed)" "$t2"; else pass "c2: killed lane does NOT claim success"; fi
if has "$t2" "dead_with_unlanded_work"; then fail "c2: workless lane claims dead_with_unlanded_work" "$t2"; else pass "c2: workless lane stays plain dead"; fi

# ── Case 3 (THE CORE): TERM mid-run, work committed -> dead_with_unlanded_work ──
SIG3="33c3c3c3"
LANE3="$TMP/lane3"
git init -q "$LANE3"
git -C "$LANE3" -c user.name=fixture -c user.email=fixture@localhost commit -q --allow-empty -m "lane anchor"
hold
LEADV2_LANE_WORK_ROOT="$LANE3" LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG3" sonnet "${HOLDERS[1]}" 0 0 "" >"$TMP/out3.log" 2>&1 &
PC3=$!
sleep 1.2
printf 'worker fix\n' > "$LANE3/src.txt"
git -C "$LANE3" add src.txt
git -C "$LANE3" -c user.name=worker -c user.email=worker@localhost commit -q -m "work"
WORK_SHA3="$(git -C "$LANE3" rev-parse --short HEAD)"
kill -TERM "$PC3" 2>/dev/null
wait "$PC3" 2>/dev/null; rc3=$?
t3="$(jrows "$SIG3")"
if [[ "$rc3" -eq 143 ]]; then pass "c3: TERM converted to exit 143, EXIT trap ran"; else fail "c3: expected rc=143, got ${rc3}" "$(tail -3 "$TMP/out3.log" 2>/dev/null)"; fi
if [[ "$(nterm "$SIG3")" -eq 1 ]]; then pass "c3: exactly one dispatch_terminal journal row"; else fail "c3: expected 1 terminal row, got $(nterm "$SIG3")" "$t3"; fi
if has "$t3" "terminal=dead_with_unlanded_work"; then pass "c3: row says dead_with_unlanded_work (work present, salvage)"; else fail "c3: row does not distinguish work-present death" "$t3"; fi
if has "$t3" "commit=$WORK_SHA3"; then pass "c3: row names the unlanded commit (commit=$WORK_SHA3)"; else fail "c3: commit sha missing from row" "$t3"; fi
if has "$t3" "terminal=landed"; then fail "c3: killed lane claims success (terminal=landed)" "$t3"; else pass "c3: killed lane does NOT claim success"; fi

# ── Case 4 (PRODUCTION PARITY): real ledger, normal finish -> exactly one row ────
SIG4="44d4c4d4"
LED4="$TMP/ledger4.jsonl"
LANE4="$TMP/lane4"; make_committed_lane "$LANE4"
LEADV2_LANE_WORK_ROOT="$LANE4" LEADV2_LANE_START_SHA="$LANE_START_SHA" LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LED4" bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG4" codex "" 0 0 "" >"$TMP/out4.log" 2>&1
rc4=$?
t4="$(jrows "$SIG4")"
if [[ "$rc4" -eq 0 ]]; then pass "c4: real-ledger close exited 0"; else fail "c4: expected rc=0, got ${rc4}" "$(tail -3 "$TMP/out4.log" 2>/dev/null)"; fi
if [[ "$(nterm "$SIG4")" -eq 1 ]]; then pass "c4: healthy ledger path leaves EXACTLY one row (backstop silent, no doubles)"; else fail "c4: expected 1 terminal row, got $(nterm "$SIG4")" "$t4"; fi
if grep -q '"terminal":"landed"' "$LED4" 2>/dev/null; then pass "c4: ledger row recorded landed"; else fail "c4: no landed row in ledger file" "$(cat "$LED4" 2>/dev/null)"; fi

# ── Case 5 (REAL LEDGER + TERM + WORK): enum end-to-end through write_terminal ───
SIG5="55e5c5c5"
LANE5="$TMP/lane5"
git init -q "$LANE5"
git -C "$LANE5" -c user.name=fixture -c user.email=fixture@localhost commit -q --allow-empty -m "lane anchor"
LED5="$TMP/ledger5.jsonl"
hold
LEADV2_LANE_WORK_ROOT="$LANE5" LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LED5" bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG5" sonnet "${HOLDERS[2]}" 0 0 "" >"$TMP/out5.log" 2>&1 &
PC5=$!
sleep 1.2
printf 'worker fix\n' > "$LANE5/src.txt"
git -C "$LANE5" add src.txt
git -C "$LANE5" -c user.name=worker -c user.email=worker@localhost commit -q -m "work"
kill -TERM "$PC5" 2>/dev/null
wait "$PC5" 2>/dev/null; rc5=$?
t5="$(jrows "$SIG5")"
if [[ "$rc5" -eq 143 ]]; then pass "c5: TERM converted to exit 143"; else fail "c5: expected rc=143, got ${rc5}" "$(tail -3 "$TMP/out5.log" 2>/dev/null)"; fi
if grep -q '"terminal":"dead_with_unlanded_work"' "$LED5" 2>/dev/null; then pass "c5: real ledger accepts dead_with_unlanded_work end-to-end"; else fail "c5: ledger row is not dead_with_unlanded_work" "$(cat "$LED5" 2>/dev/null)"; fi
if [[ "$(nterm "$SIG5")" -eq 1 ]]; then pass "c5: exactly one dispatch_terminal journal row (ledger's own append)"; else fail "c5: expected 1 terminal row, got $(nterm "$SIG5")" "$t5"; fi
if has "$t5" "terminal=dead_with_unlanded_work"; then pass "c5: journal row carries dead_with_unlanded_work"; else fail "c5: journal row missing the state" "$t5"; fi

# ── Case 6: INT and HUP take the same dead row, never success ────────────────────
C6_SPECS="INT:130:66i6c6c6 HUP:129:77h7c7c7"
for spec in $C6_SPECS; do
  sig_name="${spec%%:*}"; rest="${spec#*:}"; want_rc="${rest%%:*}"; sig8="${rest#*:}"
  hold
  # Background bash inherits ignored INT/HUP on macOS. A foreground wrapper
  # starts a timer that signals its own PID and then execs product-close in
  # that same PID, so each close-script trap is actually exercised.
  LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash -c '( sleep 1.2; kill "-$0" "$$" ) & exec bash "$@"' "$sig_name" "$PRODUCT_CLOSE_SH" "$ROOT" "$sig8" sonnet "${HOLDERS[$(( ${#HOLDERS[@]} - 1 ))]}" 0 0 "" >"$TMP/out-$sig8.log" 2>&1
  rcx=$?
  tx="$(jrows "$sig8")"
  if [[ "$rcx" -eq "$want_rc" ]]; then pass "c6/$sig_name: converted to exit $want_rc, EXIT trap ran"; else fail "c6/$sig_name: expected rc=$want_rc, got ${rcx}" "$(tail -3 "$TMP/out-$sig8.log" 2>/dev/null)"; fi
  if [[ "$(nterm "$sig8")" -eq 1 ]]; then pass "c6/$sig_name: exactly one dispatch_terminal journal row"; else fail "c6/$sig_name: expected 1 terminal row, got $(nterm "$sig8")" "$tx"; fi
  if has "$tx" "terminal=dead"; then pass "c6/$sig_name: row says dead"; else fail "c6/$sig_name: row does not say dead" "$tx"; fi
  if has "$tx" "terminal=landed"; then fail "c6/$sig_name: killed lane claims success" "$tx"; else pass "c6/$sig_name: no success claim"; fi
done

# ── Negative controls: mutations are strictly inside the real function bodies ────
# The controls run temporary copies, never mutate the working tree. Each passes
# only when its targeted invariant goes RED; the ordinary cases above are the
# corresponding GREEN proof.
MUT_NOJ="$TMP/product-close-mut-nojournal.sh"
cp "$PRODUCT_CLOSE_SH" "$MUT_NOJ"
python3 -c 'import sys
p = sys.argv[1]
s = open(p).read()
needle = "  _pc_journal_terminal_once \"$1\" \"$2\" \"${_PC_TERMINAL_EVIDENCE}\"\n"
assert s.count(needle) == 1, "terminal-writer call site not unique"
s = s.replace(needle, "  : # MUTATION: terminal journal backstop removed inside _dl_note\n", 1)
open(p, "w").write(s)' "$MUT_NOJ"
SIG7="88m8c8c8"
LANE7="$TMP/lane7"; make_committed_lane "$LANE7"
LEADV2_LANE_WORK_ROOT="$LANE7" LEADV2_LANE_START_SHA="$LANE_START_SHA" LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash "$MUT_NOJ" "$ROOT" "$SIG7" codex "" 0 0 "" >"$TMP/out7.log" 2>&1
rc7=$?
t7="$(jrows "$SIG7")"
if [[ "$rc7" -eq 0 && "$(nterm "$SIG7")" -eq 0 ]]; then
  pass "NC1 RED: dropping _dl_note's in-body journal write recreates finished-in-silence"
else
  fail "NC1: mutated terminal writer did not go red" "$t7"
fi

MUT_SUCCESS="$TMP/product-close-mut-success.sh"
cp "$PRODUCT_CLOSE_SH" "$MUT_SUCCESS"
python3 -c 'import sys
p = sys.argv[1]
s = open(p).read()
needle = "_pc_crash_terminal() {  # -> stdout: <state><x1f><cause><x1f><evidence>\n"
assert s.count(needle) == 1, "crash classifier function not unique"
repl = needle + "  printf \"landed\\x1fmutation_success\\x1fsource=mutation\\n\"; return 0 # MUTATION inside _pc_crash_terminal body\n"
s = s.replace(needle, repl, 1)
open(p, "w").write(s)' "$MUT_SUCCESS"
SIG8="99n9c9c9"; LANE8="$TMP/lane8"
git init -q "$LANE8"
git -C "$LANE8" -c user.name=fixture -c user.email=fixture@localhost commit -q --allow-empty -m "lane anchor"
hold
LEADV2_LANE_WORK_ROOT="$LANE8" LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER" bash "$MUT_SUCCESS" "$ROOT" "$SIG8" sonnet "${HOLDERS[${#HOLDERS[@]}-1]}" 0 0 "" >"$TMP/out8.log" 2>&1 &
PC8=$!
sleep 1.2
kill -TERM "$PC8" 2>/dev/null
wait "$PC8" 2>/dev/null; rc8=$?
t8="$(jrows "$SIG8")"
if [[ "$rc8" -eq 143 ]] && has "$t8" "terminal=landed"; then
  pass "NC2 RED: unconditional success inside crash classifier falsely marks TERM as landed"
else
  fail "NC2: mutated crash classifier did not expose false success" "$t8"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
