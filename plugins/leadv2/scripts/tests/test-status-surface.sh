#!/usr/bin/env bash
# tests/test-status-surface.sh — SUPERVISOR-STATUS-SURFACE-02 DoD test.
#
# Harness style of test-acceptance-shape.sh: set -uo pipefail, PASS/FAIL
# counters, lv2_mktemp_dir sandbox, exit 1 if FAIL>0.
#
# Every source is env-injected: all 5 LEADV2_STATUS_* vars (plus HOME) point at
# a throwaway sandbox, so this NEVER touches the real ~/.claude. The renderer is
# read-only, so we additionally assert no symlink appears in the sandbox after a
# run (R1: rendering must not mutate a worktree's symlink set).
#
# Run: bash plugins/leadv2/scripts/tests/test-status-surface.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="${SCRIPT_DIR}/leadv2-status-surface.sh"
WATCH="${SCRIPT_DIR}/leadv2-status-watch.sh"
BAR="${SCRIPT_DIR}/leadv2-status-surface.10s.sh"
SELF="${BASH_SOURCE[0]}"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

# ── 1. bash -n on all 3 new scripts + the test itself ───────────────────────
for f in "$RENDER" "$WATCH" "$BAR" "$SELF"; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n $(basename "$f")"; else fail "bash -n $(basename "$f")"; fi
done

# frozen clock for deterministic mtimes/ages
NOW="${NOW:-$(date +%s)}"
export NOW

# portable mtime setter: _setage <path> <seconds-old> (relative to $NOW)
_setage() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, off = sys.argv[1], int(sys.argv[2])
now = int(os.environ.get("NOW", "0") or time.time())
t = max(0, now - off)
os.utime(path, (t, t))
PY
}

# ── fresh sandbox builder ──────────────────────────────────────────────────
# globals: SB (root), STATE_DIR, LEDGER_DIR, RUNS_ROOT, LEDGER
NEW_SB() {
  SB="$(lv2_mktemp_dir ss-surface)"
  STATE_DIR="${SB}/state"
  LEDGER_DIR="${SB}/dispatch-ledger"
  RUNS_ROOT="${SB}/cache"
  mkdir -p "$STATE_DIR" "$LEDGER_DIR" "$RUNS_ROOT"
  LEDGER="${LEDGER_DIR}/testrepo.jsonl"
  : > "$LEDGER"
}
# run the renderer against the current sandbox (default mode unless $1=--oneline)
# NOTE: we deliberately do NOT override HOME here. The 5 LEADV2_STATUS_* vars
# fully sandbox EVERY path the renderer reads (HOME is only consulted as a
# default when one of them is UNSET — and we set all five), so the real
# ~/.claude is never touched. Forcing HOME to the sandbox would additionally
# strip the user-site `yaml` module from python's sys.path on this host
# (PyYAML lives under ~), silently degrading every session-row test into the
# "active.yaml unreadable" warn path. The 5-var wall is the real isolation.
run_render() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  bash "$RENDER" "$@"
}
# append a ledger row: _ledger <sig8> <arm> <handle> <state> <created_epoch>
_ledger() {
  printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"%s","handle":"%s","created_epoch":%s}\n' \
    "$1" "$2" "$4" "$3" "$5" >> "$LEDGER"
}
# write a provider run dir: _run <handle> <arm> <status> <exit_code> [journal_off]
_run() {
  local h="$1" arm="$2" st="$3" ec="$4" off="${5:-0}"
  local d="${RUNS_ROOT}/${arm}-runs/${h}"
  mkdir -p "$d"
  if [ "$st" != "NONE" ]; then
    printf 'status: %s\nexit_code: %s\nmodel: glm-5.2\npid: 0\nstarted_at: 2026-07-31T00:00:00Z\n' "$st" "$ec" > "${d}/meta.yaml"
  fi
  : > "${d}/journal.jsonl"
  [ "$off" -gt 0 ] && _setage "${d}/journal.jsonl" "$off"
}

# ── 2. live lane: session pid=$$ renders live ──────────────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: liveabcd1234
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    started_at: '2026-07-31T18:00:00Z'
    last_pulse_at: '2026-07-31T18:00:00Z'
    log_path: ''
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'liveabcd.*live$'; then
  pass "live lane renders live"
else
  fail "live lane renders live (got: $(printf '%s' "$out" | tail -1))"
fi
# R1: no symlink appeared in the sandbox
if find "$SB" -type l 2>/dev/null | grep -q .; then
  fail "R1: symlink appeared in sandbox (render must be read-only)"
else
  pass "R1: no symlink mutation"
fi

# ── 3. dead-with-exit: meta exit_code 76, journal 20m, dead pid ────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: deadexit76abcd
    phase: build
    class: Standard
    pid: 999999
    lead_model: glm
    log_path: ''
EOF
_ledger deadexit glm deadd76 confirmed $((NOW-1200))
_run deadd76 glm failed 76 1200
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'deadexit.*dead(exit=76)'; then
  pass "dead-with-exit renders dead(exit=76)"
else
  fail "dead-with-exit renders dead(exit=76) (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 4. stale: no meta, journal 14m old, no pid ─────────────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
