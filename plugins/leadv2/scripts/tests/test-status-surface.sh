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
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${TASKS_YAML:-${SB}/tasks.yaml}" \
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
# STATUS-SURFACE-R5-01: the SIG column is now its own last field, so name-first
# grep patterns no longer work. sig_has <sig8> <cause_substr> <output> succeeds
# when the rendered row whose LAST whitespace field == sig also contains the
# literal cause substring. cause is matched with index() (literal, regex-safe).
sig_has() { printf '%s\n' "$3" | awk -v s="$1" -v c="$2" 'index($0,c)&&$NF==s{f=1} END{exit !f}'; }
# sig_seen <sig8> <output>: any row whose last field == sig (presence/absence).
sig_seen() { printf '%s\n' "$2" | awk -v s="$1" '$NF==s{f=1} END{exit !f}'; }

# ── sandbox-leak guard (verify-notes §7): the suite's sentinel writes all use
# THIS process's pid ($$, e.g. `printf 'pid %s\n' "$$"`) and target the sandbox
# STATE_DIR. If any escaped to the REAL leadv2-state, a real .supervise-active
# would carry $$ as its pid. leadv2's own writers (supervise.sh:175, the
# PreToolUse snapshot hook) NEVER use this test bash's pid, so the presence of
# $$ in any real sentinel is an unambiguous, deterministic leak signature --
# stable against the live supervisor/hook churn that makes content/path/mtime
# fingerprints flaky on this machine. (Static proof the suite can't be the
# writer at all: the only .supervise-active writer in-tree is
# leadv2-supervise.sh:175, and the suite env-injects every path it reads.)
REAL_STATE="${HOME}/.claude/leadv2-state"
TEST_PID=$$

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
if sig_has liveabcd live "$out"; then
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
if sig_has deadexit 'dead(exit=76)' "$out"; then
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
# state=confirmed is now terminal (is_terminal), so a recent (<7200s)
# ledger-only terminal row reinterprets the last-resort stale() branch as
# done(confirmed) rather than stale. See round-2 fix C1/C2.
if sig_has stale001 'done(confirmed)' "$out"; then
  pass "recent terminal confirmed renders done(confirmed)"
else
  fail "recent terminal confirmed renders done(confirmed) (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 4a/T21. ledger-only confirmed @ 17h -> DROPPED (old terminal ages out) ─
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
_ledger dropcnf1 glm drop-h confirmed $((NOW-61200))
out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'dropcnf1'; then
  fail "T21: old(17h) terminal confirmed row should be dropped (got: $(printf '%s' "$out" | tail -1))"
else
  pass "T21: old(17h) terminal confirmed row dropped"
fi

# ── 4b/T22. ledger-only confirmed @ 1h -> done(confirmed), NOT stale ───────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
_ledger donecnf1 glm done-h confirmed $((NOW-300))
out="$(run_render)"
if sig_has donecnf1 'done(confirmed)' "$out"; then
  pass "T22: recent(1h) confirmed renders done(confirmed)"
else
  fail "T22: recent(1h) confirmed renders done(confirmed) (got: $(printf '%s' "$out" | tail -1))"
fi
if sig_seen donecnf1 "$out" && printf '%s\n' "$out" | grep -q 'stale('; then
  fail "T22: recent(1h) confirmed must not render stale (got: $(printf '%s' "$out" | tail -1))"
else
  pass "T22: recent(1h) confirmed not labelled stale"
fi

# ── 4c/T23. ledger-only PENDING @ 17h -> still stale (non-terminal never drops)
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
_ledger pendcnf1 glm pend-h pending $((NOW-61200))
out="$(run_render)"
if sig_seen pendcnf1 "$out"; then
  fail "T23: old(17h) pending should drop after dead-TTL (got: $(printf '%s' "$out" | tail -1))"
else
  pass "T23: old(17h) pending dropped after dead-TTL (non-terminal stale still ages out)"
fi

# ── 5. no sentinel, no heartbeat -> supervisor: OFF (+reason, never bare) ──
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
# SUP-OFF-IS-A-LIE-01 D4: a bare `supervisor: OFF` with no reason must NEVER
# render. The line must carry a parenthetical reason.
if printf '%s\n' "$out" | grep -Eq '^supervisor: OFF +\('; then
  pass "no-sentinel OFF carries a reason"
else
  fail "no-sentinel OFF is bare / has no reason (got: $(printf '%s' "$out" | sed -n '1p'))"
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
if printf '%s\n' "$out" | grep -Eq "^supervisor: ON +\\(pid $$, beat"; then
  pass "supervisor ON with beat age"
