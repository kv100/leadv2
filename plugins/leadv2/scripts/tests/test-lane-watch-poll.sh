#!/usr/bin/env bash
# tests/test-lane-watch-poll.sh — LANE-OBSERVABILITY-02 change 4.
#
# Lane journals are written via atomic replace (tmp + mv), so `tail -F` follows
# the OLD inode and silently misses events — the exact lie-by-silence this
# watcher exists to fix. This suite locks leadv2-lane-watch.sh:
#
#   W1  a journal rewritten via `mv` still yields the NEW dispatch_terminal
#       line, EXACTLY ONCE (line-count offsets, not inode following).
#   W2  non-matching lines are never printed; dispatch_terminal_dedup rows
#       (already-delivered duplicates) never fire the emit.
#   W3  rotation (fewer lines than the stored offset) resets and re-reads
#       instead of reading past EOF forever.
#   W4  heartbeat fires on the injectable clock without real sleeping:
#       hb <lane> stream_age=<s>s phase=<p>, one line per watched lane.
#   W5  exit 0 once EVERY watched lane has emitted dispatch_terminal task=
#       (loop mode, not --once).
#   W6  a repo-root argument expands to every
#       <root>/docs/leadv2/tasks/dispatch-*/journal.md.
#
# Hermetic: scratch journal trees, scratch --state-dir, no network, no real
# lanes. Run: bash scripts/tests/test-lane-watch-poll.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
WATCH="$SCRIPT_DIR/leadv2-lane-watch.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-lane-watch-XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

REPO="$TMP/repo"
LANE_DIR="$REPO/docs/leadv2/tasks/dispatch-abcd0001"
mkdir -p "$LANE_DIR"
J="$LANE_DIR/journal.md"

# handoff sibling so stream_age has something to stat
HDIR="$REPO/docs/handoff/dispatch-abcd0001"
mkdir -p "$HDIR"
printf 'x\n' > "$HDIR/developer.stream.jsonl"

# append via ATOMIC REPLACE (tmp + mv) — the write shape that kills tail -F
append_lines() {  # <journal> [lines...]
  local j="$1"; shift
  { cat "$j" 2>/dev/null; for l in "$@"; do printf '%s\n' "$l"; done; } > "${j}.tmp"
  mv "${j}.tmp" "$j"
}

STATE="$TMP/state"
run_once() { bash "$WATCH" --once --state-dir "$STATE" "$@"; }

# ── W1/W2: exactly-once across an atomic replace ────────────────────────────
append_lines "$J" \
  "10:00 decision lane spawned phase=build" \
  "10:01 note some ordinary journal chatter that must never be printed"
out1="$(run_once "$J")"
[[ -z "$out1" ]] && ok "W2a: non-matching existing lines print nothing" \
                  || bad "W2a: noise printed: $out1"

append_lines "$J" \
  "10:02 decision dispatch_terminal task=abcd0001 terminal=no_work cause=arm_produced_nothing worker_reason=\"census falsified\"" \
  "10:03 decision dispatch_terminal_dedup task=abcd0001" \
  "10:04 question should the lane retry?"
out2="$(run_once "$J")"
n_term="$(printf '%s\n' "$out2" | grep -c 'dispatch_terminal task=')"
if [[ "$n_term" == "1" ]]; then
  ok "W1a: mv-replaced journal yields the new terminal line"
else
  bad "W1a: expected exactly 1 terminal line, got ${n_term}: $(printf '%s' "$out2")"
fi
if printf '%s' "$out2" | grep -q 'dispatch_terminal_dedup'; then
  bad "W2b: dispatch_terminal_dedup fired (it must not)"
else
  ok "W2b: dispatch_terminal_dedup never fires the emit"
fi
if printf '%s' "$out2" | grep -q 'ordinary journal chatter'; then
  bad "W2c: non-matching new line was printed"
else
  ok "W2c: non-matching new lines never printed"
fi
if printf '%s' "$out2" | grep -q 'question should the lane retry?'; then
  ok "W2d: question lines DO reach the lead"
else
  bad "W2d: question line missing from output: $out2"
fi
if printf '%s' "$out2" | grep -q '^repo/dispatch-abcd0001 '; then
  ok "W1b: emitted line carries <slug>/<task-id> prefix"
else
  bad "W1b: prefix wrong: $(printf '%s' "$out2" | head -1)"
