#!/usr/bin/env bash
# tests/test-single-lead-beat.sh — PULSE-IN-SINGLE-LEAD-01
#
# Verifies the single-lead beat driver (leadv2-pulse-beat.sh) and the hook
# that delivers + triggers it (leadv2-single-lead-beat.sh), without touching
# leadv2-broad-status.sh's own rendering logic (that composer is out of
# scope for this lane — its own suite is test-broad-status-duty.sh).
#
# Cases:
#   1. --now with no supervise loop running composes a beat via the REAL
#      composer (claude call stubbed) -> ready-line appears in the log AND
#      the hook's next fire delivers it as additionalContext, with the
#      ready-line's at= matching founder-status.md's own line-1 stamp.
#   2. A second hook fire with nothing changed since delivery emits NO
#      additionalContext (idempotent) even though the log line is still the
#      most recent one — the beat happened, delivery stayed quiet.
#   3. --due reports loop-owns when a live .supervise-loop.json pid exists,
#      and the hook's trigger step is then a no-op (throttle file untouched).
#   4. Kill-switch LEADV2_SINGLE_LEAD_BEAT=0 makes both the driver and the
#      hook full no-ops.
#
# Hermetic: LEADV2_PROJECT_ROOT/LEADV2_STATE_ROOT point at throwaway dirs,
# the composer's claude call and the backlog pump are stubbed exactly as in
# test-broad-status-duty.sh.
# Run: bash scripts/tests/test-single-lead-beat.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # plugins/leadv2
source "${SCRIPT_DIR}/leadv2-temp.sh"

PULSE_BEAT_SH="${SCRIPT_DIR}/leadv2-pulse-beat.sh"
BROAD_STATUS_SH="${SCRIPT_DIR}/leadv2-broad-status.sh"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-single-lead-beat.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir single-lead-beat)"
REPO="$TMP/proj"
STATE="$TMP/state"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STATE" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO"

LOG_FILE="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" supervise-loop.log)"
STATE_DIR="$(PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$STATE_PATH_SH" --no-link root)"
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

cat >"$STUBS/collector.sh" <<'EOF'
#!/usr/bin/env bash
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
printf '{"result":"тестовый хвост: очередь пуста, ничего не приземлилось."}'
EOF
cat >"$STUBS/pump.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" ]]; then
  echo "check complete: examined=1 dispatched=2 live=0 remaining_capacity=5 below_floor=0" >&2
fi
exit 0
EOF
chmod +x "$STUBS/collector.sh" "$STUBS/claude.sh" "$STUBS/pump.sh"

beat_env() {
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BACKLOG_PUMP_BIN="$STUBS/pump.sh" \
    LEADV2_BROAD_STATUS_BIN="$BROAD_STATUS_SH" \
    "$@"
}

hook_fire() {  # <event: UserPromptSubmit|PostToolUse>
  printf '{"cwd":"%s","hook_event_name":"%s"}' "$REPO" "$1" \
    | env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" CLAUDE_PROJECT_DIR="$REPO" \
        LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
        LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
        LEADV2_BACKLOG_PUMP_BIN="$STUBS/pump.sh" \
        LEADV2_BROAD_STATUS_BIN="$BROAD_STATUS_SH" \
        CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
        bash "$HOOK_SH"
}

# ── Test 1: --now composes a real beat, hook delivers it, stamps match ────
beat_env bash "$PULSE_BEAT_SH" --now >/dev/null 2>&1 || true
if grep -q 'BROAD_STATUS_READY' "$LOG_FILE" 2>/dev/null; then
  pass "T1a: --now composed a beat (ready-line in log)"
else
  fail "T1a: no BROAD_STATUS_READY line after --now"
fi

DELIVER_OUT="$(hook_fire UserPromptSubmit)"
if printf -- '%s' "$DELIVER_OUT" | grep -q 'BROAD_STATUS_READY'; then
  pass "T1b: hook delivered the ready-line as additionalContext"
else
  fail "T1b: hook produced no delivery on first fire: $DELIVER_OUT"
fi