else
  fail "supervisor ON with beat age (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# ── 5c. stale sentinel: dead pid -> STALE (not OFF) ───────────────────────
# SUP-OFF-IS-A-LIE-01 D4: the founder must read STALE — not OFF — when a
# sentinel's pid is gone, so the three worlds stay distinguishable.
NEW_SB
printf 'pid 999999\n' > "${STATE_DIR}/.supervise-active"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: STALE +\(sentinel pid 999999 gone'; then
  pass "stale sentinel -> STALE (pid gone)"
else
  fail "stale sentinel -> STALE (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# ── SUP-OFF-IS-A-LIE-01 T-A..T-F: heartbeat-primary truth table ────────────
# These FAIL on the pre-fix reader (which gated everything on the sentinel and
# rendered a bare OFF whenever the sentinel was absent). Each seeds exactly
# the files the named row needs and asserts the rendered long form.
#
# T-A (the red test): fresh heartbeat, NO sentinel -> ON, mentioning "no
# sentinel". Pre-fix rendered `supervisor: OFF`.
NEW_SB
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 30
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: ON' \
   && printf '%s\n' "$out" | grep -q 'no sentinel'; then
  pass "T-A: fresh beat, no sentinel -> ON (heartbeat only)"
else
  fail "T-A: fresh beat, no sentinel -> ON (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-B: heartbeat aged 3h, no sentinel -> STALE, NOT starting with OFF.
NEW_SB
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 10800
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: STALE' \
   && ! printf '%s\n' "$out" | grep -Eq '^supervisor: OFF'; then
  pass "T-B: old beat, no sentinel -> STALE (not OFF)"
else
  fail "T-B: old beat, no sentinel -> STALE (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-C: neither file -> OFF, and the line carries a reason (bare OFF never
# renders). Pre-fix rendered a bare `supervisor: OFF`.
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: OFF +\('; then
  pass "T-C: nothing -> OFF with a reason (never bare)"
else
  fail "T-C: nothing -> OFF with a reason (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-D: sentinel with dead pid 999999 + fresh heartbeat -> ON, naming the gone
# pid. Pre-fix rendered STALE (the live beat was invisible inside the sentinel
# gate).
NEW_SB
printf 'pid 999999\n' > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 41
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: ON' \
   && printf '%s\n' "$out" | grep -q 'sentinel pid 999999 gone'; then
  pass "T-D: dead-pid sentinel + fresh beat -> ON"
else
  fail "T-D: dead-pid sentinel + fresh beat -> ON (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-D2: unparsable sentinel (no pid digits) + OLD heartbeat -> STALE naming the
# beat age, NOT "no beat" (Codex review fix: the unparsable branch must honour
# SUP_BEAT_AGE_SECS just like the dead-pid branch).
NEW_SB
printf '{"mode":"x"}\n' > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
_setage "${STATE_DIR}/.supervise-loop.heartbeat" 7200
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: STALE' \
   && printf '%s\n' "$out" | grep -q 'beat 2h old' \
   && ! printf '%s\n' "$out" | grep -q 'unparsable, no beat'; then
  pass "T-D2: unparsable sentinel + old beat -> STALE (beat age, not 'no beat')"
else
  fail "T-D2: unparsable + old beat (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-E: legacy docs/leadv2/.supervise-active present, canonical absent, no
# heartbeat -> STALE mentioning "legacy".
NEW_SB
mkdir -p "${SB}/docs/leadv2"
printf 'pid 55555\n' > "${SB}/docs/leadv2/.supervise-active"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
out="$(run_render)"
if printf '%s\n' "$out" | grep -Eq '^supervisor: STALE' \
   && printf '%s\n' "$out" | grep -q 'legacy'; then
  pass "T-E: legacy sentinel, canonical absent, no beat -> STALE (legacy)"
else
  fail "T-E: legacy -> STALE (got: $(printf '%s' "$out" | sed -n '1p'))"
fi

# T-F (writer parity): leadv2-supervise.sh and leadv2-status-surface.sh must
# resolve the SAME sentinel path for a given sandboxed control plane, so the
# writer/reader split that caused this bug cannot recur. We sandbox both via
# LEADV2_STATE_ROOT and compare the resolved strings.
NEW_SB
mkdir -p "${SB}/.git"
SENT_WRITER="$(PROJECT_ROOT="$SB" LEADV2_STATE_ROOT="${SB}/state" \
  bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link .supervise-active 2>/dev/null || true)"
SENT_READER="$(PROJECT_ROOT="$SB" LEADV2_STATE_ROOT="${SB}/state" \
  bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root 2>/dev/null || true)"
SENT_READER="${SENT_READER}/.supervise-active"
if [ -n "$SENT_WRITER" ] && [ "$SENT_WRITER" = "$SENT_READER" ]; then
  pass "T-F: writer and reader resolve the same sentinel path (${SENT_WRITER})"
else
  fail "T-F: writer/reader path split (writer=${SENT_WRITER} reader=${SENT_READER})"
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
if sig_has termrow0 'done(exit=0)' "$out"; then
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
_ledger liveunkw glm liveunk-h pending $((NOW-1800))
_run liveunk-h glm NONE 0 1800
rm -f "${RUNS_ROOT}/glm-runs/liveunk-h/meta.yaml" 2>/dev/null || true
out="$(run_render)"
if sig_has liveunkw 'stale(30m silent)' "$out"; then
  pass "non-terminal row aged 30m present as stale (within dead-TTL)"
else
  fail "non-terminal row aged 30m present as stale (got: $(printf '%s' "$out" | tail -1))"
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
   && printf '%s' "$out" | grep -q '^sup:\(ON\|OFF\|STALE\)' \
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
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
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
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$BAR" 2>/dev/null)"
if printf '%s\n' "$baroff" | sed -n '1p' | grep -q '⚪ sup OFF'; then
  pass "SwiftBar sup-OFF prefix"
else
  fail "SwiftBar sup-OFF prefix (got: $(printf '%s' "$baroff" | sed -n '1p'))"
fi

# ── 11/R1. name resolution: tasks.yaml id -> external_id shown ─────────────
NEW_SB
cat > "${SB}/tasks.yaml" <<EOF
total_open: 1
tasks:
- id: nameabcd1234
  external_id: ALERTS-TO-LEAD-01
  node_id: leadv2:ALERTS-TO-LEAD-01
EOF
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: nameabcd1234
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
TASKS_YAML="${SB}/tasks.yaml" out="$(run_render)"
if printf '%s\n' "$out" | grep -q 'ALERTS-TO-LEAD-01'; then
  pass "R1: tasks.yaml id resolves to human name"
else
  fail "R1: name resolution (got: $(printf '%s' "$out" | tail -1))"
fi
# last-resort fallback still embeds sig8 (no bare hash column can appear)
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: lastres01abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
out="$(run_render)"
if sig_seen lastres0 "$out" && printf '%s\n' "$out" | grep -q 'unnamed'; then
  pass "R1: last-resort name is 'unnamed', sig in SIG column (no hash dressed as name)"
else
  fail "R1: last-resort name (got: $(printf '%s' "$out" | tail -1))"
fi

# ── 12/R2. TYPE column: lane (session) vs worker (ledger-only) ─────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: lane0001abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
_ledger workr001 glm work-h confirmed $((NOW-300))
out="$(run_render)"
if printf '%s\n' "$out" | awk '$NF=="lane0001"&&$2=="lane"' | grep -q . \
   && printf '%s\n' "$out" | awk '$NF=="workr001"&&$2=="worker"' | grep -q .; then
  pass "R2: TYPE column lane vs worker"
else
  fail "R2: TYPE column (got: $(printf '%s' "$out" | tail -3 | tr '\n' '|'))"
fi

# ── 13/R3. >10 terminal rows collapse to 10 + one summary line ─────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  _ledger "$(printf 'colp%04d' "$i")" glm "c$i-h" confirmed $((NOW-300-i))
done
out="$(run_render)"
done_n="$(printf '%s\n' "$out" | grep -c 'done(confirmed)')"
if printf '%s\n' "$out" | grep -q '+ 3 done earlier today' && [ "$done_n" -eq 10 ]; then
  pass "R3: 13 done rows -> 10 + '+ 3 done earlier today'"
else
  fail "R3: collapse (done rows=${done_n}, got: $(printf '%s' "$out" | tail -2 | tr '\n' '|'))"
fi

# ── 13b/R3. live + stale rows are NEVER collapsed ─────────────────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: liveone0abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  _ledger "$(printf 'stly%04d' "$i")" glm "s$i-h" pending $((NOW-300-i))
done
out="$(run_render)"
if sig_seen liveone0 "$out" \
   && [ "$(printf '%s\n' "$out" | grep -c 'stale(')" -eq 12 ]; then
  pass "R3: live + non-terminal stale rows never collapsed"
else
  fail "R3: no-collapse of live/stale (got: $(printf '%s' "$out" | tail -3 | tr '\n' '|'))"
fi

# ── 14/R4. --oneline contains 'live' when a live lane exists ───────────────
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: oneliveabcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
out="$(run_render --oneline)"
if printf '%s' "$out" | grep -q 'live'; then
  pass "R4: oneline reports live lane"
else
  fail "R4: oneline live (got: $out)"
fi

# ── 15/§6. dash-leading name does not break the SwiftBar dropdown ─────────
NEW_SB
cat > "${SB}/tasks.yaml" <<EOF
total_open: 1
tasks:
- id: dashname0abcd
  external_id: '--dash-leading-name'
EOF
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: dashname0abcd
    phase: build
    class: Standard
    pid: $$
    lead_model: glm
    log_path: ''
EOF
TASKS_YAML="${SB}/tasks.yaml" barout="$(LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$BAR" 2>/dev/null)"
# the dash-leading row must still render as a well-formed dropdown line (printf
# '%s | font=...' -- never interpreted as a format string / option).
if printf '%s\n' "$barout" | grep -- '--dash-leading-name.*font=Menlo size=12'; then
  pass "§6: dash-leading name renders a well-formed dropdown line"
else
  fail "§6: dash-leading dropdown (got: $(printf '%s' "$barout" | grep -- '--dash' | head -1))"
fi

# ── sandbox-leak guard (verify-notes §7): the test's own pid must not appear
# in any real .supervise-active (would mean a sandboxed sentinel write escaped).
_leak_paths=""
while IFS= read -r _p; do
  [ -z "$_p" ] && continue
  if grep -Eq "(\"pid\"[[:space:]]*:[[:space:]]*|^pid[[:space:]+])${TEST_PID}([^0-9]|\$)" "$_p" 2>/dev/null; then
    _leak_paths="${_leak_paths}${_p}"$'\n'
  fi
done <<EOF
$(find "$REAL_STATE" -type f -name '.supervise-active' 2>/dev/null)
EOF
if [ -z "$_leak_paths" ]; then
  pass "sandbox-leak: real leadv2-state dir not written by suite (test pid $$ absent)"
else
  fail "sandbox-leak: test pid $$ found in a real sentinel (sandbox write escaped):
$_leak_paths"
fi

# ════════════════════════════════════════════════════════════════════════════
# ROUND 4 (2026-08-01): questions / limits / due / alarms sections + widget.
# Every round-4 source is env-injected (R4_* → LEADV2_STATUS_*); SD hook, codex
# lockout, urgent log, and limits snapshot all default to /nonexistent so NO
# round-4 test reads the founder's real ~/.claude state.
# ════════════════════════════════════════════════════════════════════════════

# round-4 renderer runner: full env isolation, all R4 sources defaulted off.
run_render_r4() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  LEADV2_STATUS_QUESTIONS_DIR="${R4_QDIR:-}" \
  LEADV2_STATUS_HANDOFF_DIR="${R4_HANDOFF:-}" \
  LEADV2_STATUS_LIMITS_SNAPSHOT="${R4_SNAP:-/nonexistent}" \
  LEADV2_STATUS_CODEX_LOCKOUT="${R4_CODEX:-/nonexistent}" \
  LEADV2_STATUS_SD_HOOK="${R4_SDHOOK:-/nonexistent}" \
  LEADV2_STATUS_URGENT_LOG="${R4_URGENT:-/nonexistent}" \
  bash "$RENDER" "$@"
}
# round-4 widget runner (same env wall). The widget re-invokes the renderer
# with --all, so the renderer inherits these vars.
run_bar_r4() {
  LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_REPO_ROOT="$SB" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  LEADV2_STATUS_QUESTIONS_DIR="${R4_QDIR:-}" \
  LEADV2_STATUS_HANDOFF_DIR="${R4_HANDOFF:-}" \
  LEADV2_STATUS_LIMITS_SNAPSHOT="${R4_SNAP:-/nonexistent}" \
  LEADV2_STATUS_CODEX_LOCKOUT="${R4_CODEX:-/nonexistent}" \
  LEADV2_STATUS_SD_HOOK="${R4_SDHOOK:-/nonexistent}" \
  LEADV2_STATUS_URGENT_LOG="${R4_URGENT:-/nonexistent}" \
  bash "$BAR" "$@"
}

