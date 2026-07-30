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
# SD-LEDGER-SWEEP-HARDEN-01: sweep now defaults ON (LEADV2_LEDGER_SWEEP_ENABLE=0 is the
# one-flip rollback) -- set explicitly here anyway so this suite's intent stays legible
# and immune to a future default change.
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
  {"lane":"dispatch-eeee5555","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-7001"},
  {"lane":"dispatch-aaaa1111","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-7002"},
  {"lane":"dispatch-ffff6666","verdict":"alive","age_s":9999,"attempt":"pid-7003"},
  {"lane":"some-other-lane","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-7004"}
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
{"lanes":[{"lane":"dispatch-11112222","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-8001"}]}
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
{"lanes":[{"lane":"dispatch-33334444","verdict":"dead:no_handoff_dir","age_s":5,"attempt":"pid-10001"}]}
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

# --- 14 (round4 finding 1; SD-LEDGER-SWEEP-HARDEN-01 "retryable-row-not-swept"): a
#         refused (retryable) row already recorded for a sig8, for the SAME attempt the
#         lane row now reports dead, must NEVER be swept into `dead` -- dead is a TRUE
#         terminal (write-once), so sweeping it on top of a refused row would permanently
#         block the later retry that case 11 proved must still be able to land.
#         LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S is unset since case 10 (line 144 above), so
#         this now runs at the real DEFAULT grace period (7200s), not an overridden one --
#         age_s=9999 clears it either way.
bash "$BIN" write-terminal "99990000" "task-14" "refused" "all_arms_exhausted_quota" "chain=glm,codex" "pid-9000" \
  || { echo "FAIL 14: seeding a refused row failed"; FAIL=1; }
LANE_LIVENESS_STUB14="$ROOT/lane-liveness-stub14.sh"
cat > "$LANE_LIVENESS_STUB14" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-99990000","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-9000"}]}
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

# --- 15 (round4 finding 3; SD-LEDGER-SWEEP-HARDEN-01 "vanished-artifact lane swept after
#         started_at+grace"): integration test against the REAL leadv2-lane-liveness.sh
#         producer (NOT a stub) -- a funnel dispatch whose active.yaml row records a
#         dispatch-<sig8> log_path, but whose stream file never existed (the exact
#         crash-lane shape: worker died before ever writing developer.stream.jsonl, or the
#         file was later cleaned up). The real producer resolves this to
#         verdict=dead:no_handoff_dir with a NULL verified log_path -- proving sig8
#         discovery can only succeed here via raw_log_path, never log_path.
#         round-5 finding 2: age_s used to stay null-coerced-to-0 forever on exactly this
#         shape, making an artifactless lane PERMANENTLY too young to sweep no matter how
#         long it had actually been dead; case 15 used to mask this by forcing the grace
#         period to zero. It no longer does -- started_at is deliberately ancient and
#         LEADV2_DISPATCH_CLOSE_OWNER_GRACE_S is left UNSET, so this now proves the sweep
#         at the REAL default grace period (7200s), deriving age from active.yaml's own
#         started_at instead of a missing artifact.
REAL_LIVENESS_STATE="$ROOT/real-liveness-state"
REAL_LIVENESS_PROJECT="$ROOT/real-liveness-project"
mkdir -p "$REAL_LIVENESS_STATE" "$REAL_LIVENESS_PROJECT/docs/leadv2"
STATE_PATH_BIN_15="$(dirname "$BIN")/leadv2-state-path.sh"
LIVENESS_BIN_15="$(dirname "$BIN")/leadv2-lane-liveness.sh"
REAL_ACTIVE_YAML="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" PROJECT_ROOT="$REAL_LIVENESS_PROJECT" bash "$STATE_PATH_BIN_15" --no-link active.yaml)"
mkdir -p "$(dirname "$REAL_ACTIVE_YAML")"
printf 'sessions:\n  - task_id: founder-task-crash\n    phase: build\n    pid: null\n    started_at: "2020-01-01T00:00:00Z"\n    attempt: "pid-15001"\n    log_path: docs/handoff/dispatch-deadbeef/developer.stream.jsonl\n' > "$REAL_ACTIVE_YAML"
# deliberately never create docs/handoff/dispatch-deadbeef/ (or its stream file) NOR
# docs/handoff/founder-task-crash/ -- this is the vanished-artifact crash lane.
LIVENESS_RAW_15="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT" \
  bash "$LIVENESS_BIN_15" --project-root "$REAL_LIVENESS_PROJECT" --all --json 2>"$ROOT/liveness15.err")"
