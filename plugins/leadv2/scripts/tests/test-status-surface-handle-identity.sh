#!/usr/bin/env bash
# tests/test-status-surface-handle-identity.sh — N-7c DoD test.
#
# Signal 2 (ledger `handle`) must prove IDENTITY, not mere existence: the pid
# behind the handle must be THIS lane's worker (argv carries
# --task-id dispatch-<sig8>), OR the row must be demonstrably fresh. A bare,
# recycled, or foreign-uid pid is no longer trusted -- that is exactly how a
# 47h-old dead lane rendered live(pid 71249).
#
# Drives the surface with LEADV2_STATUS_PS_SNAPSHOT (the documented injection
# point, leadv2-status-surface.sh:198) so no real worker processes are needed.
# The handle pid is the test's own $$ (genuinely alive via os.kill(pid,0));
# only the argv content and row age vary. Acceptance #1 (0 live) and #2 (1
# live) are exercised at the end against the real surface.
#
# Run: bash plugins/leadv2/scripts/tests/test-status-surface-handle-identity.sh

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

bash -n "$RENDER" 2>/dev/null && pass "bash -n leadv2-status-surface.sh" || fail "bash -n leadv2-status-surface.sh"
bash -n "$SELF"   2>/dev/null && pass "bash -n $(basename "$SELF")"      || fail "bash -n $(basename "$SELF")"

NOW="${NOW:-$(date +%s)}"
export NOW
HOURS47=$(( 47 * 3600 ))

_setage() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, off = sys.argv[1], int(sys.argv[2])
now = int(os.environ.get("NOW", "0") or time.time())
t = max(0, now - off)
os.utime(path, (t, t))
PY
}

SB=; STATE_DIR=; LEDGER_DIR=; RUNS_ROOT=; LEDGER=
NEW_SB() {
  SB="$(lv2_mktemp_dir ss-handle-id)"
  STATE_DIR="${SB}/state"
  LEDGER_DIR="${SB}/dispatch-ledger"
  RUNS_ROOT="${SB}/cache"
  mkdir -p "$STATE_DIR" "$LEDGER_DIR" "$RUNS_ROOT"
  LEDGER="${LEDGER_DIR}/testrepo.jsonl"
  : > "$LEDGER"
  printf 'meta: {}\nsessions: []\n' > "${STATE_DIR}/active.yaml"
}

# render with a pinned PS_SNAPSHOT ($1). No active.yaml -> no session rows, so
# only the ledger `handle` (signal 2) and argv (signal 3) paths are exercised.
run_ps() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_PS_SNAPSHOT="$1" \
  bash "$RENDER"
}

# ledger worker row: _ledger <sig8> <arm> <handle> <created_epoch_off>
_ledger() {
  printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"confirmed","handle":"%s","created_epoch":%s}\n' \
    "$1" "$2" "$3" "$(( NOW - $4 ))" >> "$LEDGER"
}
# run dir: _run <handle> <arm> <status> <exit_code> <journal_off>
_run() {
  local h="$1" arm="$2" st="$3" ec="$4" off="$5"
  local d="${RUNS_ROOT}/${arm}-runs/${h}"
  mkdir -p "$d"
  printf 'status: %s\nexit_code: %s\nmodel: glm-5.2\n' "$st" "$ec" > "${d}/meta.yaml"
  : > "${d}/journal.jsonl"
  [ "$off" -gt 0 ] && _setage "${d}/journal.jsonl" "$off"
}

# row whose last field == sig carries "live" (any live marker).
sig_live()  { printf '%s\n' "$2" | awk -v s="$1" 'index($0,"live")&&$NF==s{f=1} END{exit !f}'; }
sig_seen()  { printf '%s\n' "$2" | awk -v s="$1" '$NF==s{f=1} END{exit !f}'; }
# "N live" count from the lanes header line.
live_count() { printf '%s\n' "$1" | sed -n 's/.*lanes (\([0-9][0-9]*\) live.*/\1/p' | head -1; }
# any "live(" marker at all in the rendered output.
has_live_marker() { printf '%s\n' "$1" | grep -q 'live('; }