# ── R4-T1. --questions: 1 CP pending + answered, 1 legacy pending + sibling-answered
NEW_SB
mkdir -p "${STATE_DIR}/questions"
R4_QDIR="${STATE_DIR}/questions"
R4_HANDOFF="${SB}/handoff"
mkdir -p "${R4_HANDOFF}/taskA/questions-async" "${R4_HANDOFF}/taskB/questions-async"
cat > "${R4_QDIR}/qPEND0001.yaml" <<EOF
status: pending
task_id: taskA
question: Should we restart the failed codex job?
options:
  - {label: restart, text: restart the task}
  - {label: wait, text: wait 10 min}
EOF
cat > "${R4_QDIR}/qANS0001.yaml" <<EOF
status: answered
task_id: taskA
question: already resolved
options: [{label: a, text: x}]
EOF
cat > "${R4_HANDOFF}/taskA/questions-async/qLEGPEND-pending.yaml" <<EOF
question: legacy pending question
options: [{label: yes, text: y}, {label: no, text: n}]
EOF
cat > "${R4_HANDOFF}/taskB/questions-async/qLEGANS-pending.yaml" <<EOF
question: legacy answered-by-sibling
options: [{label: go, text: g}]
EOF
: > "${R4_HANDOFF}/taskB/questions-async/qLEGANS-answered.yaml"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
qout="$(run_render_r4 --questions)"
if printf '%s\n' "$qout" | grep -q '^questions (2)$' \
   && printf '%s\n' "$qout" | grep -q '^qPEND0001 ' \
   && printf '%s\n' "$qout" | grep -q '^qLEGPEND ' \
   && ! printf '%s\n' "$qout" | grep -q 'qANS0001' \
   && ! printf '%s\n' "$qout" | grep -q 'qLEGANS'; then
  pass "R4-T1: --questions counts pending only (CP status + legacy sibling)"