echo "$LIVENESS_RAW_15" | grep -q '"log_path": null' \
  || { echo "FAIL 15 setup: expected the verified log_path to be null for the vanished-artifact lane, got: $LIVENESS_RAW_15"; FAIL=1; }
echo "$LIVENESS_RAW_15" | grep -q '"raw_log_path": "docs/handoff/dispatch-deadbeef/developer.stream.jsonl"' \
  || { echo "FAIL 15 setup: expected raw_log_path to survive despite the missing artifact, got: $LIVENESS_RAW_15"; FAIL=1; }
echo "$LIVENESS_RAW_15" | python3 -c "import json,sys; d=json.load(sys.stdin); a=d['lanes'][0]['age_s']; sys.exit(0 if isinstance(a,int) and a > 7200 else 1)" \
  || { echo "FAIL 15 setup: expected age_s derived from started_at to exceed the default grace period, got: $LIVENESS_RAW_15"; FAIL=1; }
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LIVENESS_BIN_15" \
  LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT" LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" \
  PROJECT_ROOT="$REAL_LIVENESS_PROJECT" \
  bash "$BIN" sweep 2>"$ROOT/sweep15.err"
grep -q '"task_sig":"deadbeef"' "$LEDGER_FILE" \
  || { echo "FAIL 15: sweep against the REAL liveness producer never resolved sig8 for the vanished-stream-file crash lane at default grace"; FAIL=1; cat "$ROOT/sweep15.err"; }
grep -q '"task_sig":"deadbeef".*"founder_task_id":"founder-task-crash"' "$LEDGER_FILE" \
  || { echo "FAIL 15: swept row missing the real founder_task_id (lane id), not the sig8-shaped lane string"; FAIL=1; }

# --- 15b (SD-LEDGER-SWEEP-HARDEN-01 companion, same shape, YOUNG started_at): proves the
#         started_at-derived age still respects the grace window -- a genuinely recent
#         artifactless lane must NOT be swept just because it has no artifact.
REAL_LIVENESS_PROJECT_YOUNG="$ROOT/real-liveness-project-young"
mkdir -p "$REAL_LIVENESS_PROJECT_YOUNG/docs/leadv2"
REAL_ACTIVE_YAML_YOUNG="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" PROJECT_ROOT="$REAL_LIVENESS_PROJECT_YOUNG" bash "$STATE_PATH_BIN_15" --no-link active.yaml)"
mkdir -p "$(dirname "$REAL_ACTIVE_YAML_YOUNG")"
NOW_ISO_15B="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'sessions:\n  - task_id: founder-task-crash-young\n    phase: build\n    pid: null\n    started_at: "%s"\n    attempt: "pid-15002"\n    log_path: docs/handoff/dispatch-1eadbeef/developer.stream.jsonl\n' "$NOW_ISO_15B" > "$REAL_ACTIVE_YAML_YOUNG"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LIVENESS_BIN_15" \
  LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT_YOUNG" LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" \
  PROJECT_ROOT="$REAL_LIVENESS_PROJECT_YOUNG" \
  bash "$BIN" sweep 2>"$ROOT/sweep15b.err"
if grep -q '"task_sig":"1eadbeef"' "$LEDGER_FILE"; then
  echo "FAIL 15b: a YOUNG artifactless lane (started_at just now) was swept -- grace window not respected"; FAIL=1
fi

# --- 16 (SD-LEDGER-SWEEP-HARDEN-01 "wrong-attempt not swept"): round-5 finding (a) -- the
#         OLD sig8-wide dispatch_any_terminal_exists() preflight let a stale row for a
#         DIFFERENT (wrong) attempt hide a later, genuinely dead retry forever. Proves the
#         opposite failure mode from case 14: a refused row for attempt "pid-16000" must
#         NOT block sweeping a dead lane whose row now carries a DIFFERENT attempt
#         "pid-16999" -- the attempt-scoped check must let this one through, appending its
#         own dead row, while the sig8-wide TRUE-terminal guard (unrelated to attempt
#         matching) stays intact for the landed/dead case (proven separately by case 12).
bash "$BIN" write-terminal "aaaa6666" "task-16" "refused" "all_arms_exhausted_quota" "chain=glm" "pid-16000" \
  || { echo "FAIL 16: seeding the wrong-attempt refused row failed"; FAIL=1; }
