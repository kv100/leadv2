#!/usr/bin/env bash
# T-o (SUPERVISOR-AUDIT-01): dispatch terminal-state ledger -- write-once, dedup, sweep.
# CLI-only (this script is NEVER sourced -- see leadv2-dispatch-ledger.sh's own doc header
# for why it is called as a subprocess, not a library, by dispatch-code.sh/dispatch-
# product-close.sh once wired).
set -uo pipefail

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
BIN="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-ledger.sh"
LEDGER_FILE="$ROOT/dispatch-ledger.jsonl"
JOURNAL_LOG="$ROOT/journal.log"
JOURNAL_STUB="$ROOT/journal-stub.sh"
cat > "$JOURNAL_STUB" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${JOURNAL_LOG}"
EOF
chmod +x "$JOURNAL_STUB"

export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE"
export LEADV2_JOURNAL_BIN="$JOURNAL_STUB"
export PROJECT_ROOT="$ROOT"
# SD-LEDGER-SWEEP-HARDEN-01: cmd_sweep() is default-off in production pending the
# attempt-scoped hardening (see leadv2-dispatch-ledger.sh's own cmd_sweep header) -- this
# suite still exercises the real (future-enabled) sweep behavior, so it sets the flag.
export LEADV2_LEDGER_SWEEP_ENABLE=1

FAIL=0

# --- 1: first write for a sig succeeds and is the only row ---
bash "$BIN" write-terminal "aaaa1111" "task-1" "landed" "confirmed" "handle=abc" \
  || { echo "FAIL 1: write-terminal returned nonzero"; FAIL=1; }
rows="$(grep -c . "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows" -eq 1 ]] || { echo "FAIL 1: expected 1 row, got $rows"; FAIL=1; }
grep -q '"task_sig":"aaaa1111"' "$LEDGER_FILE" || { echo "FAIL 1: row missing task_sig"; FAIL=1; }
grep -q '"terminal":"landed"' "$LEDGER_FILE" || { echo "FAIL 1: row missing terminal=landed"; FAIL=1; }

# --- 2: a second write for the SAME sig is a dedup no-op, not a second row ---
bash "$BIN" write-terminal "aaaa1111" "task-1" "dead" "crash" "" \
  || { echo "FAIL 2: dedup write returned nonzero (should be a successful no-op)"; FAIL=1; }
rows2="$(grep -c . "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows2" -eq 1 ]] || { echo "FAIL 2: expected still 1 row after dedup attempt, got $rows2"; FAIL=1; }
grep -q '"terminal":"landed"' "$LEDGER_FILE" || { echo "FAIL 2: original terminal was overwritten"; FAIL=1; }
grep -q 'dispatch_terminal_dedup task=aaaa1111 attempted=dead' "$JOURNAL_LOG" || { echo "FAIL 2: missing dedup journal line"; FAIL=1; }

# --- 3: `exists` reflects reality ---
bash "$BIN" exists "aaaa1111" || { echo "FAIL 3: exists check false-negative"; FAIL=1; }
if bash "$BIN" exists "bbbb2222"; then echo "FAIL 3: exists check false-positive for unwritten sig"; FAIL=1; fi

# --- 4: a different sig gets its own independent row ---
bash "$BIN" write-terminal "bbbb2222" "task-2" "refused" "duplicate_task_signature" "" \
  || { echo "FAIL 4: write-terminal for a second sig failed"; FAIL=1; }
rows4="$(grep -c . "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows4" -eq 2 ]] || { echo "FAIL 4: expected 2 rows total, got $rows4"; FAIL=1; }

# --- 5: an invalid terminal value is rejected, no row written ---
if bash "$BIN" write-terminal "cccc3333" "task-3" "bogus" "x" ""; then
  echo "FAIL 5: invalid terminal value was accepted"; FAIL=1
fi
if grep -q '"task_sig":"cccc3333"' "$LEDGER_FILE"; then
  echo "FAIL 5: a row was written despite the invalid terminal"; FAIL=1
fi

# --- 6: JSON-unsafe characters in cause/evidence are sanitized, not left raw ---
bash "$BIN" write-terminal "dddd4444" "task-4" "dead" 'quote"here' $'newline\nhere' \
  || { echo "FAIL 6: write with unsafe chars failed"; FAIL=1; }
python3 -c "
import json
with open('$LEDGER_FILE') as fh:
    lines = [l for l in fh if '\"dddd4444\"' in l]
assert len(lines) == 1, lines
json.loads(lines[0])  # must parse as valid JSON
" || { echo "FAIL 6: row is not valid JSON"; FAIL=1; }