else
  fail "R4-T1: --questions (got: $(printf '%s' "$qout" | tr '\n' '|'))"
fi
# option labels survive, | joined, no answered qid
if printf '%s\n' "$qout" | grep -q '\[restart|wait\]'; then
  pass "R4-T1: question options rendered [restart|wait]"
else
  fail "R4-T1: options (got: $(printf '%s' "$qout" | grep qPEND | tr '\n' '|'))"
fi

# ── R4-T2. widget title starts with ❓1 when exactly one question is pending
NEW_SB
mkdir -p "${STATE_DIR}/questions"
R4_QDIR="${STATE_DIR}/questions"
R4_HANDOFF=""
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${R4_QDIR}/qSOLO0001.yaml" <<EOF
status: pending
task_id: taskS
question: a single pending question
options: [{label: a, text: x}, {label: b, text: y}]
EOF
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
barout="$(run_bar_r4)"
if printf '%s\n' "$barout" | sed -n '1p' | grep -q '^❓1'; then
  pass "R4-T2: widget title is ❓1 with a pending question"
else
  fail "R4-T2: widget title ❓1 (got: $(printf '%s' "$barout" | sed -n '1p'))"
fi

# ── R4-T3. title priority: 1 pending question AND a dead lane -> ❓ wins over 🔴
NEW_SB
mkdir -p "${STATE_DIR}/questions"
R4_QDIR="${STATE_DIR}/questions"
R4_HANDOFF=""
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${R4_QDIR}/qDEAD01.yaml" <<EOF
status: pending
task_id: taskD
question: question alongside a dead lane
options: [{label: a, text: x}]
EOF
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
barout="$(run_bar_r4)"
if printf '%s\n' "$barout" | sed -n '1p' | grep -q '^❓1' \
   && ! printf '%s\n' "$barout" | sed -n '1p' | grep -q '^🔴'; then
  pass "R4-T3: ❓1 wins over 🔴 (question + dead lane)"