LANE_LIVENESS_STUB16="$ROOT/lane-liveness-stub16.sh"
cat > "$LANE_LIVENESS_STUB16" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-aaaa6666","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"pid-16999"}]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB16"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB16" bash "$BIN" sweep 2>"$ROOT/sweep16.err"
grep -q '"task_sig":"aaaa6666".*"terminal":"dead".*"attempt":"pid-16999"' "$LEDGER_FILE" \
  || { echo "FAIL 16: a genuinely dead retry (different attempt) was hidden by an old refused row for the WRONG attempt"; FAIL=1; cat "$ROOT/sweep16.err"; }
grep -q '"task_sig":"aaaa6666".*"terminal":"refused".*"attempt":"pid-16000"' "$LEDGER_FILE" \
  || { echo "FAIL 16: the original wrong-attempt refused row was lost/mutated, expected append-only"; FAIL=1; }
rows16="$(grep -c '"task_sig":"aaaa6666"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows16" -eq 2 ]] || { echo "FAIL 16: expected exactly 2 rows (refused for pid-16000 + dead for pid-16999), got $rows16"; FAIL=1; }
# now prove the sig8-wide TRUE-terminal guard is NOT weakened by attempt-scoping: once
# aaaa6666 has a TRUE terminal (dead, just recorded above), a THIRD attempt must still be
# deduped, exactly like case 12 for landed.
bash "$BIN" write-terminal "aaaa6666" "task-16" "landed" "should_not_land" "" "pid-17000" \
  || { echo "FAIL 16: post-sweep dedup-of-true-terminal write returned nonzero (should be a no-op)"; FAIL=1; }
rows16b="$(grep -c '"task_sig":"aaaa6666"' "$LEDGER_FILE" 2>/dev/null || echo 0)"
[[ "$rows16b" -eq 2 ]] || { echo "FAIL 16: a 3rd row was appended after sweep's dead already TRUE-terminaled the sig8, got $rows16b rows"; FAIL=1; }

# --- 17 (SD-LEDGER-SWEEP-HARDEN-01 "concurrent refused-append-vs-sweep race", REWRITTEN
#         MEDIUM-2 fixround-tails): round-5 finding (b) -- the old preflight ran OUTSIDE
#         the lock, so a refused/parked append landing in the window between check and
#         write was invisible to the check and then overwritten by write-once dead anyway.
#         The ORIGINAL version of this case staggered the refuser by a bare `sleep 0.05`,
#         which in practice always let the refused write land and finish BEFORE the sweep
#         even reached its own flock call -- that ordering also passes against the OLD,
#         unlocked, sig8-wide preflight, so the case proved nothing about atomicity
#         (review-tails-verdict.md MEDIUM-2). This version forces GENUINE contention: a
#         helper holds the ledger's own lockfile for ~0.3s BEFORE either contender starts,
#         so write-terminal (refused) and sweep (dead) are BOTH already blocked in their
#         own `flock -x 9` the instant the lock is released -- whichever the kernel wakes
#         first wins, and the loser's own locked check-then-append (same flock section, no
#         TOCTOU) must observe the winner's row and skip. Looped so both orderings are
#         exercised across the run, not just whichever one `sleep 0.05` happened to favor.
RACE_LOCK="$LEDGER_FILE.lock"
race_fail=0
for race_i in $(seq 1 12); do
  # review-tails-verdict-2.md HIGH-2: this used to be `c0000%02x` -- 5 chars + 2 hex = 7
  # hex characters total, which fails cmd_sweep's `^[0-9a-f]{8}$` sig8 extraction
  # (ledger:419) and drops the lane before `checked` is even incremented, so the race
  # below tested nothing (sweep was a guaranteed no-op regardless of locking). `c00000`
  # is 6 chars + 2 hex = 8, a real sig8.
  RACE_SIG8="$(printf 'c00000%02x' "$race_i")"
  RACE_ATTEMPT="pid-17${race_i}"
  LANE_LIVENESS_STUB17="$ROOT/lane-liveness-stub17-${race_i}.sh"
  cat > "$LANE_LIVENESS_STUB17" <<EOF