# --- 7: sweep -- a lane-liveness stub says one dispatch-<sig8> lane is dead, no terminal
#         yet, NO close-owner record, and OLD ENOUGH to clear the grace window -> sweep
#         writes terminal=dead cause=no_close_owner (round2: absent record + old row); a
#         lane with no terminal-owning prefix or a non-dead verdict is left untouched.
#         age_s is set past LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S (set to 60 here) so this
#         case exercises the "genuinely never got a close gate" path, not the grace window.
export LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S=60
LANE_LIVENESS_STUB="$ROOT/lane-liveness-stub.sh"
cat > "$LANE_LIVENESS_STUB" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[
  {"lane":"dispatch-eeee5555","verdict":"dead:no_handoff_dir","age_s":9999},
  {"lane":"dispatch-aaaa1111","verdict":"dead:no_handoff_dir","age_s":9999},
  {"lane":"dispatch-ffff6666","verdict":"alive","age_s":9999},
  {"lane":"some-other-lane","verdict":"dead:no_handoff_dir","age_s":9999}
]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB" bash "$BIN" sweep 2>"$ROOT/sweep.err"
grep -q '"task_sig":"eeee5555"' "$LEDGER_FILE" || { echo "FAIL 7: dead lane with no prior terminal was not swept"; FAIL=1; cat "$ROOT/sweep.err"; }
grep -q '"task_sig":"eeee5555".*"cause":"no_close_owner"' "$LEDGER_FILE" || { echo "FAIL 7: swept row missing cause=no_close_owner"; FAIL=1; }
rows7="$(grep -c . "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows7" -eq 4 ]] || { echo "FAIL 7: expected 4 rows after sweep (aaaa1111 already had one, eeee5555 newly swept, others untouched), got $rows7"; FAIL=1; }
if grep -q '"task_sig":"ffff6666"' "$LEDGER_FILE"; then echo "FAIL 7: an ALIVE lane was swept"; FAIL=1; fi

# --- 8 (round2 finding 3): a dead-verdict lane whose close-owner pidfile records an
#         ALIVE pid is NEVER swept, even though the worker lane itself reports dead.
export PROJECT_ROOT="$ROOT"
CLOSE_OWNER_ALIVE_FILE="$(PROJECT_ROOT="$ROOT" bash "$(dirname "$BIN")/leadv2-state-path.sh" --no-link "dispatch-close-owner/11112222.pid")"
mkdir -p "$(dirname "$CLOSE_OWNER_ALIVE_FILE")"
sleep 30 & ALIVE_PID=$!
printf '%s\n' "$ALIVE_PID" > "$CLOSE_OWNER_ALIVE_FILE"
LANE_LIVENESS_STUB8="$ROOT/lane-liveness-stub8.sh"
cat > "$LANE_LIVENESS_STUB8" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-11112222","verdict":"dead:no_handoff_dir","age_s":9999}]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB8"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB8" bash "$BIN" sweep 2>"$ROOT/sweep8.err"
if grep -q '"task_sig":"11112222"' "$LEDGER_FILE"; then
  echo "FAIL 8: a lane whose close-owner pid is ALIVE was swept"; FAIL=1
fi
kill "$ALIVE_PID" 2>/dev/null; wait "$ALIVE_PID" 2>/dev/null

# --- 9 (round2 finding 3): same lane, close-owner pid now DEAD -> sweep proceeds with
#         the NORMAL cause (not no_close_owner -- a record was found, just stale).
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB8" bash "$BIN" sweep 2>"$ROOT/sweep9.err"
grep -q '"task_sig":"11112222"' "$LEDGER_FILE" || { echo "FAIL 9: lane with dead close-owner pid was not swept"; FAIL=1; }
grep -q '"task_sig":"11112222".*"cause":"swept"' "$LEDGER_FILE" || { echo "FAIL 9: swept row should carry cause=swept (record found, pid dead), not no_close_owner"; FAIL=1; }

# --- 10 (round2 finding 3): NO close-owner record, but the row is YOUNG (inside the
#         grace window) -> sweep must NOT sweep it (a legitimate not-yet-launched
#         close gate must not be mistaken for "never coming").
export LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S=7200
LANE_LIVENESS_STUB10="$ROOT/lane-liveness-stub10.sh"
cat > "$LANE_LIVENESS_STUB10" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-33334444","verdict":"dead:no_handoff_dir","age_s":5}]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB10"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB10" bash "$BIN" sweep 2>"$ROOT/sweep10.err"
if grep -q '"task_sig":"33334444"' "$LEDGER_FILE"; then
  echo "FAIL 10: a young (grace-window) lane with no close-owner record was swept"; FAIL=1
