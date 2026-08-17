#!/usr/bin/env bash
# tests/test-broad-status-duty.sh — PULSE-IS-A-PLUGIN-DUTY-01.
#
# The transition this suite exists to survive: the beat was composed,
# timestamped, and written to two files — but contained no URGENT substring,
# so the founder's `grep --line-buffered URGENT` watcher filtered it out and
# no live session was ever woken. Cases:
#
#   1. one beat -> exactly ONE [SUPERVISE-URGENT] BROAD_STATUS_READY line
#      that passes the REAL filter (grep URGENT), and founder-status.md
#      carries the dispatched= stamp (C1+C2).
#   2. dedupe: same beat identity re-run -> still one line; new identity ->
#      fires; lib force-disabled -> pass-through still one line per run (R2).
#   3. ordering: full loop, one cycle -> pump ran BEFORE the composer wrote
#      founder-status.md, and the ready-line's dispatched= matches the pump.
#   4. session-death survival (the demonstration, not a claim): kill the
#      loop, age past 2xPULSE_S, run the watchdog -> LOOP_SILENT, a NEW live
#      pid, and a fresh beat afterwards. Includes the --ensure adopt
#      assertion (R3: single-owner sentinel, no sibling on double-ensure).
#   5. degraded beat: collector missing -> BROAD_STATUS_READY degraded=1
#      still appears (a missing status is visible, never silent).
#   9. failed beat is visibly failed IN THE ARTIFACT (fix r1): collector or
#      renderer failure REPLACES founder-status.md (sentinel gone, СТАТУС НЕ
#      СОБРАН, pinned beat, degraded=1 on line 1); ready-line at= always
#      equals the file's line-1 timestamp; unwritable artifact -> READY is
#      refused (BROAD_STATUS_FAILED stale_file_kept=1, stale bytes kept).
#   6. kill-switch: LEADV2_SUPERVISE_BROAD_STATUS_S=0 -> no beat, no
#      ready-line (the rollback cannot half-work).
#   7. crontab unavailable -> the skip is LOGGED, not silent.
#   8. wording drift (R4): the relay sentence is present verbatim in every
#      C3 surface, and the CronCreate ban lives where a non-supervisor lead
#      reads it (C4).
#
# Hermetic: LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT point at throwaway dirs,
# CRONTAB_BIN is a stub (the real crontab is never touched), the composer's
# claude call is a stub (no model invoked), the pump is a stub.
# Non-goals: real crontab, real reboot, real claude.
#
# NOTE on timing: one supervise.sh snapshot costs ~25s in a bare fixture
# (liveness/pick retries against an empty control plane), so loop-running
# cases use generous timeouts — a cycle completes in ~60s, not ~5s.
# Run: bash scripts/tests/test-broad-status-duty.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # plugins/leadv2
source "${SCRIPT_DIR}/leadv2-temp.sh"

LOOP_SH="${SCRIPT_DIR}/leadv2-supervise-loop.sh"
BROAD_STATUS_SH="${SCRIPT_DIR}/leadv2-broad-status.sh"
WATCHDOG_SH="${SCRIPT_DIR}/leadv2-supervise-watchdog.sh"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir broad-status-duty)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
PUMP_COUNTER="$TMP/pump-counter"
CRONTAB_STUB_STATE="$TMP/crontab-state"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
# TEST SAFETY: this suite writes through leadv2-state-path.sh — prove the
# fixture is a throwaway before any control-plane write happens.
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE"

LOG_FILE="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" supervise-loop.log)"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"
ready_count()   { grep -c 'BROAD_STATUS_READY' "$LOG_FILE" 2>/dev/null || true; }
urgent_count()  { grep 'URGENT' "$LOG_FILE" 2>/dev/null | grep -c 'BROAD_STATUS_READY' || true; }
started_pids()  { sed -n 's/.*\[supervise-loop\] started pid=\([0-9]*\) .*/\1/p' "$LOG_FILE" 2>/dev/null; }