#!/usr/bin/env bash
cat <<JSON
{"lanes":[{"lane":"dispatch-${RACE_SIG8}","verdict":"dead:no_handoff_dir","age_s":9999,"attempt":"${RACE_ATTEMPT}"}]}
JSON
EOF
  chmod +x "$LANE_LIVENESS_STUB17"
  (
    exec 9>"$RACE_LOCK"
    flock -x 9
    sleep 0.3
    flock -u 9
    exec 9>&-
  ) &
  holder_pid=$!
  sleep 0.05  # let the holder actually acquire the lock before launching contenders
  (
    bash "$BIN" write-terminal "$RACE_SIG8" "task-17-refuser" "refused" "all_arms_exhausted_quota" "chain=glm" "$RACE_ATTEMPT" >/dev/null 2>&1
  ) &
  race_pid_a=$!
  (
    LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB17" bash "$BIN" sweep >/dev/null 2>"$ROOT/sweep17-${race_i}.err"
  ) &
  race_pid_b=$!
  wait "$holder_pid" "$race_pid_a" "$race_pid_b" 2>/dev/null
  # HIGH-2 required fix: assert the sweep actually SAW this lane (checked=1) so a future
  # sig8-shape mistake (or any other silent drop before the checked counter) cannot re-
  # inert this case the way the 7-hex RACE_SIG8 did -- without this, rows17==1 is
  # guaranteed by the refused write alone regardless of what the sweep did.
  if ! grep -q 'sweep: checked=1 ' "$ROOT/sweep17-${race_i}.err"; then
    echo "FAIL 17: iteration ${race_i}: sweep did not report checked=1 -- the lane was dropped before reaching the race, this iteration proves nothing -- $(cat "$ROOT/sweep17-${race_i}.err")"
    race_fail=1
  fi
  rows17="$(grep -c "\"task_sig\":\"${RACE_SIG8}\"" "$LEDGER_FILE" 2>/dev/null || echo 0)"
  if [[ "$rows17" -ne 1 ]]; then
    echo "FAIL 17: iteration ${race_i}: expected exactly 1 terminal row for the raced sig8 (write-once-per-attempt held under a real lock race), got $rows17 -- $(grep "\"${RACE_SIG8}\"" "$LEDGER_FILE" 2>/dev/null)"
    race_fail=1
  fi
  row17="$(grep "\"task_sig\":\"${RACE_SIG8}\"" "$LEDGER_FILE" 2>/dev/null)"
  if ! grep -q '"terminal":"refused"' <<<"$row17" && ! grep -q '"terminal":"dead"' <<<"$row17"; then
    echo "FAIL 17: iteration ${race_i}: the one surviving row is neither refused nor dead -- $row17"; race_fail=1
  fi
done
[[ "$race_fail" -eq 0 ]] || FAIL=1

# --- 18 (HIGH-1 regression, review-tails-verdict.md live repro): a LIVE worker pid +
#         artifactless (no handoff dir at all) + ANCIENT started_at + no close-owner
#         record used to get swept into a write-once `dead` even though the worker is
#         still running -- against the REAL leadv2-lane-liveness.sh producer (not a stub),
#         proving the fix threads pid_alive all the way through cmd_sweep's own funnel.
sleep 30 & LIVE_PID_18=$!
REAL_LIVENESS_PROJECT_18="$ROOT/real-liveness-project-18"
mkdir -p "$REAL_LIVENESS_PROJECT_18/docs/leadv2"
REAL_ACTIVE_YAML_18="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18" bash "$STATE_PATH_BIN_15" --no-link active.yaml)"
mkdir -p "$(dirname "$REAL_ACTIVE_YAML_18")"
printf 'sessions:\n  - task_id: founder-task-livepid\n    phase: build\n    pid: %s\n    started_at: "2020-01-01T00:00:00Z"\n    attempt: "pid-18001"\n    log_path: docs/handoff/dispatch-18001111/developer.stream.jsonl\n' "$LIVE_PID_18" > "$REAL_ACTIVE_YAML_18"
# deliberately never create docs/handoff/dispatch-18001111/ -- same artifactless-crash
# shape as case 15, but this time with a session pid that IS actually alive.
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LIVENESS_BIN_15" \
  LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18" LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" \
  PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18" \
  bash "$BIN" sweep 2>"$ROOT/sweep18.err"
