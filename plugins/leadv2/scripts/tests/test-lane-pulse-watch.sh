#!/usr/bin/env bash
# tests/test-lane-pulse-watch.sh — MON-PULSE-01 part 1: dispatcher-owned lane watch.
#
# Locks leadv2-lane-pulse-watch.sh (armed by leadv2-dispatch-code.sh at
# worker_spawned):
#
#   W1  REPLAY-SAFETY (today's incident): a terminal line already in the
#       journal BEFORE the watcher starts is still reported — the watcher
#       reads from line 1 (tail -n +1), never tail -n 0.
#   W2  beats vs terminals (fix-round C1/H1): an own-sig review_gate line
#       PULSES but the watch keeps running; a dispatch_terminal_dedup row
#       neither pulses nor exits; the later dispatch_terminal pulses and only
#       THEN does the watcher exit. A FOREIGN sig's line never pulses.
#   W3  pidfile guard: a second arm attempt for the same sig while a live
#       watcher holds the pidfile is an immediate no-op (no pulse written).
#   W4  NEGATIVE CONTROL (declared here, RUN RED below): reverting the
#       replay-safe offset init to tail -n 0 semantics must FAIL W1 — proving
#       W1 locks the actual mechanism, not an incidental pass.
#   W5  re-arm dedup (fix-round H2): after a watcher exited at the terminal,
#       a second arm of the same sig replays the journal WITHOUT duplicating
#       any pulse (per-sig seen ledger survives watcher exit).
#   W6  NEGATIVE CONTROL (RUN RED): putting review_gate back into the exit
#       set (the round-1 defect) must make the watcher die at the review_gate
#       beat and MISS the later dispatch_terminal — proving W2 locks the
#       actual mechanism, not an incidental pass.
#
# Hermetic: scratch repo tree, scratch --state-dir, no network, no real lanes,
# no real control-plane state. Run: bash scripts/tests/test-lane-pulse-watch.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
WATCH="$SCRIPT_DIR/leadv2-lane-pulse-watch.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-lane-pulse-watch-XXXXXX)"
cleanup() {
  [[ -n "${WATCH_PID:-}" ]] && kill "${WATCH_PID}" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

SIG="abcd0001"
FSIG="deadbeef"   # foreign sig — its lines must never pulse for ours
STATE="$TMP/state"

new_lane() {  # <sig> -> fresh scratch repo with an empty journal; sets REPO/J/PULSE
  REPO="$TMP/repo-$1"
  LANE_DIR="$REPO/docs/leadv2/tasks/dispatch-$1"
  mkdir -p "$LANE_DIR"
  J="$LANE_DIR/journal.md"
  PULSE="$LANE_DIR/pulse.md"
  : > "$J"
}

append_lines() {  # <journal> [lines...] — atomic replace (tmp + mv)
  local j="$1"; shift
  { cat "$j" 2>/dev/null; for l in "$@"; do printf '%s\n' "$l"; done; } > "${j}.tmp"
  mv "${j}.tmp" "$j"
}

wait_for_exit() {  # <pid> <max_s> -> rc0 if the process exited in time
  local pid="$1" max="$2" i
  for ((i = 0; i < max * 10; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -0 "$pid" 2>/dev/null && return 1
  return 0
}

# ── W1: replay-safety — terminal line exists BEFORE the watcher starts ──────
new_lane "$SIG"
append_lines "$J" \
  "- 2026-08-28T10:00:00Z [decision] worker_spawned by=router model=glm task=${SIG} handle=h1" \
  "- 2026-08-28T10:00:25Z [decision] dispatch_terminal task=${SIG} state=landed"
bash "$WATCH" --sig "$SIG" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 10 >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 && -f "$PULSE" ]] && grep -q "dispatch_terminal" "$PULSE" && [[ "$(wc -l < "$PULSE" | tr -d ' ')" -eq 1 ]]; then
  ok "W1 replay-safety: pre-existing terminal line still pulsed (exactly once), rc=0"
else
  bad "W1 replay-safety: rc=$rc pulse=$(cat "$PULSE" 2>/dev/null | tr '\n' ';')"
fi

# ── W2: beats pulse but never end the watch; only a true terminal exits ──────
SIG2="cafe0213"
new_lane "$SIG2"
append_lines "$J" \
  "- 2026-08-28T11:00:00Z [decision] worker_spawned by=router model=freepool task=${SIG2} handle=h2"
bash "$WATCH" --sig "$SIG2" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 20 >/dev/null 2>&1 &
WATCH_PID=$!
sleep 1.5
append_lines "$J" \
  "- 2026-08-28T11:01:00Z [decision] review_gate task=${FSIG} status=pass diff=aa11" \
  "- 2026-08-28T11:01:05Z [decision] review_gate task=${SIG2} status=ran round=1"
sleep 1.5
if kill -0 "$WATCH_PID" 2>/dev/null && [[ -f "$PULSE" ]] \
   && grep -q "review_gate task=${SIG2}" "$PULSE" \
   && ! grep -q "task=${FSIG}" "$PULSE" \
   && [[ "$(wc -l < "$PULSE" | tr -d ' ')" -eq 1 ]]; then
  ok "W2 beat: own-sig review_gate pulsed, foreign sig excluded, watch still running"
else
  bad "W2 beat: alive=$(kill -0 "$WATCH_PID" 2>/dev/null && echo yes || echo no) pulse=$(cat "$PULSE" 2>/dev/null | tr '\n' ';')"
fi
# H1: a dispatch_terminal_dedup row is duplicate-suppression noise — no pulse, no exit
append_lines "$J" \
  "- 2026-08-28T11:02:00Z [decision] dispatch_terminal_dedup task=${SIG2} attempted=dead reason=terminal_already_recorded"
sleep 1.5
if kill -0 "$WATCH_PID" 2>/dev/null && [[ "$(cat "$PULSE" 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]]; then
  ok "W2 dedup noise: dispatch_terminal_dedup neither pulsed nor exited (H1)"
else
  bad "W2 dedup noise: watcher exited at, or pulsed, the dedup row (H1)"
fi
# C1: the true terminal ends the watch — after the beat, never before
append_lines "$J" \
  "- 2026-08-28T11:03:00Z [decision] dispatch_terminal task=${SIG2} state=landed"
if wait_for_exit "$WATCH_PID" 15; then
  if grep -q "dispatch_terminal task=${SIG2}" "$PULSE" \
     && ! grep -q "dispatch_terminal_dedup" "$PULSE" \
     && [[ "$(wc -l < "$PULSE" | tr -d ' ')" -eq 2 ]]; then
    ok "W2 terminal: dispatch_terminal pulsed after the beat, exit only there (C1)"
  else
    bad "W2 terminal: pulse=$(cat "$PULSE" 2>/dev/null | tr '\n' ';')"
  fi
else
  bad "W2 terminal: watcher did not exit at dispatch_terminal"
  kill "$WATCH_PID" 2>/dev/null || true
fi
WATCH_PID=""

# ── W5: re-arm never duplicates (fix-round H2) ───────────────────────────────
# The ledger recorded the pulsed offset at exit; a fresh watcher for the same
# sig replays the journal without re-pulsing review_gate or dispatch_terminal.
bash "$WATCH" --sig "$SIG2" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 2 >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 && "$(wc -l < "$PULSE" | tr -d ' ')" -eq 2 ]]; then
  ok "W5 re-arm dedup: replayed journal produced no duplicate pulses (ledger held)"
else
  bad "W5 re-arm dedup: rc=$rc pulse_lines=$(wc -l < "$PULSE" 2>/dev/null | tr -d ' ')"
fi

# ── W3: pidfile guard — second arm attempt for the same sig is a no-op ──────
SIG3="beef4242"
new_lane "$SIG3"
append_lines "$J" \
  "- 2026-08-28T12:00:00Z [decision] worker_spawned by=router model=codex task=${SIG3} handle=h3"
# a live stand-in process holds the pidfile, exactly like a real armed watcher
HolderPid=""
sleep 300 & HolderPid=$!
printf '%s\n' "$HolderPid" > "$STATE/lane-pulse-watch/${SIG3}.pid"
before="$(cat "$PULSE" 2>/dev/null | wc -l | tr -d ' ')"
timeout_bin="$(command -v timeout || true)"
if [[ -n "$timeout_bin" ]]; then
  "$timeout_bin" 5 bash "$WATCH" --sig "$SIG3" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 10 >/dev/null 2>&1
  rc=$?
else
  bash "$WATCH" --sig "$SIG3" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 2 >/dev/null 2>&1
  rc=$?
fi
after="$(cat "$PULSE" 2>/dev/null | wc -l | tr -d ' ')"
if [[ $rc -eq 0 && "$before" == "$after" ]]; then
  ok "W3 pidfile: second arm attempt no-op (rc=0, no pulse written)"
else
  bad "W3 pidfile: rc=$rc before=$before after=$after"
fi
kill "$HolderPid" 2>/dev/null || true

# ── W4: NEGATIVE CONTROL (RUN RED) — revert replay-safety to tail -n 0 ───────
# Patch the offset init (`printf '0'` -> pre-existing line count) in a scratch
# copy, rerun the exact W1 scenario, and REQUIRE the pulse to be missing. If
# the patched copy still passes, W1 is not locking the mechanism.
BAD_WATCH="$TMP/watch-tailn0.sh"
python3 - "$WATCH" "$BAD_WATCH" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding='utf-8') as fh:
    text = fh.read()