_ledger stale001 glm stale-h confirmed $((NOW-840))
_run stale-h glm NONE 0 840
rm -f "${RUNS_ROOT}/glm-runs/stale-h/meta.yaml" 2>/dev/null || true
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'stale001.*stale(14m silent)'; then
  pass "stale renders stale(14m silent)"
else
  fail "stale renders stale(14m silent) (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 5. no sentinel -> supervisor: OFF and no "?" ───────────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -q '^supervisor: OFF'; then
  pass "no sentinel -> supervisor: OFF"
else
  fail "no sentinel -> supervisor: OFF (got: $(printf '%s' "$out" | sed -n '1p'))"
fi
if printf '%s\n' "$out" | grep -q '?'; then
  fail "output contains a bare '?'"
else
  pass "output has no bare '?'"
fi

# ── 5b. supervisor ON: sentinel pid=$$, fresh heartbeat ───────────────────
NEW_SB
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 12
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -q "^supervisor: ON  pid=$$  beat"; then
  pass "supervisor ON with beat age"
else
  fail "supervisor ON with beat age (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# ── 5c. stale sentinel: dead pid -> OFF (stale sentinel...) ────────────────
NEW_SB
printf 'pid 999999\n' > "${STATE_DIR}/.supervise-active"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -q '^supervisor: OFF  (stale sentinel'; then
  pass "stale sentinel -> OFF (stale sentinel, pid gone)"
else
  fail "stale sentinel -> OFF (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# ── 6. terminal row aged 3h dropped; same at 10m present ───────────────────
# 3h case: absent
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: termrow01abcd
    phase: build
    class: Standard
    pid: 999999
    log_path: ''
EOF
_ledger termrow0 glm term-h confirmed $((NOW-10800))
_run term-h glm complete 0 10800
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'termrow'; then
  fail "terminal row aged 3h should be dropped"
else
  pass "terminal row aged 3h dropped"
fi
# 10m case: present as done(exit=0)
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: termrow01abcd
    phase: build
    class: Standard
    log_path: ''
EOF
_ledger termrow0 glm term-h confirmed $((NOW-600))
_run term-h glm complete 0 600
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'termrow.*done(exit=0)'; then
  pass "terminal row aged 10m present as done(exit=0)"
else
  fail "terminal row aged 10m present (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 7. non-terminal row aged 3h still present as stale ─────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: liveunkw0abcd
    phase: build
    class: Standard
    log_path: ''
EOF
_ledger liveunkw glm liveunk-h confirmed $((NOW-10800))
_run liveunk-h glm NONE 0 10800
rm -f "${RUNS_ROOT}/glm-runs/liveunk-h/meta.yaml" 2>/dev/null || true
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'liveunkw.*stale(3h silent)'; then
  pass "non-terminal row aged 3h present as stale"
else
  fail "non-terminal row aged 3h present as stale (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 8. --oneline shape: 1 line, ^sup:(ON|OFF), contains "lanes " ───────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: oneln001abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
out="$(run_render --oneline)"
nlines="$(printf '%s\n' "$out" | grep -c .)"
if [ "$nlines" -eq 1 ] \
   && printf '%s' "$out" | grep -q '^sup:\(ON\|OFF\)' \
   && printf '%s' "$out" | grep -q 'lanes '; then
  pass "--oneline shape (1 line, sup:, lanes)"
else
  fail "--oneline shape (got ${nlines} lines: ${out})"
fi

# ── 9. grep the 3 new scripts for [[ -> zero occurrences ───────────────────
bad=0
for f in "$RENDER" "$WATCH" "$BAR"; do
  if grep -q '\[\[' "$f"; then bad=$((bad+1)); fi
done
if [ "$bad" -eq 0 ]; then
  pass "no [[ in any new script"
else
  fail "found [[ in ${bad} script(s)"
fi

# ── 10. timing: renderer on the sandbox < 500 ms wall ──────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: timetest0abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
s="$(python3 -c 'import time;print(int(time.time()*1000))')"
run_render >/dev/null
e="$(python3 -c 'import time;print(int(time.time()*1000))')"
elapsed=$(( e - s ))
if [ "$elapsed" -lt 500 ]; then
  pass "renderer < 500ms wall (${elapsed}ms)"
else
  fail "renderer < 500ms wall (${elapsed}ms)"
fi

# ── bonus: SwiftBar line-1 shape ───────────────────────────────────────────
NEW_SB
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: barln0001abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
barout="$(LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  bash "$BAR" 2>/dev/null)"
if printf '%s\n' "$barout" | sed -n '1p' | grep -Eq '🟢 [0-9]+ / 🔴 [0-9]+'; then
  pass "SwiftBar line-1 emoji summary"
else
  fail "SwiftBar line-1 emoji summary (got: $(printf '%s' "$barout" | sed -n '1p'))"
fi
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
baroff="$(LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  bash "$BAR" 2>/dev/null)"
if printf '%s\n' "$baroff" | sed -n '1p' | grep -q '⚪ sup OFF'; then
  pass "SwiftBar sup-OFF prefix"
else
  fail "SwiftBar sup-OFF prefix (got: $(printf '%s' "$baroff" | sed -n '1p'))"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