SIG="abc12345"
ARM="sonnet"
H=$$   # genuinely alive pid; only its argv (via PS_SNAPSHOT) and row age vary
# age between signal-4's 120s window and the 900s HANDLE_TRUST window: isolates
# signal-2's fresh fallback (signal-4 live(fresh) cannot fire here).
MID_AGE=300

# ps line: pid $$ exists but is plainly /usr/bin/sleep -- no dispatch marker
PS_UNRELATED="$(printf '  %s /usr/bin/sleep 9999\n' "$H")"

# ── 1. handle alive, UNRELATED argv, row 47h old → NOT live (acceptance #3) ─
NEW_SB
_ledger "$SIG" "$ARM" "$H" "$HOURS47"
_run    "$H" "$ARM" "running" "0" "$HOURS47"
out="$(run_ps "$PS_UNRELATED")"
if [ "$(live_count "$out")" = "0" ] && ! has_live_marker "$out"; then
  pass "unrelated argv + 47h row is NOT live"
else
  fail "unrelated argv + 47h row is NOT live (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── 2. handle alive, argv IS this lane's worker → live (identity holds) ─────
NEW_SB
_ledger "$SIG" "$ARM" "$H" "$HOURS47"
_run    "$H" "$ARM" "running" "0" "$HOURS47"
PS_MATCH="$(printf '  %s /usr/bin/env claude --task-id dispatch-%s\n' "$H" "$SIG")"
out="$(run_ps "$PS_MATCH")"
if [ "$(live_count "$out")" = "1" ] && sig_live "$SIG" "$out"; then
  pass "matching argv renders live even at 47h"
else
  fail "matching argv renders live even at 47h (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── 3. handle alive, unrelated argv, row MID_AGE → live (signal-2 fallback) ─
NEW_SB
_ledger "$SIG" "$ARM" "$H" "$MID_AGE"
_run    "$H" "$ARM" "running" "0" "$MID_AGE"
out="$(run_ps "$PS_UNRELATED")"
if [ "$(live_count "$out")" = "1" ] && sig_live "$SIG" "$out"; then
  pass "unrelated argv + mid-age row renders live (signal-2 fresh fallback)"
else
  fail "unrelated argv + mid-age row renders live (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── 4. handle pid ABSENT from snapshot, row 47h old → dead ─────────────────
NEW_SB
_ledger "$SIG" "$ARM" "$H" "$HOURS47"
_run    "$H" "$ARM" "running" "0" "$HOURS47"
# snapshot lists some OTHER pid only -- $$ is alive to os.kill but unidentifiable
PS_OTHER="$(printf '  %s /usr/bin/sleep 1\n' "1")"
out="$(run_ps "$PS_OTHER")"
if [ "$(live_count "$out")" = "0" ] && ! has_live_marker "$out"; then
  pass "absent-from-snapshot handle is NOT live"
else
  fail "absent-from-snapshot handle is NOT live (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── 5. identity-only (HANDLE_TRUST_S=0): mid-age unrelated no longer saves ─
NEW_SB
_ledger "$SIG" "$ARM" "$H" "$MID_AGE"
_run    "$H" "$ARM" "running" "0" "$MID_AGE"
out="$(
  LEADV2_STATUS_HANDLE_TRUST_S=0 \
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_PS_SNAPSHOT="$PS_UNRELATED" \
  bash "$RENDER"
)"
if [ "$(live_count "$out")" = "0" ] && ! has_live_marker "$out"; then
  pass "HANDLE_TRUST_S=0 disables fresh fallback (strict identity)"
else
  fail "HANDLE_TRUST_S=0 disables fresh fallback (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

log "---- $PASS passed, $FAIL failed ----"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