fi
unset LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S

# --- 11 (round3 finding 3): a quota-refused attempt (attempt token "pid-1000") for a
#         FRESH sig8 must not permanently poison that sig8 -- a LATER, separate attempt
#         (a different attempt token, simulating a new process's own $$ after quota
#         recovers) recording a real "landed" outcome must still be allowed to write.
bash "$BIN" write-terminal "ffff7777" "task-11" "refused" "all_arms_exhausted_quota" "chain=glm,codex" "pid-1000" \
  || { echo "FAIL 11: first (quota-refused) attempt write failed"; FAIL=1; }
rows11a="$(grep -c '"task_sig":"ffff7777"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows11a" -eq 1 ]] || { echo "FAIL 11: expected 1 row after first refused attempt, got $rows11a"; FAIL=1; }
if bash "$BIN" exists "ffff7777"; then
  echo "FAIL 11: exists() reported true after only a refused (retryable) row"; FAIL=1
fi
bash "$BIN" write-terminal "ffff7777" "task-11" "landed" "confirmed" "handle=xyz" "pid-2000" \
  || { echo "FAIL 11: later (retry) attempt write was blocked by the earlier refused row"; FAIL=1; }
rows11b="$(grep -c '"task_sig":"ffff7777"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows11b" -eq 2 ]] || { echo "FAIL 11: expected 2 rows after the retry landed, got $rows11b"; FAIL=1; }
grep -q '"task_sig":"ffff7777".*"terminal":"landed"' "$LEDGER_FILE" \
  || { echo "FAIL 11: no landed row recorded for the retried attempt"; FAIL=1; }
bash "$BIN" exists "ffff7777" || { echo "FAIL 11: exists() should be true once landed is recorded"; FAIL=1; }

# --- 12 (round3 finding 3): once a TRUE terminal (landed) is recorded, it is still
#         write-once -- a THIRD, later attempt (a fresh attempt token) trying to record
#         "dead" for the SAME sig8 must be deduped, not appended as a new row.
bash "$BIN" write-terminal "ffff7777" "task-11" "dead" "should_not_land" "" "pid-3000" \
  || { echo "FAIL 12: dedup-of-true-terminal write returned nonzero (should be a no-op)"; FAIL=1; }
rows12="$(grep -c '"task_sig":"ffff7777"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows12" -eq 2 ]] || { echo "FAIL 12: a 3rd row was appended after a TRUE terminal already landed, got $rows12 rows"; FAIL=1; }

# --- 13 (round3 finding 3): an intra-attempt idempotent retry (the SAME attempt token,
#         mirroring leadv2-dispatch-product-close.sh's EXIT trap re-confirming its own
#         already-recorded state) must still dedup -- "exactly one row per real attempt".
bash "$BIN" write-terminal "88889999" "task-13" "refused" "no_e2e_entrypoint" "repo=x" "pid-4000" \
  || { echo "FAIL 13: first attempt write failed"; FAIL=1; }
bash "$BIN" write-terminal "88889999" "task-13" "refused" "no_e2e_entrypoint" "repo=x" "pid-4000" \
  || { echo "FAIL 13: same-attempt idempotent retry write returned nonzero (should be a no-op)"; FAIL=1; }
rows13="$(grep -c '"task_sig":"88889999"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows13" -eq 1 ]] || { echo "FAIL 13: same-attempt retry appended a 2nd row, got $rows13 rows"; FAIL=1; }

# --- 14 (round4 finding 1): a refused (retryable) row already recorded for a sig8 must
#         NEVER be swept into `dead` -- dead is a TRUE terminal (write-once), so sweeping it
#         on top of a refused row would permanently block the later retry that case 11
#         proved must still be able to land. Same close-owner-absent-and-old setup as case 7
#         (grace window already cleared via LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S=60 above),
#         but this sig8 already has a refused row instead of no row at all.
bash "$BIN" write-terminal "99990000" "task-14" "refused" "all_arms_exhausted_quota" "chain=glm,codex" "pid-9000" \
  || { echo "FAIL 14: seeding a refused row failed"; FAIL=1; }
LANE_LIVENESS_STUB14="$ROOT/lane-liveness-stub14.sh"
cat > "$LANE_LIVENESS_STUB14" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-99990000","verdict":"dead:no_handoff_dir","age_s":9999}]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB14"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB14" bash "$BIN" sweep 2>"$ROOT/sweep14.err"
if grep -q '"task_sig":"99990000".*"terminal":"dead"' "$LEDGER_FILE"; then
  echo "FAIL 14: sweep appended dead on top of an existing refused row (permanently poisons the sig8)"; FAIL=1
