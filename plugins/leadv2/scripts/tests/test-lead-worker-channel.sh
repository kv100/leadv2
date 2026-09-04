#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: ask-lead leadv2-ask leadv2-broad-status leadv2-dispatch-code leadv2-inbox leadv2-notify-lead
# tests/test-lead-worker-channel.sh — LEAD-WORKER-CHANNEL-01.
#
# Proves the worker->lead channel's guaranteed path (leadv2-notify-lead.sh
# appends a durable row via leadv2-inbox.sh, unconditionally, before it
# ever prints the SendMessage-relay line a worker MODEL might act on) and
# the lead's drain-without-being-told path (leadv2-inbox.sh drain, wired
# into leadv2-broad-status.sh's beat).
#
# Hermetic: every case sets LEADV2_LEAD_INBOX_DIR to a throwaway dir --
# never a real lane, never the real lane registry, never a real inbox.
# The broad-status case additionally sets LEADV2_PROJECT_ROOT/STATE_ROOT to
# throwaway dirs (lv2_assert_scratch_repo proves it before any write).
#
# Cases (LEAD-WORKER-CHANNEL-01 Acceptance):
#   1. no lead reachable -> row still written, exit 0
#   2. event from repo A + event from repo B for the SAME lead -> both
#      land in one inbox, in order
#   3. drain returns each row exactly once across two consecutive calls
#   4. two concurrent drain calls -> every row delivered exactly once,
#      none lost
#   5. an undrained row -> appears in the beat's rendered status
#      (leadv2-broad-status.sh)
#   6. `finished` and `died` are distinct events for the same lane --
#      an INFRASTRUCTURE capability proof (notify-lead/inbox can carry two
#      distinct event rows for one lane), NOT a wired call site: the real
#      terminal-write funnel (dispatch_ledger_write_terminal) lives
#      entirely in leadv2-dispatch-ledger.sh, which is outside this task's
#      LANE_WRITES scope (see docs/handoff/dispatch-a49eba80/developer.full.md
#      census correction) -- nothing in-scope calls it today.
#   7. the notifier failing (unwritable inbox) -> the caller's exit code
#      is unchanged
#
# Run: bash plugins/leadv2/scripts/tests/test-lead-worker-channel.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

NOTIFY_SH="${SCRIPT_DIR}/leadv2-notify-lead.sh"
INBOX_SH="${SCRIPT_DIR}/leadv2-inbox.sh"
BROAD_STATUS_SH="${SCRIPT_DIR}/leadv2-broad-status.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir lead-worker-channel)"
trap 'rm -rf "$TMP"' EXIT

# ── Case 1: no lead reachable => row still written, exit 0 ─────────────────
INBOX1="$TMP/inbox1"
OUT="$(LEADV2_LEAD_INBOX_DIR="$INBOX1" LEADV2_ACTIVE_YAML_PATH="$TMP/nonexistent-active.yaml" \
  PROJECT_ROOT="$TMP/repoUnknown" bash "$NOTIFY_SH" task-unreachable died "no pid, no commit" 2>"$TMP/c1.err")"
RC=$?
if [[ "$RC" -eq 0 ]]; then pass "C1a: notify-lead exits 0 when lead is unreachable"; else fail "C1a: notify-lead exit=$RC (expected 0)"; fi
ROW="$(LEADV2_LEAD_INBOX_DIR="$INBOX1" bash "$INBOX_SH" drain --lead unknown)"
if printf '%s' "$ROW" | grep -q 'event=died'; then
  pass "C1b: durable row still written for an unreachable lead"
else
  fail "C1b: no durable row found for unreachable lead. drain output: [$ROW]"
fi
if printf '%s' "$OUT" | grep -q '^\[leadv2-notify\] lead=unknown'; then
  pass "C1c: printed SendMessage-relay line names lead=unknown"
else
  fail "C1c: relay line missing/wrong: [$OUT]"
fi

# ── Case 2: repo A + repo B, same lead -> one inbox, in order ──────────────
INBOX2="$TMP/inbox2"
LEADV2_LEAD_INBOX_DIR="$INBOX2" LEADV2_LEAD_SESSION_ID=lead-shared PROJECT_ROOT="$TMP/repoA" \
  bash "$NOTIFY_SH" task-a first-event "from repo A" >/dev/null 2>&1
LEADV2_LEAD_INBOX_DIR="$INBOX2" LEADV2_LEAD_SESSION_ID=lead-shared PROJECT_ROOT="$TMP/repoB" \
  bash "$NOTIFY_SH" task-b second-event "from repo B" >/dev/null 2>&1