# ── stubs ──────────────────────────────────────────────────────────────────
cat >"$STUBS/collector.sh" <<'EOF'
#!/usr/bin/env bash
# Minimal snapshot: no lanes, no repo_facts — enough for the deterministic
# renderer to produce the placeholder table.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
printf '{"sections": {}}' >"$out"
EOF
cat >"$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
# Fixed composer result — no model is called from this suite.
printf '{"result":"тестовый хвост: очередь пуста, ничего не приземлилось."}'
EOF
cat >"$STUBS/pump.sh" <<EOF
#!/usr/bin/env bash
# Stub pump: increments a counter on every check (mtime = last run) and logs
# the same "check complete:" summary line the real pump emits.
if [[ "\${1:-}" == "check" ]]; then
  n=0
  [[ -f "\$PUMP_COUNTER" ]] && n="\$(cat "\$PUMP_COUNTER" 2>/dev/null || echo 0)"
  echo \$((n + 1)) >"\$PUMP_COUNTER"
  echo "check complete: examined=1 dispatched=2 live=0 remaining_capacity=5 below_floor=0" >&2
fi
exit 0
EOF
cat >"$STUBS/crontab.sh" <<EOF
#!/usr/bin/env bash
# Stub crontab: records installs into a state file, never touches the real one.
case "\${1:-}" in
  -l) cat "\$CRONTAB_STUB_STATE" 2>/dev/null; exit 0 ;;
  -)  cat >"\$CRONTAB_STUB_STATE"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$STUBS/collector.sh" "$STUBS/claude.sh" "$STUBS/pump.sh" "$STUBS/crontab.sh"

# Common env for every direct broad-status invocation.
beat_env() {  # <beat-at> [extra env assignments via caller]
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="$1" \
    LEADV2_BROAD_STATUS_DISPATCHED="2" \
    "${@:2}"
}
loop_env() {  # extra env assignments
  env LEADV2_PROJECT_ROOT="$REPO" CLAUDE_PROJECT_DIR="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BACKLOG_PUMP_BIN="$STUBS/pump.sh" \
    CRONTAB_BIN="$STUBS/crontab.sh" \
    "$@"
}
wait_for() {  # <desc> <timeout_s> <cmd...> — poll until cmd succeeds
  local desc="$1" tmo="$2"; shift 2
  local i=0
  while (( i < tmo )); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1; i=$(( i + 1 ))
  done
  fail "$desc (waited ${tmo}s)"
  return 1
}

cleanup() {
  # Kill any loop this suite left behind (sentinel pid), then drop the tree.
  local sent pid
  sent="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" .supervise-loop.json 2>/dev/null || true)"
  if [[ -n "$sent" && -f "$sent" ]]; then
    pid="$(python3 -c "import json;print(json.load(open('$sent')).get('pid',0))" 2>/dev/null || echo 0)"
    [[ "$pid" -gt 0 ]] && kill "$pid" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# ── Test 1: ready-line emitted, passes the real filter, artifact written ───
beat_env "2026-08-16T10:00:00Z" bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
if [[ -f "$FOUNDER_STATUS" ]]; then pass "T1a: founder-status.md written"; else fail "T1a: founder-status.md missing"; fi
if [[ "$(urgent_count)" == "1" ]]; then pass "T1b: exactly one URGENT-filtered BROAD_STATUS_READY line"; else fail "T1b: expected 1 URGENT BROAD_STATUS_READY line, got $(urgent_count)"; fi
if grep -q 'BROAD_STATUS_READY at=2026-08-16T10:00:00Z path=docs/leadv2/founder-status.md rows=0 dispatched=2$' "$LOG_FILE"; then
  pass "T1c: ready-line carries at/path/rows/dispatched"
else
  fail "T1c: ready-line shape wrong: $(grep BROAD_STATUS_READY "$LOG_FILE" | tail -1)"
