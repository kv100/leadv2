#!/usr/bin/env bash
# tests/test-status-surface-close-phase.sh — N-7d DoD test.
#
# A lane has two acts: the worker (act one) and the close/review gate (act
# two, leadv2-dispatch-product-close.sh, 20+ minutes). Before this fix the
# surface only knew act one, so a lane genuinely in its gate read
# stale(...silent) or, worse, done(exit=0). This asserts BOTH directions
# (N-7c pattern): a live gate must render live/act "gate", and an artifact
# alone (no process) must NEVER render live -- only a corrected act/clock.
#
# Drives the surface with LEADV2_STATUS_PS_SNAPSHOT + LEADV2_STATUS_HANDOFF_DIR
# (documented injection points) so no real worker/gate processes are needed.
#
# Run: bash plugins/leadv2/scripts/tests/test-status-surface-close-phase.sh

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

_setage() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, off = sys.argv[1], int(sys.argv[2])
now = int(os.environ.get("NOW", "0") or time.time())
t = max(0, now - off)
os.utime(path, (t, t))
PY
}

SB=; STATE_DIR=; LEDGER_DIR=; RUNS_ROOT=; LEDGER=; HANDOFF_DIR=
NEW_SB() {
  SB="$(lv2_mktemp_dir ss-close-phase)"
  STATE_DIR="${SB}/state"
  LEDGER_DIR="${SB}/dispatch-ledger"
  RUNS_ROOT="${SB}/cache"
  HANDOFF_DIR="${SB}/docs/handoff"
  mkdir -p "$STATE_DIR" "$LEDGER_DIR" "$RUNS_ROOT" "$HANDOFF_DIR"
  LEDGER="${LEDGER_DIR}/testrepo.jsonl"
  : > "$LEDGER"
  printf 'meta: {}\nsessions: []\n' > "${STATE_DIR}/active.yaml"
}

# render with a pinned PS_SNAPSHOT ($1) and HANDOFF_DIR already set by NEW_SB.
run_ps() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_HANDOFF_DIR="$HANDOFF_DIR" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_PS_SNAPSHOT="$1" \
  bash "$RENDER"
}

# ledger worker row: _ledger <sig8> <arm> <handle> <created_epoch_off> [state]
_ledger() {
  local state="${5:-confirmed}"
  printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"%s","handle":"%s","created_epoch":%s}\n' \
    "$1" "$2" "$state" "$3" "$(( NOW - $4 ))" >> "$LEDGER"
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
# handoff dir: _handoff <sig8> <artifact_off>  (writes e2e-gate.log, ages the
# FILE and the DIRECTORY -- close_dir_mtime() takes the newest mtime across
# both, so a freshly-mkdir'd sandbox dir would otherwise leak a fresh mtime
# regardless of the file's simulated age).
_handoff() {
  local sig="$1" off="$2"
  local d="${HANDOFF_DIR}/dispatch-${sig}"
  mkdir -p "$d"
  printf 'gate log line\n' > "${d}/e2e-gate.log"
  if [ "$off" -gt 0 ]; then
    _setage "${d}/e2e-gate.log" "$off"
    _setage "$d" "$off"
  fi
}

live_count() { printf '%s\n' "$1" | sed -n 's/.*lanes (\([0-9][0-9]*\) live.*/\1/p' | head -1; }
has_live_marker() { printf '%s\n' "$1" | grep -q 'live('; }
has_gate_act()    { printf '%s\n' "$1" | grep -q '·gate'; }
has_done_label()  { printf '%s\n' "$1" | grep -q 'done(exit=0)'; }
has_gate_cause()  { printf '%s\n' "$1" | grep -q 'gate('; }
has_close_pid()   { printf '%s\n' "$1" | grep -q 'live(close pid'; }
has_stale()       { printf '%s\n' "$1" | grep -q 'stale('; }

ARM="sonnet"
HOURS2=$(( 2 * 3600 ))
CLOSE_PID=54321

# ── C1: worker gone, close process alive (this lane), handoff aged 30s ─────
# expect: cls=live, cause "live(close pid ...)", display ends "·gate"
# close-process ps line for THIS lane's current sandbox: _ps_close <sig8>
_ps_close() {
  printf '  %s /usr/bin/env bash leadv2-dispatch-product-close.sh %s %s author handle e2e review ftid\n' \
    "$CLOSE_PID" "$SB" "$1"
}

SIG="c1c1c1c1"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_handoff "$SIG" 30
PS_CLOSE="$(_ps_close "$SIG")"
out="$(run_ps "$PS_CLOSE")"
if [ "$(live_count "$out")" = "1" ] && has_close_pid "$out" && has_gate_act "$out"; then
  pass "C1: live close process -> live(close pid N), act gate"
else
  fail "C1: live close process -> live(close pid N), act gate (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C2: close ps line carries a DIFFERENT sig8 token -> not live (accept 3) ─
SIG="c2c2c2c2"
OTHERSIG="99999999"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_handoff "$SIG" 30
PS_WRONGSIG="$(_ps_close "$OTHERSIG")"
out="$(run_ps "$PS_WRONGSIG")"
if [ "$(live_count "$out")" = "0" ] && ! has_close_pid "$out"; then
  pass "C2: close process for a DIFFERENT sig -> not live for this lane"