DRAINED="$(LEADV2_LEAD_INBOX_DIR="$INBOX2" bash "$INBOX_SH" drain --lead lead-shared)"
N_LINES="$(printf '%s\n' "$DRAINED" | grep -c .)"
if [[ "$N_LINES" -eq 2 ]]; then pass "C2a: both repos' events land in the SAME inbox for the shared lead"; else fail "C2a: expected 2 rows, got $N_LINES: [$DRAINED]"; fi
FIRST_LINE="$(printf '%s\n' "$DRAINED" | sed -n 1p)"
SECOND_LINE="$(printf '%s\n' "$DRAINED" | sed -n 2p)"
if printf '%s' "$FIRST_LINE" | grep -q 'repoA' && printf '%s' "$SECOND_LINE" | grep -q 'repoB'; then
  pass "C2b: rows preserve arrival order (repo A before repo B)"
else
  fail "C2b: order wrong. line1=[$FIRST_LINE] line2=[$SECOND_LINE]"
fi

# ── Case 3: drain returns each row exactly once across two calls ───────────
SECOND_DRAIN="$(LEADV2_LEAD_INBOX_DIR="$INBOX2" bash "$INBOX_SH" drain --lead lead-shared)"
if [[ -z "$SECOND_DRAIN" ]]; then
  pass "C3: a second drain call returns nothing -- each row delivered exactly once"
else
  fail "C3: second drain re-delivered rows: [$SECOND_DRAIN]"
fi

# ── Case 4: two concurrent drain calls -> every row delivered exactly once,
#    none lost, none duplicated ────────────────────────────────────────────
INBOX4="$TMP/inbox4"
for i in $(seq 1 20); do
  LEADV2_LEAD_INBOX_DIR="$INBOX4" LEADV2_LEAD_SESSION_ID=lead-concurrent PROJECT_ROOT="$TMP/repoC" \
    bash "$NOTIFY_SH" "task-$i" tick "row $i" >/dev/null 2>&1
done
OUT_A="$TMP/drainA.out"; OUT_B="$TMP/drainB.out"
LEADV2_LEAD_INBOX_DIR="$INBOX4" bash "$INBOX_SH" drain --lead lead-concurrent >"$OUT_A" 2>/dev/null &
PID_A=$!
LEADV2_LEAD_INBOX_DIR="$INBOX4" bash "$INBOX_SH" drain --lead lead-concurrent >"$OUT_B" 2>/dev/null &
PID_B=$!
wait "$PID_A" "$PID_B"
TOTAL_ROWS="$(cat "$OUT_A" "$OUT_B" | grep -c .)"
UNIQUE_ROWS="$(cat "$OUT_A" "$OUT_B" | grep -oE 'row [0-9]+' | sort -u | wc -l | tr -d ' ')"
if [[ "$TOTAL_ROWS" -eq 20 && "$UNIQUE_ROWS" -eq 20 ]]; then
  pass "C4: two concurrent drains delivered all 20 rows exactly once, none lost/duplicated"
else
  fail "C4: total=$TOTAL_ROWS unique=$UNIQUE_ROWS (expected 20/20). A=$(cat "$OUT_A") B=$(cat "$OUT_B")"
fi

# ── Case 5: an undrained row appears in the beat's rendered status ────────
REPO5="$TMP/proj5"; STATE5="$TMP/state5"; STUBS5="$TMP/stubs5"; INBOX5="$TMP/inbox5"
mkdir -p "$REPO5" "$STATE5" "$STUBS5" "$INBOX5"
git -C "$REPO5" init -q
lv2_assert_scratch_repo "$REPO5"
cat >"$STUBS5/collector.sh" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac; done
[[ -z "$out" ]] && exit 1
printf '{"sections": {}}' >"$out"
EOF
cat >"$STUBS5/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"fixture tail"}'
EOF
chmod +x "$STUBS5/collector.sh" "$STUBS5/claude.sh"

LEADV2_LEAD_INBOX_DIR="$INBOX5" LEADV2_LEAD_SESSION_ID=lead-beat PROJECT_ROOT="$REPO5" \
  bash "$NOTIFY_SH" task-beat blocked "gate refused: review round cap" >/dev/null 2>&1

env LEADV2_PROJECT_ROOT="$REPO5" LEADV2_STATE_ROOT="$STATE5" \
  LEADV2_STATUS_COLLECTOR_BIN="$STUBS5/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS5/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-31T10:00:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="0" \
  LEADV2_LEAD_SESSION_ID=lead-beat \
  LEADV2_LEAD_INBOX_DIR="$INBOX5" \
  bash "$BROAD_STATUS_SH" >/dev/null 2>"$TMP/c5.err"