fi
if grep -q '\[BROAD_STATUS\] dispatched=2$' "$LOG_FILE" && grep -q 'dispatched=2' "$FOUNDER_STATUS"; then
  pass "T1d: block header + artifact carry the dispatched= stamp"
else
  fail "T1d: dispatched= stamp missing from block/artifact"
fi

# ── Test 2: dedupe (same beat suppressed, new beat fires, lib-less R2) ─────
beat_env "2026-08-16T10:00:00Z" bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
if [[ "$(ready_count)" == "1" ]]; then pass "T2a: same beat re-run -> still one line"; else fail "T2a: dedupe failed, $(ready_count) lines"; fi
beat_env "2026-08-16T10:30:00Z" bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
if [[ "$(ready_count)" == "2" ]]; then pass "T2b: new beat -> fires"; else fail "T2b: expected 2 lines, got $(ready_count)"; fi
beat_env "2026-08-16T11:00:00Z" LEADV2_ALARM_DEDUPE_BIN=/nonexistent-lib \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
if [[ "$(ready_count)" == "3" ]]; then pass "T2c: lib absent -> pass-through still one line per beat (R2)"; else fail "T2c: expected 3 lines, got $(ready_count)"; fi

# ── Test 3: dispatch before report, through the real loop branch ───────────
: >"$LOG_FILE"; : >"$PUMP_COUNTER" 2>/dev/null || true; rm -f "$PUMP_COUNTER" "$FOUNDER_STATUS"
loop_env timeout 90 \
  LEADV2_SUPERVISE_LOOP_MAX_CYCLES=1 LEADV2_SUPERVISE_LOOP_PULSE_ON_START=1 \
  LEADV2_SUPERVISE_EVENT_POLL_S=0 \
  bash "$LOOP_SH" >/dev/null 2>&1 || true
if [[ -f "$PUMP_COUNTER" && -f "$FOUNDER_STATUS" ]]; then
  ORDER="$(python3 -c "
import os, sys
pump, status = os.path.getmtime('$PUMP_COUNTER'), os.path.getmtime('$FOUNDER_STATUS')
print('before' if pump < status else 'after')
")"
  if [[ "$ORDER" == "before" ]]; then pass "T3a: pump ran before founder-status.md was written"; else fail "T3a: pump ran AFTER the composer"; fi
else
  fail "T3a: pump counter or founder-status.md missing after one loop cycle"
  echo "=== T3a DEBUG: LOG_FILE=[$LOG_FILE] exists=$(test -f "$LOG_FILE" && echo yes || echo no)"; echo "=== T3a DEBUG loop-log tail:"; tail -25 "$LOG_FILE" 2>&1; echo "=== T3a DEBUG STATE=[$STATE]:"; ls "$STATE" 2>&1 | head; echo "=== T3a DEBUG REPO docs:"; ls "$REPO/docs/leadv2" 2>&1 | head
fi
if grep -q 'BROAD_STATUS_READY at=.* path=docs/leadv2/founder-status.md rows=0 dispatched=2' "$LOG_FILE"; then
  pass "T3b: loop-run beat stamps the pump's dispatched count"
else
  fail "T3b: no ready-line with dispatched=2 after loop cycle: $(grep BROAD_STATUS_READY "$LOG_FILE" || echo none)"
fi

# ── Test 4: session-death survival — the demonstration ─────────────────────
: >"$LOG_FILE"; rm -f "$PUMP_COUNTER" "$FOUNDER_STATUS"
loop_env timeout 240 \
  LEADV2_SUPERVISE_LOOP_PULSE_ON_START=1 LEADV2_SUPERVISE_EVENT_POLL_S=1 \
  LEADV2_SUPERVISE_PULSE_S=2 LEADV2_SUPERVISE_BROAD_STATUS_S=2 \
  bash "$LOOP_SH" >/dev/null 2>&1 &
