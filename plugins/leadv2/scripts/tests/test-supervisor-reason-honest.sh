#!/usr/bin/env bash
# tests/test-supervisor-reason-honest.sh — N7E-SURFACE-DISAGREES defect 2.
#
# Asserts the `supervisor:` line, against a fully sandboxed
# LEADV2_STATUS_STATE_DIR, is readable in one glance as ON / STALE / OFF, and
# that an ABSENT sentinel never surfaces a "no sentinel" reason (it is
# corroborating-only per the design decision -- the heartbeat alone is the
# reason, since leadv2-supervise-resume.sh is contractually write-free and no
# writer maintains the sentinel on the resume path a founder actually takes).
# A sentinel that DOES exist but whose pid is dead still must be reported --
# that is a real, actionable inconsistency, not an absence.
#
# Run: bash plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="${SCRIPT_DIR}/leadv2-status-surface.sh"
SELF="${BASH_SOURCE[0]}"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

for f in "$RENDER" "$SELF"; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n $(basename "$f")"; else fail "bash -n $(basename "$f")"; fi
  if /bin/bash -n "$f" 2>/dev/null; then pass "/bin/bash -n $(basename "$f")"; else fail "/bin/bash -n $(basename "$f")"; fi
done

NOW="${NOW:-$(date +%s)}"
export NOW

_setage() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, off = sys.argv[1], int(sys.argv[2])
now = int(os.environ.get("NOW", "0") or time.time())
t = max(0, now - off)
os.utime(path, (t, t))
PY
}

NEW_SB() {
  SB="$(lv2_mktemp_dir sup-reason)"
  STATE_DIR="${SB}/state"
  LEDGER_DIR="${SB}/dispatch-ledger"
  RUNS_ROOT="${SB}/cache"
  mkdir -p "$STATE_DIR" "$LEDGER_DIR" "$RUNS_ROOT"
  : > "${LEDGER_DIR}/testrepo.jsonl"
  cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
}

# Same 5-var isolation wall as test-status-surface.sh: every path the
# renderer reads is env-injected, so the real ~/.claude is never touched.
run_render() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$RENDER"
}

sup_line() { printf '%s\n' "$1" | grep '^supervisor:'; }

# ── 1. fresh beat, no sentinel at all -> ON, no "no sentinel" mention ──────
NEW_SB
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 40
out="$(run_render)"
line="$(sup_line "$out")"
if printf '%s\n' "$line" | grep -Eq '^supervisor: ON +\(beat 40s\)$' \
   && ! printf '%s\n' "$line" | grep -q 'no sentinel'; then
  pass "fresh beat, no sentinel -> ON (beat 40s), no sentinel mention (got: $line)"
else
  fail "fresh beat, no sentinel -> ON (got: $line)"
fi

# ── 2. old beat (6h), no sentinel at all -> STALE, no "no sentinel" mention ─
NEW_SB
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 21600
out="$(run_render)"
line="$(sup_line "$out")"
if printf '%s\n' "$line" | grep -Eq '^supervisor: STALE +\(beat 6h old\)$' \
   && ! printf '%s\n' "$line" | grep -q 'no sentinel'; then
  pass "old beat, no sentinel -> STALE (beat 6h old), no sentinel mention (got: $line)"
else
  fail "old beat, no sentinel -> STALE (got: $line)"
fi

# ── 3. no beat, no sentinel at all -> OFF, honest reason (not "no sentinel")
NEW_SB
out="$(run_render)"
line="$(sup_line "$out")"
if printf '%s\n' "$line" | grep -Fq 'supervisor: OFF  (no supervise loop running)'; then
  pass "no beat, no sentinel -> OFF (no supervise loop running) (got: $line)"
else
  fail "no beat, no sentinel -> OFF (got: $line)"
fi

# ── 4. sentinel present but pid dead -> the pid-gone clause still survives ──
NEW_SB
printf 'pid 999999\n' > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 41
out="$(run_render)"
line="$(sup_line "$out")"
if printf '%s\n' "$line" | grep -Eq '^supervisor: ON' \
   && printf '%s\n' "$line" | grep -q 'sentinel pid 999999 gone'; then
  pass "sentinel present, pid dead, fresh beat -> ON, pid-gone clause survives (got: $line)"
else
  fail "sentinel present, pid dead -> pid-gone clause (got: $line)"
fi

# ── 5. supervised vs unsupervised sessions must render differently ─────────
NEW_SB
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 10
supervised_line="$(sup_line "$(run_render)")"
NEW_SB
unsupervised_line="$(sup_line "$(run_render)")"
if [ "$supervised_line" != "$unsupervised_line" ] \
   && printf '%s\n' "$supervised_line" | grep -q '^supervisor: ON' \
   && printf '%s\n' "$unsupervised_line" | grep -q '^supervisor: OFF'; then
  pass "supervised (ON) vs unsupervised (OFF) sessions read differently at a glance"
else
  fail "supervised/unsupervised did not differ as expected (supervised: $supervised_line | unsupervised: $unsupervised_line)"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