FOUNDER_STATUS5="$REPO5/docs/leadv2/founder-status.md"
if [[ -f "$FOUNDER_STATUS5" ]] && grep -q 'gate refused: review round cap' "$FOUNDER_STATUS5"; then
  pass "C5: an undrained row appears in the beat's rendered founder-status.md"
else
  fail "C5: undrained row missing from beat output. file: $(cat "$FOUNDER_STATUS5" 2>&1) stderr: $(cat "$TMP/c5.err" 2>&1)"
fi
# Second beat: the row was consumed by the first drain, so it must NOT repeat.
env LEADV2_PROJECT_ROOT="$REPO5" LEADV2_STATE_ROOT="$STATE5" \
  LEADV2_STATUS_COLLECTOR_BIN="$STUBS5/collector.sh" \
  LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS5/claude.sh" \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-31T10:30:00Z" \
  LEADV2_BROAD_STATUS_DISPATCHED="0" \
  LEADV2_LEAD_SESSION_ID=lead-beat \
  LEADV2_LEAD_INBOX_DIR="$INBOX5" \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1
if grep -q 'gate refused: review round cap' "$FOUNDER_STATUS5"; then
  fail "C5b: consumed row repeated on the NEXT beat"
else
  pass "C5b: consumed row does not repeat on the next beat"
fi

# ── Case 6: `finished` and `died` are distinct events for the same lane
#    (infrastructure capability -- see header note: no in-scope call site
#    wires the real terminal determination today) ──────────────────────────
INBOX6="$TMP/inbox6"
LEADV2_LEAD_INBOX_DIR="$INBOX6" LEADV2_LEAD_SESSION_ID=lead-term PROJECT_ROOT="$TMP/repoD" \
  bash "$NOTIFY_SH" task-lane-x finished "commit landed" >/dev/null 2>&1
LEADV2_LEAD_INBOX_DIR="$INBOX6" LEADV2_LEAD_SESSION_ID=lead-term PROJECT_ROOT="$TMP/repoD" \
  bash "$NOTIFY_SH" task-lane-x died "no pid, no commit" >/dev/null 2>&1
DRAINED6="$(LEADV2_LEAD_INBOX_DIR="$INBOX6" bash "$INBOX_SH" drain --lead lead-term)"
N_FINISHED="$(printf '%s\n' "$DRAINED6" | grep -c 'event=finished')"
N_DIED="$(printf '%s\n' "$DRAINED6" | grep -c 'event=died')"
if [[ "$N_FINISHED" -eq 1 && "$N_DIED" -eq 1 ]]; then
  pass "C6: finished and died recorded as two distinct rows for the same lane"
else
  fail "C6: expected 1 finished + 1 died, got finished=$N_FINISHED died=$N_DIED: [$DRAINED6]"
fi

# ── Case 7: notifier failing (unwritable inbox) => caller's exit code
#    is unchanged ──────────────────────────────────────────────────────────
INBOX7_PARENT="$TMP/ro7"
mkdir -p "$INBOX7_PARENT"
chmod 000 "$INBOX7_PARENT"
_caller_exit_code_probe() {
  true  # caller's own last command before notifying -- sets $? = 0
  LEADV2_LEAD_INBOX_DIR="$INBOX7_PARENT/inbox" LEADV2_LEAD_SESSION_ID=lead-ro PROJECT_ROOT="$TMP/repoE" \
    bash "$NOTIFY_SH" task-ro blocked "x" >/dev/null 2>&1
  return $?
}
_caller_exit_code_probe
NOTIFY_RC=$?
chmod 755 "$INBOX7_PARENT"
if [[ "$NOTIFY_RC" -eq 0 ]]; then
  pass "C7: notifier exits 0 even when the inbox directory is unwritable"
else
  fail "C7: notifier propagated a non-zero exit ($NOTIFY_RC) from an unwritable inbox"
fi
# Direct proof the underlying append call DID fail (so C7 isn't vacuous):
mkdir -p "$TMP/ro7b"
chmod 000 "$TMP/ro7b"
LEADV2_LEAD_INBOX_DIR="$TMP/ro7b/inbox" bash "$INBOX_SH" append leadX repoX taskX laneX blockedX textX >/dev/null 2>/dev/null
APPEND_RC=$?
chmod 755 "$TMP/ro7b"
if [[ "$APPEND_RC" -ne 0 ]]; then
  pass "C7b: the underlying append genuinely failed on an unwritable dir (not a vacuous pass)"
else
  fail "C7b: append unexpectedly succeeded against an unwritable dir -- C7 would be vacuous"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