fi
out3="$(run_once "$J")"
if [[ -z "$(printf '%s' "$out3" | grep 'dispatch_terminal')" ]]; then
  ok "W1c: second pass prints nothing new (exactly-once)"
else
  bad "W1c: duplicate emission: $out3"
fi

# ── W3: rotation (fewer lines than stored offset) resets ────────────────────
printf '10:00 fresh start after rotation\n' > "${J}.tmp" && mv "${J}.tmp" "$J"
printf '10:01 decision dispatch_terminal task=abcd0001 terminal=dead cause=rotated\n' >> "$J"
out4="$(run_once "$J")"
if printf '%s' "$out4" | grep -q 'terminal=dead cause=rotated'; then
  ok "W3: rotation reset re-reads the truncated journal"
else
  bad "W3: rotated journal line missed: $out4"
fi

# ── W4: heartbeat on the injectable clock (no real sleeping) ────────────────
# NOW_BIN advances the clock +11s per read, so a --heartbeat 30 watcher fires
# within ~3 loop iterations even with --interval 1.
NOW="$TMP/now"; printf '1780000000' > "$NOW"
NOW_BIN="$TMP/now-bin.sh"
printf '#!/usr/bin/env bash\nv="$(cat %s)"; echo "$((v + 11))" > %s; printf "%%s\\n" "$((v + 11))"\n' "$NOW" "$NOW" > "$NOW_BIN"
chmod +x "$NOW_BIN"

J2="$REPO/docs/leadv2/tasks/dispatch-beef0002/journal.md"
mkdir -p "$(dirname "$J2")"
printf '11:00 decision phase=build lane running\n' > "$J2"

# fresh state dir so no .terminal flags leak from W1-W3
STATE2="$TMP/state2"
out5="$(LEADV2_LANE_WATCH_NOW_BIN="$NOW_BIN" \
  timeout 10 bash "$WATCH" --interval 1 --heartbeat 33 --state-dir "$STATE2" "$J" "$J2" 2>/dev/null || true)"
n_hb1="$(printf '%s\n' "$out5" | grep -c '^hb dispatch-abcd0001 ')"
n_hb2="$(printf '%s\n' "$out5" | grep -c '^hb dispatch-beef0002 ')"
if [[ "$n_hb1" -ge 1 && "$n_hb2" -ge 1 ]]; then
  ok "W4: heartbeat fires per watched lane on the injected clock (${n_hb1}+${n_hb2} hb lines)"
else
  bad "W4: heartbeat missing (lane1=${n_hb1} lane2=${n_hb2}): $(printf '%s' "$out5" | head -5)"
fi
if printf '%s' "$out5" | grep -Eq '^hb dispatch-abcd0001 stream_age=[0-9?]+s phase='; then
  ok "W4b: heartbeat line carries stream_age + phase"
else
  bad "W4b: hb shape wrong: $(printf '%s' "$out5" | grep '^hb' | head -2)"
fi

# ── W5: exit 0 when every watched lane is terminal ──────────────────────────
STATE3="$TMP/state3"
rc=0
LEADV2_LANE_WATCH_NOW_BIN="$NOW_BIN" \
  timeout 10 bash "$WATCH" --interval 1 --heartbeat 0 --state-dir "$STATE3" "$J" >/dev/null 2>&1 || rc=$?
# $J already carries a dispatch_terminal task= line from W3 (fresh state dir ->
# first pass sees it) -> watcher must exit 0 on its own, not via timeout 124.
if [[ "$rc" -eq 0 ]]; then
  ok "W5: watcher exits 0 once every watched lane is terminal"
else
  bad "W5: expected exit 0, got ${rc}"
fi

# ── W6: repo-root arg expands to every lane journal ─────────────────────────
append_lines "$J2" "11:05 question is the second lane visible?"
STATE4="$TMP/state4"
out6="$(bash "$WATCH" --once --state-dir "$STATE4" "$REPO")"
if printf '%s' "$out6" | grep -q 'repo/dispatch-abcd0001.*dispatch_terminal task=abcd0001' \
   && printf '%s' "$out6" | grep -q 'repo/dispatch-beef0002'; then
  ok "W6: repo-root arg expands to all dispatch-* journals (both lanes seen)"
else
  bad "W6: expansion incomplete: $(printf '%s' "$out6" | head -3)"
fi

printf '\n[lane-watch-poll] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "${FAIL}" -eq 0 ]]