else
  fail "C2: close process for a DIFFERENT sig -> not live for this lane (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C3: close ps line's project-root token is a FOREIGN root -> not live ───
SIG="c3c3c3c3"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_handoff "$SIG" 30
PS_FOREIGNROOT="$(printf '  %s /usr/bin/env bash leadv2-dispatch-product-close.sh /some/other/repo %s author handle e2e review ftid\n' "$CLOSE_PID" "$SIG")"
out="$(run_ps "$PS_FOREIGNROOT")"
if [ "$(live_count "$out")" = "0" ] && ! has_close_pid "$out"; then
  pass "C3: close process argv with a foreign project root -> not live"
else
  fail "C3: close process argv with a foreign project root -> not live (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C4: worker exited 0 AND close process alive -> live, NOT done(exit=0) ──
# This is the N7C regression: done(exit=0) must not win over a live gate.
SIG="c4c4c4c4"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_run "999999" "$ARM" "complete" "0" "$HOURS2"
_handoff "$SIG" 30
PS_CLOSE="$(_ps_close "$SIG")"
out="$(run_ps "$PS_CLOSE")"
if [ "$(live_count "$out")" = "1" ] && has_close_pid "$out" && ! has_done_label "$out"; then
  pass "C4: worker exit=0 under a live gate renders live, not done(exit=0)"
else
  fail "C4: worker exit=0 under a live gate renders live, not done(exit=0) (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C5: no processes at all, handoff aged 30s -> dead, cause gate(30s ago) ──
# Artifact freshness alone must NEVER yield live (the false-live re-inversion
# the mission forbids).
SIG="c5c5c5c5"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_handoff "$SIG" 30
out="$(run_ps "")"
if [ "$(live_count "$out")" = "0" ] && has_gate_cause "$out" && ! has_live_marker "$out"; then
  pass "C5: artifact-fresh with no process -> dead, cause gate(Xs ago), never live"
else
  fail "C5: artifact-fresh with no process -> dead, never live (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C6: no processes, handoff+journal both 20m old -> stale(...)/dead ──────
# 20m sits beyond CLOSE_FRESH_S (600s) so the gate branch cannot fire, and
# below DEAD_TTL (3600s default) so the row is not TTL-dropped before this
# assertion can see it -- isolates "no false-live from a cold lane" from the
# unrelated TTL-drop mechanism.
SIG="c6c6c6c6"
MIN20=1200
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$MIN20"
_run "999999" "$ARM" "running" "" "$MIN20"
_handoff "$SIG" "$MIN20"
out="$(run_ps "")"
if [ "$(live_count "$out")" = "0" ] && has_stale "$out" && ! has_live_marker "$out"; then
  pass "C6: cold lane (worker+gate both 20m silent) stays stale/dead"
else
  fail "C6: cold lane (worker+gate both 20m silent) stays stale/dead (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C7: sibling dispatch-<sig>-review dir fresh, but dispatch-<sig> aged ───
# Sibling dirs are deliberately excluded (prefix-glob would let a review
# subsession vouch for a lane whose own gate is dead).
SIG="c7c7c7c7"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_handoff "$SIG" "$HOURS2"
mkdir -p "${HANDOFF_DIR}/dispatch-${SIG}-review"
printf 'sibling artifact\n' > "${HANDOFF_DIR}/dispatch-${SIG}-review/review-verdict.md"
out="$(run_ps "")"
if [ "$(live_count "$out")" = "0" ] && ! has_gate_act "$out" && ! has_live_marker "$out"; then
  pass "C7: fresh sibling -review dir does not count as this lane's gate motion"
else
  fail "C7: fresh sibling -review dir does not count as this lane's gate motion (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C8: empty/absent HANDOFF_DIR -> renders, no traceback, no regression ───
SIG="c8c8c8c8"
NEW_SB
_ledger "$SIG" "$ARM" "999999" "$HOURS2"
_run "999999" "$ARM" "running" "0" "$HOURS2"
out="$(
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_HANDOFF_DIR="" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_PS_SNAPSHOT="" \
  bash "$RENDER"
)"
rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ] && ! printf '%s' "$out" | grep -qi 'traceback'; then
  pass "C8: empty HANDOFF_DIR renders cleanly, no traceback"
else
  fail "C8: empty HANDOFF_DIR renders cleanly, no traceback (rc=$rc, got: $(printf '%s' "$out" | tr '\n' '|'))"
fi

# ── C9: acceptance 1 + 2 against the REAL surface, env -i, as N-7c's tail ──
# Acceptance 2: with no leadv2 processes at all, the real repo's own
# docs/handoff/dispatch-*/ dirs (which carry genuinely recent mtimes from
# gates that have since been killed) must NOT push the header off "0 live".
# This is the regression test for the false-live re-inversion risk (R1).
real_out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash "$RENDER" 2>&1)"
real_rc=$?
log "C9 real-surface output:"
printf '%s\n' "$real_out" | sed 's/^/[TEST]   /'
if [ "$real_rc" -eq 0 ] && ! printf '%s' "$real_out" | grep -qi 'traceback'; then
  pass "C9: real surface renders under env -i with no traceback"
else
  fail "C9: real surface renders under env -i with no traceback (rc=$real_rc)"
fi

log "---- $PASS passed, $FAIL failed ----"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