AT_FROM_LINE="$(printf -- '%s' "$DELIVER_OUT" | sed -n 's/.* at=\([^ "\\]*\).*/\1/p' | head -1)"
AT_FROM_FILE="$(head -1 "$FOUNDER_STATUS" 2>/dev/null | sed -n 's/^\([^ ]*\) .*/\1/p')"
if [[ -n "$AT_FROM_LINE" && "$AT_FROM_LINE" == "$AT_FROM_FILE" ]]; then
  pass "T1c: ready-line at=$AT_FROM_LINE matches founder-status.md line-1 stamp"
else
  fail "T1c: stamp mismatch — ready-line at=$AT_FROM_LINE vs file=$AT_FROM_FILE"
fi

# ── Test 2: second fire, nothing changed -> no duplicate delivery ─────────
DELIVER_OUT2="$(hook_fire UserPromptSubmit)"
if [[ -z "$DELIVER_OUT2" ]]; then
  pass "T2: second fire with no change emits nothing (no duplicate wake)"
else
  fail "T2: expected empty output on unchanged re-fire, got: $DELIVER_OUT2"
fi
if grep -c 'BROAD_STATUS_READY' "$LOG_FILE" | grep -qx 1; then
  pass "T2b: log still shows exactly the one beat (no re-composition from delivery)"
else
  fail "T2b: unexpected beat count in log: $(grep -c 'BROAD_STATUS_READY' "$LOG_FILE")"
fi

# ── Test 3: loop-owns -> --due says loop-owns, trigger is a no-op ─────────
LOOP_SENTINEL="${STATE_DIR}/.supervise-loop.json"
printf '{"pid": %s}' "$$" > "$LOOP_SENTINEL"
BEAT_LAST_BEFORE=""
[[ -f "${STATE_DIR}/.pulse-beat-last" ]] && BEAT_LAST_BEFORE="$(cat "${STATE_DIR}/.pulse-beat-last")"
DUE_OUT="$(env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$PULSE_BEAT_SH" --due 2>&1)"; DUE_RC=$?
if [[ "$DUE_OUT" == "loop-owns" && "$DUE_RC" -eq 1 ]]; then
  pass "T3a: --due reports loop-owns while .supervise-loop.json pid is live"
else
  fail "T3a: expected loop-owns/rc1, got '$DUE_OUT' rc=$DUE_RC"
fi
env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" bash "$PULSE_BEAT_SH" --check >/dev/null 2>&1 || true
sleep 0.3
BEAT_LAST_AFTER=""
[[ -f "${STATE_DIR}/.pulse-beat-last" ]] && BEAT_LAST_AFTER="$(cat "${STATE_DIR}/.pulse-beat-last")"
if [[ "$BEAT_LAST_BEFORE" == "$BEAT_LAST_AFTER" ]]; then
  pass "T3b: --check does not touch the throttle stamp while the loop is live"
else
  fail "T3b: throttle stamp changed despite live loop ($BEAT_LAST_BEFORE -> $BEAT_LAST_AFTER)"
fi
rm -f "$LOOP_SENTINEL"

# ── Test 4: kill-switch -> both driver and hook are full no-ops ───────────
rm -f "${STATE_DIR}/.pulse-beat-last"
env LEADV2_SINGLE_LEAD_BEAT=0 LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
  bash "$PULSE_BEAT_SH" --now >/dev/null 2>&1 || true
if [[ -f "${STATE_DIR}/.pulse-beat-last" ]]; then
  fail "T4a: kill-switched driver still touched .pulse-beat-last"
else
  pass "T4a: kill-switched driver touched nothing"
fi
HOOK_OUT4="$(printf '{"cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$REPO" \
  | env LEADV2_SINGLE_LEAD_BEAT=0 LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
      CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOK_SH")"
if [[ -z "$HOOK_OUT4" ]]; then
  pass "T4b: kill-switched hook emits nothing"
else
  fail "T4b: kill-switched hook still emitted: $HOOK_OUT4"
fi

# ── Summary ─────────────────────────────────────────────────────────────
rm -rf "$TMP"
printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