if grep -q '"founder_task_id":"founder-task-livepid"' "$LEDGER_FILE"; then
  echo "FAIL 18: an artifactless lane with a LIVE worker pid was swept dead -- HIGH-1 regressed"; FAIL=1; cat "$ROOT/sweep18.err"
fi
kill "$LIVE_PID_18" 2>/dev/null; wait "$LIVE_PID_18" 2>/dev/null

# --- 18b (companion, same shape, DEAD pid): proves the fix is discriminating, not a
#         blanket new grace -- once the pid is confirmed dead, the same artifactless +
#         ancient-started_at lane IS still swept.
DEAD_PID_18B=$LIVE_PID_18  # already reaped above; guaranteed not alive
REAL_LIVENESS_PROJECT_18B="$ROOT/real-liveness-project-18b"
mkdir -p "$REAL_LIVENESS_PROJECT_18B/docs/leadv2"
REAL_ACTIVE_YAML_18B="$(LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18B" bash "$STATE_PATH_BIN_15" --no-link active.yaml)"
mkdir -p "$(dirname "$REAL_ACTIVE_YAML_18B")"
printf 'sessions:\n  - task_id: founder-task-deadpid\n    phase: build\n    pid: %s\n    started_at: "2020-01-01T00:00:00Z"\n    attempt: "pid-18002"\n    log_path: docs/handoff/dispatch-18002222/developer.stream.jsonl\n' "$DEAD_PID_18B" > "$REAL_ACTIVE_YAML_18B"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LIVENESS_BIN_15" \
  LEADV2_PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18B" LEADV2_STATE_ROOT="$REAL_LIVENESS_STATE" \
  PROJECT_ROOT="$REAL_LIVENESS_PROJECT_18B" \
  bash "$BIN" sweep 2>"$ROOT/sweep18b.err"
grep -q '"founder_task_id":"founder-task-deadpid"' "$LEDGER_FILE" \
  || { echo "FAIL 18b: an artifactless lane with a confirmed-DEAD pid was not swept"; FAIL=1; cat "$ROOT/sweep18b.err"; }

# --- 19 (MEDIUM-4, review-tails-verdict-2.md): a WEDGED (SIGSTOP'd) worker with a live pid
#         must still be swept -- dead:wedged_STAT=<stat> already consulted pid_alive itself
#         and concluded dead deliberately, it is not one of the three artifactless-dead
#         verdicts (no_handoff_dir/no_log_artifact/log_stat_failed) that never looked at
#         pid_alive at all, so the HIGH-1 skip must NOT apply to it. Before the MEDIUM-4
#         fix this lane would stay unswept forever (same shape as case 18's assertion, but
#         asserting the OPPOSITE outcome).
LANE_LIVENESS_STUB19="$ROOT/lane-liveness-stub19.sh"
cat > "$LANE_LIVENESS_STUB19" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"lanes":[{"lane":"dispatch-19001111","verdict":"dead:wedged_STAT=TN","age_s":10832,"attempt":"pid-19001","pid_alive":true}]}
JSON
EOF
chmod +x "$LANE_LIVENESS_STUB19"
LEADV2_DISPATCH_LANE_LIVENESS_BIN="$LANE_LIVENESS_STUB19" bash "$BIN" sweep 2>"$ROOT/sweep19.err"
grep -q '"task_sig":"19001111".*"terminal":"dead"' "$LEDGER_FILE" \
  || { echo "FAIL 19: a wedged (SIGSTOP'd) lane with a live pid was NOT swept -- dead:wedged_STAT already consulted pid_alive and concluded dead deliberately, MEDIUM-4 regressed"; FAIL=1; cat "$ROOT/sweep19.err"; }

if [[ $FAIL -eq 0 ]]; then
  echo 'PASS: write-once terminal ledger (write/dedup/exists/invalid/sanitize/sweep/close-owner/retryable-refused-parked/sweep-never-poisons-refused/real-liveness-vanished-stream-sig8/attempt-scoped-sweep/wrong-attempt/concurrent-lock-race/live-pid-not-swept/dead-pid-swept/wedged-live-pid-swept)'
  exit 0
fi
exit 1