else
  fail "R4-T3: priority (got: $(printf '%s' "$barout" | sed -n '1p'))"
fi
# dead lane must actually be dead in this stub (sanity for the priority assertion)
bare="$(run_render_r4)"
if sig_has deadexit 'dead(exit=76)' "$bare"; then
  pass "R4-T3: sanity — dead lane renders dead(exit=76)"
else
  fail "R4-T3: sanity dead lane (got: $(printf '%s' "$bare" | tail -1))"
fi

# ── R4-T4. --limits: heuristic cap -> honest claude row (no fabricated %); glm
# unchanged. STATUS-SURFACE-R5-01 defect 3: the old row divided input tokens by
# a guessed 8M cap and printed a serene 0% at any load. While the heuristic cap
# is in use we print NO percentage -- only measured cache-read/output magnitudes.
NEW_SB
R4_SNAP="${SB}/snap.txt"
cat > "$R4_SNAP" <<EOF
# stamped $((NOW-30))
Quota: 5h 0% (12345 / 8000000 in, claude% only, cap est.) | weekly(claude,heuristic) 18% | cache-hit 0.91 | safe
  anthropic 5h: in 12.3K  cc 1.0M  cr 5.0M  out 500.0K  (99 turns)
  rate_limit:  not captured (heuristic cap in use) — kv hook: key=rate_limit_anthropic
  glm weekly (live, z.ai): 20%  (resets 2026-08-07T10:30:44Z)