T4_LOOP_SHELL=$!
wait_for "T4a: first beat appears" 120 bash -c "grep -q BROAD_STATUS_READY '$LOG_FILE'"
OLD_PID="$(started_pids | tail -n1)"
# R3: a second --ensure while the loop is live must ADOPT, never spawn.
STARTED_BEFORE="$(started_pids | grep -c . || true)"
loop_env timeout 20 bash "$LOOP_SH" --ensure >/dev/null 2>&1 || true
if grep -q 'adopt existing loop pid=' "$LOG_FILE" && [[ "$(started_pids | grep -c . || true)" == "$STARTED_BEFORE" ]]; then
  pass "T4b: double --ensure adopts (no sibling loop, R3)"
else
  fail "T4b: --ensure did not cleanly adopt the live loop"
fi
kill "$OLD_PID" 2>/dev/null || true
sleep 5   # heartbeat ages past 2xPULSE_S=4s AND the pid is dead
loop_env timeout 240 LEADV2_SUPERVISE_PULSE_S=2 bash "$WATCHDOG_SH" --project-root "$REPO" >/dev/null 2>&1 &
T4_WD=$!
wait_for "T4c: LOOP_SILENT alarm" 60 bash -c "grep -q 'LOOP_SILENT' '$LOG_FILE'"
wait_for "T4d: replacement loop started" 90 bash -c "[[ \"\$(started_pids | tail -n1)\" != \"$OLD_PID\" && -n \"\$(started_pids | tail -n1)\" ]]"
NEW_PID="$(started_pids | tail -n1)"
wait_for "T4e: fresh beat from the replacement loop" 150 bash -c "[[ \"\$(grep -c BROAD_STATUS_READY '$LOG_FILE')\" -ge 2 ]]"
if kill -0 "$NEW_PID" 2>/dev/null; then pass "T4f: replacement loop pid=$NEW_PID is alive (old=$OLD_PID)"; else fail "T4f: replacement loop not alive"; fi
kill "$T4_WD" "$NEW_PID" 2>/dev/null || true
wait "$T4_WD" 2>/dev/null || true

# ── Test 5: degraded beat is visible ───────────────────────────────────────
: >"$LOG_FILE"
env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
  LEADV2_STATUS_COLLECTOR_BIN=/nonexistent-collector \
  LEADV2_BROAD_STATUS_BEAT_AT="2026-08-16T12:00:00Z" \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
if grep -q 'BROAD_STATUS_READY at=.* degraded=1$' "$LOG_FILE"; then
  pass "T5: collector failure -> degraded ready-line still wakes"
else
  fail "T5: no degraded=1 ready-line: $(cat "$LOG_FILE")"
fi

# ── Test 9: a failed beat is visibly failed in the ARTIFACT (fix r1) ───────
# T5 asserts the degraded ready-line — the test that passed while the bug was
# live. T9 asserts on what the relay would PUBLISH: the artifact bytes.
mkdir -p "$REPO/docs/leadv2"
seed_stale_status() {
  printf '2026-08-16T00:00:00Z [BROAD_STATUS] dispatched=0\n' >"$FOUNDER_STATUS"
  printf '| Линия | Что делает | Кто делает | Состояние | Уже на диске |\n' >>"$FOUNDER_STATUS"
  printf '|---|---|---|---|---|\n' >>"$FOUNDER_STATUS"
  printf '| HEALTHY-SENTINEL-DO-NOT-KEEP | всё хорошо | — | тихо 5 мин | — |\n\n' >>"$FOUNDER_STATUS"
  printf 'Всё отлично, ничего не происходит.\n[BROAD_STATUS_END]\n' >>"$FOUNDER_STATUS"
}
degraded_assertions() {  # <label> <pinned-beat> <reason-substring>
  local label="$1" beat="$2" reason_re="$3"
  if grep -q 'HEALTHY-SENTINEL-DO-NOT-KEEP' "$FOUNDER_STATUS"; then
    fail "$label: previous healthy table still in founder-status.md"
  else pass "$label: previous healthy table replaced"; fi
  if grep -q 'СТАТУС НЕ СОБРАН' "$FOUNDER_STATUS"; then
    pass "$label: explicit СТАТУС НЕ СОБРАН sentence present"
  else fail "$label: no СТАТУС НЕ СОБРАН sentence"; fi
  if grep -q "$beat" "$FOUNDER_STATUS"; then
    pass "$label: pinned beat timestamp present"
  else fail "$label: pinned beat timestamp missing"; fi
  if head -n1 "$FOUNDER_STATUS" | grep -q 'degraded=1'; then
    pass "$label: line 1 carries degraded=1"
  else fail "$label: line 1 lacks degraded=1: $(head -n1 "$FOUNDER_STATUS")"; fi
  if grep -q "$reason_re" "$FOUNDER_STATUS"; then
    pass "$label: Состояние cell names the failure ($reason_re)"
  else fail "$label: failure reason missing from the table row"; fi
}