needle = "  printf '0'"
repl = "  printf '%s' \"$n\""
if needle not in text:
    print('NEGATIVE-CONTROL-PATCH-FAILED: needle not found', file=sys.stderr)
    sys.exit(1)
with open(dst, 'w', encoding='utf-8') as fh:
    fh.write(text.replace(needle, repl, 1))
PY
patch_rc=$?
SIG4="d00d5150"
new_lane "$SIG4"
append_lines "$J" \
  "- 2026-08-28T13:00:00Z [decision] worker_spawned by=router model=glm task=${SIG4} handle=h4" \
  "- 2026-08-28T13:00:25Z [decision] dispatch_terminal task=${SIG4} state=landed"
bash "$BAD_WATCH" --sig "$SIG4" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 5 >/dev/null 2>&1
if [[ $patch_rc -eq 0 ]] && ! grep -q "dispatch_terminal" "$PULSE" 2>/dev/null; then
  ok "W4 negative control RED: tail -n 0 revert misses the pre-existing terminal (as it must)"
else
  bad "W4 negative control: patched copy unexpectedly passed (patch_rc=$patch_rc) — W1 locks nothing"
fi

# ── W6: NEGATIVE CONTROL (RUN RED) — review_gate back in the exit set (C1) ──
# Patch a scratch copy so review_gate terminates the watch again (the round-1
# defect), run the mid-flight scenario, and REQUIRE the later dispatch_terminal
# pulse to be MISSING — the reverted watcher died at the review_gate beat. If
# the patched copy still delivers the terminal pulse, W2 locks nothing.
BAD_WATCH_RG="$TMP/watch-rg-terminal.sh"
python3 - "$WATCH" "$BAD_WATCH_RG" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding='utf-8') as fh:
    text = fh.read()
