#!/usr/bin/env bash
# tests/test-status-surface-terminal-ledger.sh — STATUS-SURFACE-SHOWS-STALE-TRUTH-01
#
# Proves that a lane with a terminal record (landed/dead/parked) in the
# SEPARATE write-once terminal ledger file is classified as terminal by the
# lanes table path, even when its reservation ledger row still says "confirmed".
#
# Before the fix, the lanes table path (_ss_lanes_py) read ONLY the reservation
# ledger and never the terminal ledger. A dead lane kept its "confirmed" state
# and lingered in the table as a non-terminal stale row — and could render as
# live in the single-lead section if the cached payload predated the terminal
# record.
#
# Run: bash plugins/leadv2/scripts/tests/test-status-surface-terminal-ledger.sh
# run-all-triggers: leadv2-status-surface
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="${SCRIPT_DIR}/leadv2-status-surface.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

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

SB="$(lv2_mktemp_dir ss-term)"
STATE_DIR="${SB}/state"
LEDGER_DIR="${SB}/dispatch-ledger"
RUNS_ROOT="${SB}/cache"
mkdir -p "$STATE_DIR" "$LEDGER_DIR" "$RUNS_ROOT"
LEDGER="${LEDGER_DIR}/testrepo.jsonl"
TERMINAL_LEDGER="${STATE_DIR}/dispatch-ledger.jsonl"
: > "$LEDGER"
: > "$TERMINAL_LEDGER"
printf 'sessions: []\n' > "${STATE_DIR}/active.yaml"

# active.yaml with empty sessions — must exist or the renderer warns and
# short-circuits emit_lanes_table, hiding all rows.
printf 'sessions: []\n' > "${STATE_DIR}/active.yaml"

run_render() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$RENDER" "$@"
}

# ── Setup: reservation row (confirmed) + terminal row (dead) for the same sig8
SIG8="deadbeef"
ARM="sonnet"
HANDLE="12345"
EPOCH=$(( NOW - 600 ))  # 10 minutes ago

# reservation ledger: a confirmed row (non-terminal state)
printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"confirmed","handle":"%s","created_epoch":%s,"lane_label":"Test Lane","task_id":""}\n' \
  "$SIG8" "$ARM" "$HANDLE" "$EPOCH" >> "$LEDGER"

# terminal ledger: dead terminal for the same sig8
printf '{"ts":"2026-08-07T16:58:20Z","task_sig":"%s","founder_task_id":"","task_id":"Test Lane","terminal":"dead","cause":"review_unusable","evidence":"rc=1","commit":"none","deliverable":"unknown","attempt":"%s-%d-99620"}\n' \
  "$SIG8" "$SIG8" "$EPOCH" >> "$TERMINAL_LEDGER"

# provider run dir with journal so the lane has motion (stays visible)
mkdir -p "${RUNS_ROOT}/${ARM}-runs/${HANDLE}"
: > "${RUNS_ROOT}/${ARM}-runs/${HANDLE}/journal.jsonl"
_setage "${RUNS_ROOT}/${ARM}-runs/${HANDLE}/journal.jsonl" 600

# ── Test 1: the lane's STATE column must show done(...), not stale(...) ────
# Pre-fix: stale(10m silent)? — non-terminal, inflates the dead count.
# Post-fix: done(dead) — terminal, correctly classified.
OUT="$(run_render)"
ROW="$(printf '%s\n' "$OUT" | grep 'deadbeef' | head -1)"
if [ -z "$ROW" ]; then
  fail "lane deadbeef not found in output"
else
  if printf '%s' "$ROW" | grep -q 'done('; then
    pass "lane classified as terminal (done)"
  elif printf '%s' "$ROW" | grep -q 'stale('; then
    fail "lane classified as non-terminal stale: $ROW"
  else
    fail "unexpected classification: $ROW"
  fi
fi

# ── Test 2: the header dead count must be 0 (lane is done, not dead) ───────
HDR="$(printf '%s\n' "$OUT" | sed -n 's/^lanes (\([0-9]\) live, \([0-9]\) dead,.*/\2/p')"
if [ "$HDR" = "0" ]; then
  pass "header dead count is 0 (terminal lane does not inflate dead count)"
else
  fail "header dead count is ${HDR:-?}, expected 0"
fi

# ── Test 3: --all single-lead section must not list the terminal lane ──────
OUT_ALL="$(run_render --all)"
SL_BLOCK="$(printf '%s\n' "$OUT_ALL" | awk 'BEGIN{c=1} $0=="---"{c++; next} {if(c==6) print}')"
SL_HDR="$(printf '%s\n' "$SL_BLOCK" | sed -n '1p')"
if printf '%s' "$SL_HDR" | grep -q "active ⚠"; then
  fail "single-lead section shows error: $SL_HDR"
elif printf '%s\n' "$SL_BLOCK" | grep -q "$SIG8"; then
  fail "terminal lane appears in single-lead active block"
else
  pass "terminal lane excluded from single-lead section"
fi

# ── Test 4: control — confirmed lane WITHOUT a terminal record stays stale
# (the merge must not over-suppress non-terminal lanes).
SIG8B="cafef00d"
HANDLE2="67890"
printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"confirmed","handle":"%s","created_epoch":%s,"lane_label":"Alive Lane","task_id":""}\n' \
  "$SIG8B" "$ARM" "$HANDLE2" "$EPOCH" >> "$LEDGER"
mkdir -p "${RUNS_ROOT}/${ARM}-runs/${HANDLE2}"
: > "${RUNS_ROOT}/${ARM}-runs/${HANDLE2}/journal.jsonl"
_setage "${RUNS_ROOT}/${ARM}-runs/${HANDLE2}/journal.jsonl" 600

OUT2="$(run_render)"
ROW2="$(printf '%s\n' "$OUT2" | grep 'cafef00d' | head -1)"
if [ -z "$ROW2" ]; then
  fail "non-terminal lane wrongly suppressed by terminal merge"
else
  if printf '%s' "$ROW2" | grep -q 'stale('; then
    pass "non-terminal lane still classified as stale (merge did not over-suppress)"
  elif printf '%s' "$ROW2" | grep -q 'done('; then
    fail "non-terminal lane wrongly classified as done: $ROW2"
  else
    fail "unexpected classification for control lane: $ROW2"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────
printf -- '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