# T9a: collector failure replaces the artifact.
seed_stale_status; : >"$LOG_FILE"
beat_env "2026-08-16T12:30:00Z" LEADV2_STATUS_COLLECTOR_BIN=/bin/false \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
degraded_assertions "T9a" "2026-08-16T12:30:00Z" 'collector failed'

# T9b: render failure (invalid JSON snapshot) replaces the artifact — the
# failure path the review did not name.
cat >"$STUBS/bad-collector.sh" <<'EOF'
#!/usr/bin/env bash
# Writes a snapshot that is NOT valid JSON -> the deterministic render fails.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$out" ]] && exit 1
printf 'this-is-not-json' >"$out"
EOF
chmod +x "$STUBS/bad-collector.sh"
seed_stale_status; : >"$LOG_FILE"
beat_env "2026-08-16T13:00:00Z" LEADV2_STATUS_COLLECTOR_BIN="$STUBS/bad-collector.sh" \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
degraded_assertions "T9b" "2026-08-16T13:00:00Z" 'render failed'

# T9c: stamp coherence (P2) — the ready-line's at= always equals the leading
# timestamp of founder-status.md line 1, healthy beat AND degraded beat, so a
# reader can detect staleness without trusting the writer.
stamp_coherence_check() {  # <label>
  local label="$1" at_val line1_ts
  at_val="$(sed -n 's/.*BROAD_STATUS_READY at=\([^ ]*\).*/\1/p' "$LOG_FILE" | tail -n1)"
  line1_ts="$(head -n1 "$FOUNDER_STATUS" | awk '{print $1}')"
  if [[ -n "$at_val" && "$at_val" == "$line1_ts" ]]; then
    pass "$label: ready-line at= == founder-status.md line-1 timestamp"
  else
    fail "$label: stamp mismatch: ready at=$at_val file line1=$line1_ts"
  fi
}
seed_stale_status; : >"$LOG_FILE"
beat_env "2026-08-16T13:30:00Z" bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
stamp_coherence_check "T9c-healthy"
beat_env "2026-08-16T14:00:00Z" LEADV2_STATUS_COLLECTOR_BIN=/bin/false \
  bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
stamp_coherence_check "T9c-degraded"

# T9d: artifact unwritable -> READY refused, stale file kept byte-identical.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  log "SKIP: T9d (running as root — chmod 500 does not block writes)"
else
  RO_DIR="$TMP/ro-status"; mkdir -p "$RO_DIR"
  printf 'STALE-BYTES-KEEP\n' >"$RO_DIR/founder-status.md"
  STALE_COPY="$TMP/t9d-stale-copy"; cp "$RO_DIR/founder-status.md" "$STALE_COPY"
  chmod 500 "$RO_DIR"
  : >"$LOG_FILE"
  beat_env "2026-08-16T14:30:00Z" LEADV2_FOUNDER_STATUS_PATH="$RO_DIR/founder-status.md" \
    LEADV2_STATUS_COLLECTOR_BIN=/bin/false bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
  chmod 700 "$RO_DIR"   # restore mode BEFORE suite teardown (fixture-leak risk)
  if [[ "$(ready_count)" == "0" ]]; then
    pass "T9d: unwritable artifact -> zero BROAD_STATUS_READY lines"
  else
    fail "T9d: READY advertised a file it could not write ($(ready_count) lines)"
  fi
  t9d_failed="$(grep -c 'BROAD_STATUS_FAILED .*stale_file_kept=1' "$LOG_FILE" 2>/dev/null || true)"
  if [[ "$t9d_failed" == "1" ]]; then
    pass "T9d: exactly one BROAD_STATUS_FAILED stale_file_kept=1"
  else
    fail "T9d: expected 1 BROAD_STATUS_FAILED line, got $t9d_failed: $(grep BROAD_STATUS_FAILED "$LOG_FILE" || echo none)"
  fi
  if cmp -s "$RO_DIR/founder-status.md" "$STALE_COPY"; then
    pass "T9d: stale file byte-identical (nothing half-wrote it)"
  else
    fail "T9d: stale file was modified despite the unwritable dir"
  fi