needle = "EXIT_PAT='dispatch_terminal([^_]|$)|dispatch_refused([^_]|$)|worker_died([^_]|$)'"
repl = "EXIT_PAT='review_gate|dispatch_terminal([^_]|$)|dispatch_refused([^_]|$)|worker_died([^_]|$)'"
if needle not in text:
    print('NEGATIVE-CONTROL-PATCH-FAILED: needle not found', file=sys.stderr)
    sys.exit(1)
with open(dst, 'w', encoding='utf-8') as fh:
    fh.write(text.replace(needle, repl, 1))
PY
patch_rc=$?
SIG5="f00ba4a4"
new_lane "$SIG5"
append_lines "$J" \
  "- 2026-08-28T14:00:00Z [decision] worker_spawned by=router model=glm task=${SIG5} handle=h5"
# the scratch copy lives outside scripts/, so point its pulse seam at the
# REAL writer (its own SCRIPT_DIR-relative default would not exist in $TMP)
LEADV2_LANE_PULSE_BIN="${SCRIPT_DIR}/leadv2-pulse.sh" \
bash "$BAD_WATCH_RG" --sig "$SIG5" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 10 >/dev/null 2>&1 &
WATCH_PID=$!
sleep 1.5
append_lines "$J" \
  "- 2026-08-28T14:01:00Z [decision] review_gate task=${SIG5} status=ran round=0"
if wait_for_exit "$WATCH_PID" 5; then
  append_lines "$J" \
    "- 2026-08-28T14:02:00Z [decision] dispatch_terminal task=${SIG5} state=landed"
  sleep 1.5   # the reverted watcher is dead — nothing can deliver this pulse
  if [[ $patch_rc -eq 0 ]] && grep -q "review_gate task=${SIG5}" "$PULSE" 2>/dev/null \
     && ! grep -q "dispatch_terminal task=${SIG5}" "$PULSE" 2>/dev/null; then
    ok "W6 negative control RED: review_gate-as-terminal revert dies before dispatch_terminal (as it must)"
  else
    bad "W6 negative control: patched copy still delivered the terminal pulse (patch_rc=$patch_rc) — W2 locks nothing"
  fi
else
  bad "W6 negative control: patched watcher did not exit at review_gate (patch_rc=$patch_rc)"
  kill "$WATCH_PID" 2>/dev/null || true
fi
WATCH_PID=""

printf 'test-lane-pulse-watch: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