EOF
limout="$(run_render_r4 --limits)"
if printf '%s\n' "$limout" | grep -q 'claude: не измеряется' \
   && printf '%s\n' "$limout" | grep -q 'cr 5.0M' \
   && ! printf '%s\n' "$limout" | grep -Eq 'claude: 5h [0-9]+%' \
   && printf '%s\n' "$limout" | grep -q 'glm: weekly 20% (snapshot, live z.ai)'; then
  pass "R4-T4: heuristic cap -> honest claude row, no fabricated %, glm unchanged"
else
  fail "R4-T4: --limits (got: $(printf '%s' "$limout" | tr '\n' '|'))"
fi
if printf '%s\n' "$limout" | grep -q '\$'; then
  fail "R4-T4: --limits contains a dollar sign"
else
  pass "R4-T4: --limits has no dollar amount"
fi
# Real rate-limit kv row (C3b consumer-compatible schema) -> measured % computed
# from unified_limit/unified_remaining: 1M limit, 250k remaining => 75% used.
if command -v sqlite3 >/dev/null 2>&1; then
  R4_DB="${SB}/burn.db"
  sqlite3 "$R4_DB" "CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY,value TEXT);" 2>/dev/null
  sqlite3 "$R4_DB" "INSERT OR REPLACE INTO kv VALUES('rate_limit_anthropic','{\"captured_epoch\":$((NOW-30)),\"status\":\"allowed\",\"overageStatus\":\"accepted\",\"resetsAt\":0,\"unified_limit\":1000000,\"unified_remaining\":250000,\"source\":\"messages_api_headers\"}');" 2>/dev/null
  limout2="$(LEADV2_STATUS_BURN_DB="$R4_DB" run_render_r4 --limits)"
  if printf '%s\n' "$limout2" | grep -Eq 'claude: 5h 75% \(rate-limit signal\)'; then
    pass "R4-T4: real rate-limit kv row -> measured 75% (750k of 1M used)"
  else
    fail "R4-T4: real % (got: $(printf '%s' "$limout2" | tr '\n' '|'))"
  fi
else
  pass "R4-T4: real-% sub-case SKIP (no sqlite3)"
fi
# stale stamp (older than 15 min) -> (stale Nm) suffix, shown not hidden
cat > "$R4_SNAP" <<EOF
# stamped $((NOW-1200))
Quota: 5h 5% (1 / 8000000 in, claude% only) | weekly(claude,heuristic) 2%
EOF
limout="$(run_render_r4 --limits)"
if printf '%s\n' "$limout" | sed -n '1p' | grep -q 'limits (stale'; then
  pass "R4-T4: stale snapshot stamp shown as (stale Nm)"
else
  fail "R4-T4: stale suffix (got: $(printf '%s' "$limout" | sed -n '1p'))"
fi

# ── R4-T5. --limits with snapshot absent -> 'no snapshot', exit 0
NEW_SB
R4_SNAP="/nonexistent-r4-no-snap"
limout="$(run_render_r4 --limits)"; rc=$?
if printf '%s\n' "$limout" | grep -q 'no snapshot' && [ "$rc" -eq 0 ]; then
  pass "R4-T5: absent snapshot -> 'no snapshot', exit 0"
else
  fail "R4-T5: absent snapshot (rc=$rc, got: $(printf '%s' "$limout" | tr '\n' '|'))"
fi

# ── R4-T6. --due: stub hook echoes a known count; hook not executable -> omit
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
R4_SDHOOK="${SB}/sdhook.sh"
cat > "$R4_SDHOOK" <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
import json
print(json.dumps({"additionalContext":"[OVERDUE] SD-1 - x\n[DUE TODAY] SD-2 - y\n[CONDITION-BOUND] SD-3 - z"}))
PY
EOF
chmod +x "$R4_SDHOOK"
dueout="$(run_render_r4 --due)"
if printf '%s' "$dueout" | grep -q '^due: 3 overdue: 1$'; then
  pass "R4-T6: --due counts 3 due / 1 overdue from hook JSON"