fi

# ── Test 6: kill-switch disables beat AND ready-line ────────────────────────
: >"$LOG_FILE"; rm -f "$FOUNDER_STATUS"
loop_env timeout 40 \
  LEADV2_SUPERVISE_LOOP_MAX_CYCLES=1 LEADV2_SUPERVISE_LOOP_PULSE_ON_START=1 \
  LEADV2_SUPERVISE_EVENT_POLL_S=0 LEADV2_SUPERVISE_BROAD_STATUS_S=0 \
  bash "$LOOP_SH" >/dev/null 2>&1 || true
if [[ "$(ready_count)" == "0" && ! -f "$FOUNDER_STATUS" ]]; then
  pass "T6: BROAD_STATUS_S=0 -> no beat, no ready-line (rollback whole)"
else
  fail "T6: kill-switch half-works (ready lines: $(ready_count))"
fi

# ── Test 7: crontab unavailable -> skip is logged ──────────────────────────
: >"$LOG_FILE"
loop_env timeout 40 CRONTAB_BIN=/nonexistent-crontab \
  LEADV2_SUPERVISE_LOOP_MAX_CYCLES=1 LEADV2_SUPERVISE_LOOP_PULSE_ON_START=1 \
  LEADV2_SUPERVISE_EVENT_POLL_S=0 \
  bash "$LOOP_SH" >/dev/null 2>&1 || true
if grep -q 'beat-cron install skipped: .* unavailable' "$LOG_FILE"; then
  pass "T7: cron-install skip is logged, gap visible"
else
  fail "T7: skip not logged: $(grep -i cron "$LOG_FILE" || echo none)"
fi

# ── Test 8: wording drift across the C3/C4 surfaces (R4) ───────────────────
ANCHOR="$PLUGIN_DIR/hooks/leadv2-task-anchor.sh"
n="$(grep -c 'BROAD_STATUS_READY' "$ANCHOR" || true)"
if [[ "$n" -eq 2 ]]; then pass "T8a: anchor DIRECTIVE lists the relay in BOTH blocks"; else fail "T8a: anchor has $n BROAD_STATUS_READY mentions (expected 2)"; fi
for f in "$PLUGIN_DIR/commands/leadv2.md" "$PLUGIN_DIR/hooks/leadv2-supervisor-mode-reinject.sh" "$PLUGIN_DIR/docs/supervisor-role.md"; do
  if grep -q 'BROAD_STATUS_READY' "$f" && grep -q 'verbatim relay of a' "$f"; then
    pass "T8b: $(basename "$f") carries the relay contract"
  else
    fail "T8b: $(basename "$f") drifted from the relay wording"
  fi
done
for f in "$ANCHOR" "$PLUGIN_DIR/commands/leadv2.md"; do
  if grep -q 'CronCreate' "$f"; then pass "T8c: CronCreate ban present in $(basename "$f") (C4)"; else fail "T8c: CronCreate ban missing from $(basename "$f")"; fi
done

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]:-}" >&2
  exit 1
fi
exit 0
