#!/usr/bin/env bash
# CLAUDE-SUBSESSION-HAS-NO-COMPLETION-SENTINEL-01: the claude arm of the
# lane-liveness sentinel path.  E-cases run the REAL claude-subsession.sh bg
# branch (fake `claude` binary) and assert the wrapper's run-dir/pid/sentinel
# contract; C-cases are fixture-built safety negatives (every ambiguous shape
# must resolve alive); H3 proves newest-pointer-mtime arm resolution.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir claude-subsession-sentinel)"; trap 'rm -rf "$tmp"' EXIT

# TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment (same pattern as sentinel suite).
PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_SUBSESSION="${REAL_PLUGIN_DIR}/scripts/claude-subsession.sh"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
MD5_BEFORE="$(_lv2_md5 "$REAL_SUBSESSION")$(_lv2_md5 "${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh")"
lv2_tripwire() {
  local after; after="$(_lv2_md5 "$REAL_SUBSESSION")$(_lv2_md5 "${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh")"
  if [[ "$after" != "$MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production script\n' >&2; exit 91
  fi
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

repo="$tmp/repo"; mkdir -p "$repo/.claude/agents" "$repo/docs/handoff" "$repo/docs/leadv2" "$tmp/bin" "$tmp/runs"
printf 'sessions: []\n' > "$repo/docs/leadv2/active.yaml"
printf 'Test role body.\n' > "$repo/.claude/agents/developer.md"
printf 'Test mission.\n' > "$repo/mission.md"

pass=0; fail=0
check() {
  if grep -q "$2" <<<"$1"; then
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n' "$3" "$1"; fail=$((fail+1))
  fi
}

set_mtime_ago() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, secs = sys.argv[1], int(sys.argv[2])
t = time.time() - secs
os.utime(path, (t, t))
PY
}

# Fake claude: sleeps 4s (proves no spawn-time stamping), exits 4 (proves the
# real child exit code reaches .outcome).
cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
sleep 4
printf '{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5}}}\n'
exit 4
SH
chmod +x "$tmp/bin/claude"

# ============================================================================
# E1-E2: real bg spawn — run dir, pointer, pid file, and NO sentinel while the
# worker is provably alive (the exact false-dead hazard H2 exists to kill).
# ============================================================================
echo "=== E1/E2: real bg spawn, worker alive at t+2s ==="
out="$(cd "$repo" && PROJECT_ROOT="$repo" LEADV2_CLAUDE_RUNS_DIR="$tmp/runs" \
  PATH="$tmp/bin:$PATH" LEADV2_ROUTE_BANDIT=0 bash "$REAL_SUBSESSION" \
  --role developer --model sonnet --task-id SENT-CL --mission-file "$repo/mission.md")"
pid_printed="$(sed -n 's/^PID=\([0-9]*\).*/\1/p' <<<"$out")"
run_id="$(cat "$repo/docs/handoff/SENT-CL/.claude-session-runner.run-id")"
run_dir="$tmp/runs/$run_id"
[[ -d "$run_dir" ]] && { printf '[TEST] PASS: run dir created\n'; pass=$((pass+1)); } \
  || { printf '[TEST] FAIL: run dir missing (%s)\n' "$run_dir"; fail=$((fail+1)); }
[[ -f "$run_dir/meta.yaml" ]] && grep -q "task_id: SENT-CL" "$run_dir/meta.yaml" \
  && { printf '[TEST] PASS: meta.yaml carries task_id\n'; pass=$((pass+1)); } \
  || { printf '[TEST] FAIL: meta.yaml wrong\n'; fail=$((fail+1)); }
[[ "$(cat "$run_dir/pid" 2>/dev/null)" == "$pid_printed" ]] \
  && { printf '[TEST] PASS: pid file matches printed PID (name=pid, not pgid)\n'; pass=$((pass+1)); } \
  || { printf '[TEST] FAIL: pid file mismatch\n'; fail=$((fail+1)); }
sleep 2
if [[ -f "$run_dir/.finalized" ]]; then
  printf '[TEST] FAIL: .finalized stamped while worker alive (false-dead)\n'; fail=$((fail+1))
else
  printf '[TEST] PASS: no .finalized while worker alive\n'; pass=$((pass+1))
fi
kill -0 "$pid_printed" 2>/dev/null \
  && { printf '[TEST] PASS: worker pid alive at t+2s\n'; pass=$((pass+1)); } \
  || { printf '[TEST] FAIL: worker died early\n'; fail=$((fail+1)); }

# Wait for the wrapper to reap the child and stamp the sentinel.
_wait=0
until [[ -f "$run_dir/.finalized" ]] || (( _wait >= 30 )); do sleep 1; _wait=$((_wait+1)); done
[[ -f "$run_dir/.finalized" ]] && { printf '[TEST] PASS: .finalized stamped after child reaped\n'; pass=$((pass+1)); } \
  || { printf '[TEST] FAIL: .finalized never appeared\n'; fail=$((fail+1)); }
check "$(cat "$run_dir/.outcome" 2>/dev/null)" '^outcome=4$' 'E2: .outcome carries real child exit code (4)'

# ============================================================================
# E3: the acceptance observable — lane reads dead:sentinel_finalized once the
# sentinel is aged past the settle window and the pid is positively gone.
# ============================================================================
echo "=== E3: liveness → dead:sentinel_finalized on claude arm ===
"
touch "$run_dir/.finalized"; set_mtime_ago "$run_dir/.finalized" 600
touch "$repo/docs/handoff/SENT-CL/developer.stream.jsonl"; set_mtime_ago "$repo/docs/handoff/SENT-CL/developer.stream.jsonl" 581
printf 'sessions:\n  - task_id: SENT-CL\n    pid: null\n    log_path: docs/handoff/SENT-CL/developer.stream.jsonl\n' > "$repo/docs/leadv2/active.yaml"
e3="$(LEADV2_CLAUDE_RUNS_DIR="$tmp/runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane SENT-CL --json --no-codex)"
check "$e3" '"verdict":"dead:sentinel_finalized"' 'E3: verdict is dead:sentinel_finalized'
check "$e3" '"sentinel_arm":"claude"' 'E3: sentinel_arm is claude'
check "$e3" '"lane_outcome":"4"' 'E3: lane_outcome surfaced'

# ============================================================================
# C-cases: every ambiguous shape must NOT produce a sentinel dead.
# ============================================================================
mk_lane() { # $1 lane id, $2 pid value ("-" = omit file)
  local lane="$1" rv="$2"
  local rd="$tmp/runs/$lane-run"
  mkdir -p "$rd" "$repo/docs/handoff/$lane"
  touch "$rd/.finalized"; set_mtime_ago "$rd/.finalized" 600
  [[ "$rv" != "-" ]] && printf '%s\n' "$rv" > "$rd/pid"
  printf '%s-run\n' "$lane" > "$repo/docs/handoff/$lane/.claude-session-runner.run-id"
  touch "$repo/docs/handoff/$lane/developer.stream.jsonl"; set_mtime_ago "$repo/docs/handoff/$lane/developer.stream.jsonl" 581
  printf 'sessions:\n  - task_id: %s\n    pid: null\n    log_path: docs/handoff/%s/developer.stream.jsonl\n' "$lane" "$lane" > "$repo/docs/leadv2/active.yaml"
}

run_lane() { # $1 lane id, $2.. extra env as KEY=VAL
  local lane="$1"; shift
  env LEADV2_CLAUDE_RUNS_DIR="$tmp/runs" LEADV2_PROJECT_ROOT="$repo" "$@" \
    bash "$HELPER" --project-root "$repo" --lane "$lane" --json --no-codex
}

echo "=== C1: live pid + aged sentinel → NOT sentinel dead ==="
mk_lane SENT-C1 "$$"
c1="$(run_lane SENT-C1)"
if grep -q 'dead:sentinel_finalized' <<<"$c1"; then
  printf '[TEST] FAIL: C1 fired on live pid\n'; fail=$((fail+1))
else printf '[TEST] PASS: C1 live pid → no sentinel dead\n'; pass=$((pass+1)); fi

echo "=== C2: missing pid file + aged sentinel → NOT sentinel dead ==="
mk_lane SENT-C2 "-"
c2="$(run_lane SENT-C2)"
if grep -q 'dead:sentinel_finalized' <<<"$c2"; then
  printf '[TEST] FAIL: C2 fired without pid file\n'; fail=$((fail+1))
else printf '[TEST] PASS: C2 missing pid file → no sentinel dead\n'; pass=$((pass+1)); fi

echo "=== C3: LEADV2_LANE_SENTINEL_CLAUDE=0 rollback → NOT sentinel dead ==="
c3="$(run_lane SENT-CL LEADV2_LANE_SENTINEL_CLAUDE=0)"
if grep -q 'dead:sentinel_finalized' <<<"$c3"; then
  printf '[TEST] FAIL: C3 fired with claude kill switch off\n'; fail=$((fail+1))
else printf '[TEST] PASS: C3 claude kill switch off → no sentinel dead\n'; pass=$((pass+1)); fi

echo "=== C4: .finalized inside settle window → NOT sentinel dead ==="
set_mtime_ago "$run_dir/.finalized" 5
c4="$(run_lane SENT-CL)"
if grep -q 'dead:sentinel_finalized' <<<"$c4"; then
  printf '[TEST] FAIL: C4 fired inside settle window\n'; fail=$((fail+1))
else printf '[TEST] PASS: C4 fresh .finalized → no sentinel dead\n'; pass=$((pass+1)); fi
set_mtime_ago "$run_dir/.finalized" 600

echo "=== C5/H3: newest pointer mtime wins across arms (glm newer → arm=glm) ==="
glm_runs="$tmp/glm-runs"; mkdir -p "$glm_runs"
glm_dir="$glm_runs/glm-newest"; mkdir -p "$glm_dir"
find_unused_pgid() { local p=99999; while kill -0 -- "-$p" 2>/dev/null || kill -0 "$p" 2>/dev/null; do p=$((p+1)); done; echo "$p"; }
printf '%s\n' "$(find_unused_pgid)" > "$glm_dir/pgid"
touch "$glm_dir/.finalized"; set_mtime_ago "$glm_dir/.finalized" 600
printf 'outcome=completed\n' > "$glm_dir/.outcome"
# glm pointer NEWER than the claude pointer → newest-pointer resolution must
# pick glm even though claude is later in arm iteration order.
set_mtime_ago "$repo/docs/handoff/SENT-CL/.claude-session-runner.run-id" 500
printf 'glm-newest\n' > "$repo/docs/handoff/SENT-CL/.glm-session-runner.run-id"
set_mtime_ago "$repo/docs/handoff/SENT-CL/.glm-session-runner.run-id" 100
c5="$(GLM_RUNS_DIR="$glm_runs" LEADV2_CLAUDE_RUNS_DIR="$tmp/runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane SENT-CL --json --no-codex)"
check "$c5" '"arm":"glm"' 'C5: newest pointer wins → arm=glm (not first-match claude)'

echo "=== C6/H3-tie: same-second pointers, claude finalized vs glm fresh → must NOT resolve the finalized arm ==="
# Codex review claim 2: an instant-death claude attempt + a glm spawn in the
# same second tie on pointer mtime; the tie must break toward the NON-finalized
# (possibly running) arm or a false dead can fire.
glm_dir2="$glm_runs/glm-fresh-tie"; mkdir -p "$glm_dir2"  # fresh glm run: no sentinel
printf 'glm-fresh-tie\n' > "$repo/docs/handoff/SENT-CL/.glm-session-runner.run-id"
tie_t="$(python3 -c 'import time; print(int(time.time())-300)')"
touch -t "$(python3 -c "import time; print(time.strftime('%Y%m%d%H%M.%S', time.localtime($tie_t)))")" \
  "$repo/docs/handoff/SENT-CL/.claude-session-runner.run-id" "$repo/docs/handoff/SENT-CL/.glm-session-runner.run-id"
printf 'sessions:\n  - task_id: SENT-CL\n    pid: null\n    log_path: docs/handoff/SENT-CL/developer.stream.jsonl\n' > "$repo/docs/leadv2/active.yaml"
# Both pointers now carry the IDENTICAL mtime; claude run is finalized+aged,
# glm run has no sentinel. Tie must resolve glm (non-finalized).
c6="$(GLM_RUNS_DIR="$glm_runs" LEADV2_CLAUDE_RUNS_DIR="$tmp/runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane SENT-CL --json --no-codex)"
if grep -q 'dead:sentinel_finalized' <<<"$c6"; then
  printf '[TEST] FAIL: C6 tie resolved the finalized claude arm (false-dead window)\n'; fail=$((fail+1))
else printf '[TEST] PASS: C6 same-second tie → non-finalized arm wins\n'; pass=$((pass+1)); fi

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$pass" "$fail"
(( fail == 0 ))