else
  fail "R4-T6: --due (got: $dueout)"
fi
# hook not executable -> no due: line, exit 0
R4_SDHOOK="${SB}/sdhook.sh.nox"
: > "$R4_SDHOOK"
dueout="$(run_render_r4 --due)"; rc=$?
if [ -z "$dueout" ] && [ "$rc" -eq 0 ]; then
  pass "R4-T6: non-executable hook -> due line omitted, exit 0"
else
  fail "R4-T6: omit (rc=$rc, got: '$dueout')"
fi

# ── R4-T7. bare invocation contract (STATUS-SURFACE-R5-01: header now carries
# live + recent-terminal counts). The empty stub renders the supervisor line,
# the new 'lanes (0 live, 0 done ...)' header, and the (none) placeholder.
NEW_SB
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions: []
EOF
bare="$(run_render_r4)"
expected='supervisor: OFF  (no sentinel, no heartbeat)
lanes (0 live, 0 done в последний час)
  (none)'
if [ "$bare" = "$expected" ]; then
  pass "R4-T7: bare invocation matches R5 header contract for empty stub"
else
  fail "R4-T7: bare drift (got: $(printf '%s' "$bare" | tr '\n' '|'))"
fi

# ── R4-T8. unknown flag -> usage to stderr, exit 2
NEW_SB
run_render_r4 --no-such-flag >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then
  pass "R4-T8: unknown flag exits 2"
else
  fail "R4-T8: unknown flag exit (rc=$rc)"
fi

# ── R6-T1. 2 done(exit=0) + 1 dead(exit=1) -> title 🔴 1, NOT 🔴 3 ──────────
# round-6 fix: done lanes must NOT be counted as dead. Supervisor ON (sentinel
# pid=$$) so line 1 carries no `⚪ sup OFF · ` prefix and anchors cleanly.
NEW_SB
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: done0001r6abcd
    phase: build
    class: Standard
    log_path: ''
  - task_id: done0002r6abcd
    phase: build
    class: Standard
    log_path: ''
  - task_id: dead0001r6abcd
    phase: build
    class: Standard
    pid: 999999
    lead_model: glm
    log_path: ''
EOF
_ledger done0001r glm done1-h confirmed $((NOW-600))
_run done1-h glm complete 0 600
_ledger done0002r glm done2-h confirmed $((NOW-590))
_run done2-h glm complete 0 590
_ledger dead0001r glm dead1-h confirmed $((NOW-1200))
_run dead1-h glm failed 1 1200
barout="$(LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$BAR" 2>/dev/null)"
_l1="$(printf '%s\n' "$barout" | sed -n '1p')"
if printf '%s' "$_l1" | grep -Eq '^🔴 1 ' && ! printf '%s' "$_l1" | grep -q '🔴 3'; then
  pass "R6-T1: 2 done + 1 dead -> 🔴 1 (got: $_l1)"
else
  fail "R6-T1: 2 done + 1 dead -> 🔴 1 (got: $_l1)"
fi

# ── R6-T2. only 2 done(exit=0) -> title ✅ 2 ────────────────────────────────
NEW_SB
printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"
: > "${STATE_DIR}/.supervise-loop.heartbeat"
cat > "${STATE_DIR}/active.yaml" <<EOF
meta: {}
sessions:
  - task_id: doneonly1abcd
    phase: build
    class: Standard
    log_path: ''
  - task_id: doneonly2abcd
    phase: build
    class: Standard
    log_path: ''
EOF
_ledger doneonly1 glm donly1-h confirmed $((NOW-600))
_run donly1-h glm complete 0 600
_ledger doneonly2 glm donly2-h confirmed $((NOW-590))
_run donly2-h glm complete 0 590
barout="$(LEADV2_STATUS_STATE_DIR="$STATE_DIR" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGER_DIR" \
  LEADV2_STATUS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_STATUS_REPO="testrepo" \
  LEADV2_STATUS_NOW="$NOW" \
  LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
  bash "$BAR" 2>/dev/null)"
_l1="$(printf '%s\n' "$barout" | sed -n '1p')"
if printf '%s' "$_l1" | grep -Eq '✅ 2'; then
  pass "R6-T2: only done -> ✅ 2 (got: $_l1)"
else
  fail "R6-T2: only done -> ✅ 2 (got: $_l1)"
fi

