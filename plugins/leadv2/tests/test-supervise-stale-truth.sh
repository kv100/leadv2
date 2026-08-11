#!/usr/bin/env bash
# tests/test-supervise-stale-truth.sh — STATUS-SURFACE-SHOWS-STALE-TRUTH-01
#
# leadv2-supervise.sh used to sort its lane table alphabetically by task_id
# and THEN cap it to 20 rows (CAP_ROWS), with an unbounded tombstone loop
# appended after the cap. Against a never-reaped store of hundreds of dead
# lanes, that means today's live lanes — whose ids sort late alphabetically
# — are truncated away, and the surface shows nothing but weeks-old corpses.
#
# This proves: (a) a fresh live lane survives the cap even when 25 dead
# lanes alphabetically precede it, (b) a dead lane silent well past the reap
# threshold is hidden, (c) a lane with a LIVE pid is never reaped no matter
# how old its timestamp, (d) suppression is announced, never silent.
#
# Usage: bash tests/test-supervise-stale-truth.sh
# Exit 0 = all pass; non-zero = failure count.
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}/../scripts"
SUPERVISE="${SCRIPT_DIR}/leadv2-supervise.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMP_DIR="$(mktemp -d)"
BG_PIDS=()
cleanup() {
  for p in "${BG_PIDS[@]+"${BG_PIDS[@]}"}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

REPO_DIR="${TMP_DIR}/repo"
mkdir -p "$REPO_DIR"
(cd "$REPO_DIR" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init)

STATE_ROOT="${TMP_DIR}/state"
mkdir -p "$STATE_ROOT"
HANDOFF_DIR="${REPO_DIR}/docs/handoff"
mkdir -p "$HANDOFF_DIR"

# ── Fixtures ─────────────────────────────────────────────────────────────
# (1) 25 dead lanes, alphabetically EARLY (dispatch-a01..dispatch-a25), each
#     with a 2-day-old stream file (so leadv2-lane-liveness.sh's directory
#     glob actually enumerates them as lanes) -> dead:silent_*_abandoned, no
#     pid. Enough to fill CAP_ROWS (20) on their own under an
#     alphabetical-then-cap ordering.
_OLD_MTIME="$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)"
for i in $(seq -w 1 25); do
  mkdir -p "${HANDOFF_DIR}/dispatch-a${i}"
  : > "${HANDOFF_DIR}/dispatch-a${i}/developer.stream.jsonl"
  touch -t "$_OLD_MTIME" "${HANDOFF_DIR}/dispatch-a${i}/developer.stream.jsonl"
done

# (2) the live lane under test: alphabetically LAST, fresh log -> alive.
LIVE_LANE="dispatch-zzzz-live"
mkdir -p "${HANDOFF_DIR}/${LIVE_LANE}"
: > "${HANDOFF_DIR}/${LIVE_LANE}/developer.stream.jsonl"

# (3) a dead lane, silent for 2 days, no pid -> must be reaped.
OLD_DEAD_LANE="dispatch-b-olddead"
mkdir -p "${HANDOFF_DIR}/${OLD_DEAD_LANE}"
: > "${HANDOFF_DIR}/${OLD_DEAD_LANE}/developer.stream.jsonl"
touch -t "$_OLD_MTIME" "${HANDOFF_DIR}/${OLD_DEAD_LANE}/developer.stream.jsonl"

# (4) a lane with a LIVE pid but a 2-day-old registration and no handoff
#     artifact at all (dead:no_handoff_dir per the liveness ladder) -> must
#     NEVER be reaped, because pid_alive is true.
sleep 300 &
LIVE_PID_LANE_PID=$!
BG_PIDS+=("$LIVE_PID_LANE_PID")
OLD_LIVE_PID_LANE="dispatch-c-oldlivepid"
OLD_ISO="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"
cat > "${STATE_ROOT}/active.yaml" <<EOF
version: 2
meta:
  hard_limit: 50
sessions:
  - task_id: ${OLD_LIVE_PID_LANE}
    worktree: ${REPO_DIR}
    branch: unknown
    started_at: "${OLD_ISO}"
    phase: build
    class: Standard
    pid: ${LIVE_PID_LANE_PID}
EOF

run_supervise() {
  LEADV2_STATE_ROOT="$STATE_ROOT" LEADV2_PROJECT_ROOT="$REPO_DIR" \
  LEADV2_SUPERVISE_REAP_S="${1:-3700}" \
    bash "$SUPERVISE" --json 2>"$TMP_DIR/supervise.err"
}

OUT="$(run_supervise 3700 || true)"
echo "$OUT" > "$TMP_DIR/supervise.json"

# ── (a) live lane survives the cap despite 25 alphabetically-earlier dead lanes ──
if python3 -c "
import json,sys
d = json.load(open('$TMP_DIR/supervise.json'))
ids = [r['task_id'] for r in d.get('table', [])]
sys.exit(0 if '$LIVE_LANE' in ids else 1)
" 2>/dev/null; then
  pass "(a) fresh live lane ($LIVE_LANE) is present despite 25 alphabetically-earlier dead lanes"
else
  fail "(a) fresh live lane ($LIVE_LANE) missing from table (alphabetical-then-cap truncation) — table: $(python3 -c "import json;print([r['task_id'] for r in json.load(open('$TMP_DIR/supervise.json')).get('table',[])])" 2>/dev/null)"
fi

# ── (b) a dead lane silent well past the reap threshold is hidden ──────────
if python3 -c "
import json,sys
d = json.load(open('$TMP_DIR/supervise.json'))
ids = [r['task_id'] for r in d.get('table', [])]
sys.exit(0 if '$OLD_DEAD_LANE' not in ids else 1)
" 2>/dev/null; then
  pass "(b) dead lane silent past reap threshold ($OLD_DEAD_LANE) is hidden"
else
  fail "(b) dead lane silent past reap threshold ($OLD_DEAD_LANE) should be reaped from the table"
fi

# ── (c) a lane with a LIVE pid is never reaped, no matter how old its timestamp ──
if python3 -c "
import json,sys
d = json.load(open('$TMP_DIR/supervise.json'))
ids = [r['task_id'] for r in d.get('table', [])]
sys.exit(0 if '$OLD_LIVE_PID_LANE' in ids else 1)
" 2>/dev/null; then
  pass "(c) live-PID lane ($OLD_LIVE_PID_LANE) is never reaped despite a 2-day-old registration"
else
  fail "(c) live-PID lane ($OLD_LIVE_PID_LANE) was wrongly reaped — table: $(python3 -c "import json;print([r['task_id'] for r in json.load(open('$TMP_DIR/supervise.json')).get('table',[])])" 2>/dev/null)"
fi

# ── (d) suppression is announced, never silent ──────────────────────────────
if python3 -c "
import json,sys
d = json.load(open('$TMP_DIR/supervise.json'))
sys.exit(0 if d.get('hidden_lanes_summary') else 1)
" 2>/dev/null; then
  pass "(d) hidden_lanes_summary is populated when rows were suppressed"
else
  fail "(d) hidden_lanes_summary should be non-null when rows were reaped/capped — got: $(python3 -c "import json;print(json.load(open('$TMP_DIR/supervise.json')).get('hidden_lanes_summary'))" 2>/dev/null)"
fi

# ── (e) LEADV2_SUPERVISE_REAP_S below the abandon threshold is clamped, not silently obeyed ──
OUT2="$(run_supervise 10 || true)"
echo "$OUT2" > "$TMP_DIR/supervise2.json"
if python3 -c "
import json,sys
d = json.load(open('$TMP_DIR/supervise2.json'))
w = ' '.join(d.get('warnings', []))
sys.exit(0 if 'clamped' in w else 1)
" 2>/dev/null; then
  pass "(e) LEADV2_SUPERVISE_REAP_S below the lane-liveness abandon threshold is clamped with a warning"
else
  fail "(e) an under-threshold LEADV2_SUPERVISE_REAP_S should warn+clamp, not silently apply"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