fi
rows14="$(grep -c '"task_sig":"99990000"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows14" -eq 1 ]] || { echo "FAIL 14: expected still 1 row (only the seeded refused row) after sweep, got $rows14"; FAIL=1; }
# the retry path from case 11 must still be open: a later attempt can still record landed.
bash "$BIN" write-terminal "99990000" "task-14" "landed" "confirmed" "handle=xyz" "pid-9001" \
  || { echo "FAIL 14: a retry after the (non-)sweep was blocked from recording landed"; FAIL=1; }
grep -q '"task_sig":"99990000".*"terminal":"landed"' "$LEDGER_FILE" \
  || { echo "FAIL 14: no landed row recorded for the retry after the refused row survived sweep"; FAIL=1; }

# --- 15 (round4 finding 3): integration test against the REAL leadv2-lane-liveness.sh
#         producer (NOT a stub) -- a funnel dispatch whose active.yaml row records a
#         dispatch-<sig8> log_path, but whose stream file never existed (the exact
#         crash-lane shape: worker died before ever writing developer.stream.jsonl, or the
#         file was later cleaned up). The real producer resolves this to
#         verdict=dead:no_handoff_dir with a NULL verified log_path -- proving sig8
#         discovery can only succeed here via raw_log_path, never log_path.
REAL_LIVENESS_STATE="$ROOT/real-liveness-state"
REAL_LIVENESS_PROJECT="$ROOT/real-liveness-project"
mkdir -p "$REAL_LIVENESS_STATE" "$REAL_LIVENESS_PROJECT/docs/leadv2"
STATE_PATH_BIN_15="$(dirname "$BIN")/leadv2-state-path.sh"
LIVENESS_BIN_15="$(dirname "$BIN")/leadv2-lane-liveness.sh"
REAL_ACTIVE_YAML="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" PROJECT_ROOT="$REAL_LIVENESS_PROJECT" bash "$STATE_PATH_BIN_15" --no-link active.yaml)"
mkdir -p "$(dirname "$REAL_ACTIVE_YAML")"
printf 'sessions:\n  - task_id: founder-task-crash\n    phase: build\n    pid: null\n    log_path: docs/handoff/dispatch-deadbeef/developer.stream.jsonl\n' > "$REAL_ACTIVE_YAML"
# deliberately never create docs/handoff/dispatch-deadbeef/ (or its stream file) NOR
# docs/handoff/founder-task-crash/ -- this is the vanished-artifact crash lane.
LIVENESS_RAW_15="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT" \
  bash "$LIVENESS_BIN_15" --project-root "$REAL_LIVENESS_PROJECT" --all --json 2>"$ROOT/liveness15.err")"
echo "$LIVENESS_RAW_15" | grep -q '"log_path": null' \
  || { echo "FAIL 15 setup: expected the verified log_path to be null for the vanished-artifact lane, got: $LIVENESS_RAW_15"; FAIL=1; }
echo "$LIVENESS_RAW_15" | grep -q '"raw_log_path": "docs/handoff/dispatch-deadbeef/developer.stream.jsonl"' \
  || { echo "FAIL 15 setup: expected raw_log_path to survive despite the missing artifact, got: $LIVENESS_RAW_15"; FAIL=1; }
export LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S=0
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LIVENESS_BIN_15" \
  LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT" LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" \
  PROJECT_ROOT="$REAL_LIVENESS_PROJECT" \
  bash "$BIN" sweep 2>"$ROOT/sweep15.err"
grep -q '"task_sig":"deadbeef"' "$LEDGER_FILE" \
  || { echo "FAIL 15: sweep against the REAL liveness producer never resolved sig8 for the vanished-stream-file crash lane"; FAIL=1; cat "$ROOT/sweep15.err"; }
grep -q '"task_sig":"deadbeef".*"founder_task_id":"founder-task-crash"' "$LEDGER_FILE" \
  || { echo "FAIL 15: swept row missing the real founder_task_id (lane id), not the sig8-shaped lane string"; FAIL=1; }
unset LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S

if [[ $FAIL -eq 0 ]]; then
  echo 'PASS: write-once terminal ledger (write/dedup/exists/invalid/sanitize/sweep/close-owner/retryable-refused-parked/sweep-never-poisons-refused/real-liveness-vanished-stream-sig8)'
  exit 0
fi
exit 1
