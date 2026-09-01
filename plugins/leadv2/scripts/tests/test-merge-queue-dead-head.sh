#!/usr/bin/env bash
# test-merge-queue-dead-head.sh — MERGE-QUEUE-DEAD-HEAD-01
#
# Regression coverage for: a dead ENQUEUED head (a task that enqueued, then
# its owning process died before ever reaching `acquired`) used to be
# invisible to try_acquire's reclaim logic, which only examined a dead
# HOLDER. That left every later acquire() printing WAIT forever.
#
# Hermetic: LEADV2_DIR points at a fresh temp dir per run (never touches the
# real control-plane merge-queue.jsonl), LEADV2_MERGE_STALE_SEC is set short
# so the "stale" branch is reachable without a real 10-minute wait.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MQ="${SCRIPT_DIR}/../leadv2-merge-queue.sh"

PASS=0
FAIL=0

_ok() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

# --- a genuinely dead pid: spawn a subshell, capture its pid, wait it out ---
_make_dead_pid() {
  ( exit 0 ) &
  local p=$!
  wait "$p" 2>/dev/null
  echo "$p"
}

# ---------------------------------------------------------------------------
# Case (a): dead + stale enqueued head -> next try_acquire by another task
#           reclaims it (ACQUIRED/RECLAIMED) and the ledger records a
#           dead-enqueued reclaimed event.
# ---------------------------------------------------------------------------
test_dead_stale_head_reclaimed() {
  local tmp
  tmp="$(mktemp -d)"
  export LEADV2_DIR="$tmp"
  export LEADV2_MERGE_STALE_SEC=1
  export LEADV2_MERGE_TIMEOUT_SEC=5
  export LEADV2_MERGE_POLL_SEC=0.2

  local dead_pid
  dead_pid="$(_make_dead_pid)"

  # Manually append an `enqueued` event for a dead task with an old ts
  # (older than the 1s stale threshold), bypassing the CLI so we control
  # both the pid and the timestamp precisely.
  local qfile="${tmp}/merge-queue.jsonl"
  local old_ts
  old_ts="$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time()-30)))')"
  printf '{"ts":"%s","type":"enqueued","task_id":"dead-task","branch":"x","pid":%s}\n' \
    "$old_ts" "$dead_pid" >> "$qfile"

  # Another task tries to acquire.
  LEADV2_MERGE_OWNER_PID=$$ "$MQ" enqueue live-task branch-b > /dev/null
  local result
  result="$(LEADV2_MERGE_OWNER_PID=$$ "$MQ" acquire live-task &
    local ap=$!
    # acquire() polls; give it a moment then check it returned (exit 0)
    wait "$ap"
    echo "rc=$?")"

  if grep -q '"reason": *"dead-enqueued"' "$qfile" 2>/dev/null \
    || grep -q '"reason":"dead-enqueued"' "$qfile" 2>/dev/null; then
    _ok "case (a): ledger has dead-enqueued reclaimed event"
  else
    _fail "case (a): ledger MISSING dead-enqueued reclaimed event ($(cat "$qfile" 2>/dev/null))"
  fi

  if echo "$result" | grep -q 'rc=0'; then
    _ok "case (a): live-task acquired after dead head reclaimed"
  else
    _fail "case (a): live-task did NOT acquire ($result)"
  fi

  LEADV2_MERGE_OWNER_PID=$$ "$MQ" release live-task > /dev/null 2>&1
  rm -rf "$tmp"
  unset LEADV2_DIR LEADV2_MERGE_STALE_SEC LEADV2_MERGE_TIMEOUT_SEC LEADV2_MERGE_POLL_SEC
}

# ---------------------------------------------------------------------------
# Case (b): live enqueued head -> WAIT (no reclaim).
# ---------------------------------------------------------------------------
test_live_head_waits() {
  local tmp
  tmp="$(mktemp -d)"
  export LEADV2_DIR="$tmp"
  export LEADV2_MERGE_STALE_SEC=1

  # A genuinely live pid, kept alive for the duration of the check.
  sleep 30 &
  local live_pid=$!

  local qfile="${tmp}/merge-queue.jsonl"
  local old_ts
  old_ts="$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time()-30)))')"
  printf '{"ts":"%s","type":"enqueued","task_id":"live-head-task","branch":"x","pid":%s}\n' \
    "$old_ts" "$live_pid" >> "$qfile"

  local result
  result="$(LEADV2_MERGE_OWNER_PID=$$ "$MQ" enqueue waiting-task branch-c > /dev/null; \
    "${SCRIPT_DIR}/../leadv2-merge-queue.sh" status)"

  kill "$live_pid" 2>/dev/null
  wait "$live_pid" 2>/dev/null

  if echo "$result" | grep -q 'DEAD-ENQUEUED'; then
    _fail "case (b): live head wrongly marked DEAD-ENQUEUED ($result)"
  else
    _ok "case (b): live head NOT reclaimed, status clean"
  fi

  if grep -q 'dead-enqueued' "$qfile" 2>/dev/null; then
    _fail "case (b): ledger unexpectedly recorded a dead-enqueued reclaim"
  else
    _ok "case (b): no dead-enqueued reclaim in ledger"
  fi

  rm -rf "$tmp"
  unset LEADV2_DIR LEADV2_MERGE_STALE_SEC
}

# ---------------------------------------------------------------------------
# Case (c): fresh dead head (ts under the stale threshold) -> WAIT, no
#           reclaim yet — proves the age check, not just the pid check,
#           gates the reclaim.
# ---------------------------------------------------------------------------
test_fresh_dead_head_no_reclaim_yet() {
  local tmp
  tmp="$(mktemp -d)"
  export LEADV2_DIR="$tmp"
  export LEADV2_MERGE_STALE_SEC=600

  local dead_pid
  dead_pid="$(_make_dead_pid)"

  local qfile="${tmp}/merge-queue.jsonl"
  local fresh_ts
  fresh_ts="$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))')"
  printf '{"ts":"%s","type":"enqueued","task_id":"fresh-dead-task","branch":"x","pid":%s}\n' \
    "$fresh_ts" "$dead_pid" >> "$qfile"

  LEADV2_MERGE_OWNER_PID=$$ "$MQ" enqueue waiter branch-d > /dev/null
  local status_out
  status_out="$("$MQ" status)"

  if echo "$status_out" | grep -q 'DEAD-ENQUEUED'; then
    _fail "case (c): fresh dead head reclaimed too early ($status_out)"
  else
    _ok "case (c): fresh dead head NOT yet reclaimed (under stale threshold)"
  fi

  if grep -q 'dead-enqueued' "$qfile" 2>/dev/null; then
    _fail "case (c): ledger unexpectedly recorded a dead-enqueued reclaim before threshold"
  else
    _ok "case (c): no premature reclaim in ledger"
  fi

  rm -rf "$tmp"
  unset LEADV2_DIR LEADV2_MERGE_STALE_SEC
}

test_dead_stale_head_reclaimed
test_live_head_waits
test_fresh_dead_head_no_reclaim_yet

printf -- '--- %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