# ── R5-01 round 2: _mini_yaml unit tests (PyYAML-optional reader) ──────────
# The reader lives inside the renderer's lanes heredoc; extract it and exercise
# the leadv2 machine-written subset directly. The cross-reader equality case
# (mini vs PyYAML on a tasks.yaml fixture) is the assertion that keeps both
# readers honest; it SKIPS if PyYAML is not importable on the test host.
log ""
log "== R5r2: _mini_yaml reader unit cases =="
MiniFix="$(mktemp -d -t leadv2-ss-mini)"
cleanup_mini() { rm -rf "$MiniFix"; }
trap cleanup_mini EXIT 2>/dev/null || true
_minirc=0
LEADV2_R5_REN="$RENDER" LEADV2_R5_FIX="$MiniFix" python3 - <<'PY' || _minirc=$?
import os, re, pathlib, sys
ren = pathlib.Path(os.environ["LEADV2_R5_REN"]).read_text()
m = re.search(r"\ndef _mini_yaml\(text\):.*?(?=\n# ---- helpers)", ren, re.S)
if not m:
    print("FAIL: could not extract _mini_yaml from renderer"); sys.exit(1)
ns = {}; exec(m.group(0), ns); mini = ns["_mini_yaml"]
P = F = 0
def chk(name, cond):
    global P, F
    if cond: P += 1; print("  ok   - %s" % name)
    else:    F += 1; print("  FAIL - %s" % name)

# 1: empty sessions inline collection
chk("sessions: [] -> {sessions: []}", mini("sessions: []\n") == {"sessions": []})

# 2: two populated sessions; scalar keys present, quotes stripped, null/bool/int typed
doc = mini('''
meta:
  hard_limit: 5
  rendered_at: '2026-07-30T18:05:35Z'
sessions:
- session_id: abc
  task_id: verify-stub-1
  pid: 71401
  pid_birth: null
  daemon_mode: false
  branch: 'HEAD unknown'
- session_id: def
  task_id: verify-stub-2
  pid: null
  phase: spawning
''')
s = doc.get("sessions") or []
chk("two sessions parsed", isinstance(s, list) and len(s) == 2)
chk("scalar keys present", s[0].get("task_id") == "verify-stub-1")
chk("int typed", s[0].get("pid") == 71401)
chk("null typed", s[0].get("pid_birth") is None)
chk("bool typed", s[0].get("daemon_mode") is False)
chk("quotes stripped", s[0].get("branch") == "HEAD unknown")
chk("nested meta mapping", doc.get("meta", {}).get("hard_limit") == 5)

# 3: unsupported constructs raise (never a partial doc)
def raises(txt):
    try: mini(txt); return False
    except ValueError: return True
    except Exception: return False
chk("tab indent raises",      raises("meta:\n\tbad: 1\n"))
chk("populated flow raises",  raises("k: [a, b]\n"))
chk("unclosed quote raises",  raises("k: 'unclosed\n"))

# 4: cross-reader equality on a tasks.yaml fixture (titles map). SKIP if no PyYAML.
try:
    import yaml as _pyyaml
    fixture = os.path.join(os.environ["LEADV2_R5_FIX"], "tasks.yaml")
    pathlib.Path(fixture).write_text(
        "total_open: 2\n"
        "tasks:\n"
        "- id: STATUS-SURFACE-R5-01\n"
        "  title: 'STATUS-SURFACE-R5-01 round 2'\n"
        "  external_id: dispatch-d1c53811\n"
        "  node_id: 'leadv2:STATUS-SURFACE-R5-01'\n"
        "- id: OTHER-01\n"
        "  external_id: dispatch-abcdef01\n"
        "  node_id: 'leadv2:OTHER-01'\n"
    )
    ref = _pyyaml.safe_load(open(fixture)) or {}
    got = mini(open(fixture).read())
    # build the titles map the renderer builds, from each
    def titles(doc):
        out = {}
        for t in (doc.get("tasks") or []):
            tid = str(t.get("id") or "")
            nm  = str(t.get("title") or t.get("external_id") or "")
            if tid and nm:
                out[tid] = nm
                eid = str(t.get("external_id") or "")
                if eid: out[eid] = nm
        return out
    chk("titles map: mini == PyYAML", titles(ref) == titles(got))
    chk("titles map non-empty", len(titles(got)) >= 4)
except ImportError:
    print("  SKIP - cross-reader equality (PyYAML not importable on host)")
print("R5r2-mini: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
PY
if [ "$_minirc" -eq 0 ]; then
  pass "R5r2: _mini_yaml reader unit cases (see output above)"
else
  fail "R5r2: _mini_yaml reader unit cases (rc=$_minirc)"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
