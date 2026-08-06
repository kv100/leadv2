#!/usr/bin/env bash
# LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01: a runner-written
# .finalized sentinel + dead process group must produce dead:sentinel_finalized
# even when the log mtime is still fresh.  Cases S1–S6, S8.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir lane-liveness-sentinel)"; trap 'rm -rf "$tmp"' EXIT

# TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment (same pattern as authoritative).
PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR resolves inside real plugin tree\n' >&2; exit 90 ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_HELPER="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_HELPER_MD5_BEFORE="$(_lv2_md5 "$REAL_HELPER")"
lv2_tripwire() {
  local after; after="$(_lv2_md5 "$REAL_HELPER")"
  if [[ "$after" != "$REAL_HELPER_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated production path %s\n' "$REAL_HELPER" >&2; exit 91
  fi
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
repo="$tmp/repo"; mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$tmp/bin"
(cd "$repo" && git init -q)
lv2_assert_scratch_repo "$repo"
active="$repo/docs/leadv2/active.yaml"
printf 'sessions: []\n' > "$active"

pass=0; fail=0
check() {
  if grep -q "$2" <<<"$1"; then
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n' "$3" "$1"; fail=$((fail+1))
  fi
}

# A high pid that is extremely unlikely to exist — used as a deterministic dead pgid.
# kill(-pgid, 0) raises ESRCH when no process group has that ID.
find_unused_pid() {
  local p=99999
  while kill -0 "$p" 2>/dev/null; do
    p=$((p + 1))
  done
  echo "$p"
}

DEAD_PGID="$(find_unused_pid)"

# Helper: set the mtime of a file to now-N seconds.
set_mtime_ago() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
path, secs = sys.argv[1], int(sys.argv[2])
t = time.time() - secs
os.utime(path, (t, t))
PY
}

# ============================================================================
# S1: RED→GREEN — the reported bug.
# glm run dir with .finalized (mtime=now−600s), pgid=dead group;
# stream mtime=now−581s (< 900s silent_max); active.yaml row with pid: null.
# Expected: dead:sentinel_finalized.  On HEAD → alive/log_fresh.
# ============================================================================
echo "=== S1: sentinel + dead pgid + fresh log → dead:sentinel_finalized ==="
glm_runs="$tmp/glm-runs"; mkdir -p "$glm_runs"
run_id="260806-041752-test0001-0001"
run_dir="$glm_runs/$run_id"; mkdir -p "$run_dir"
touch "$run_dir/.finalized"; set_mtime_ago "$run_dir/.finalized" 600
printf '%s\n' "$DEAD_PGID" > "$run_dir/pgid"
printf 'outcome=completed\n' > "$run_dir/.outcome"
lane_dir="$repo/docs/handoff/dispatch-test0001"; mkdir -p "$lane_dir"
printf '{"type":"assistant","text":"done"}\n' > "$lane_dir/developer.stream.jsonl"; set_mtime_ago "$lane_dir/developer.stream.jsonl" 581
# Run-id file
printf '%s\n' "$run_id" > "$lane_dir/.glm-session-runner.run-id"
# active.yaml row with pid: null (the observed case)
printf 'sessions:\n  - task_id: dispatch-test0001\n    pid: null\n    log_path: docs/handoff/dispatch-test0001/developer.stream.jsonl\n' > "$active"

s1_out="$(GLM_RUNS_DIR="$glm_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0001 --json --no-codex)"
check "$s1_out" '"verdict":"dead:sentinel_finalized"' 'S1: verdict is dead:sentinel_finalized'
check "$s1_out" '"reason":"sentinel_finalized"' 'S1: reason is sentinel_finalized'
check "$s1_out" '"arm":"glm"' 'S1: arm is glm'
check "$s1_out" '"pgid_alive":false' 'S1: pgid_alive is false'
check "$s1_out" '"pid_recorded":false' 'S1: pid_recorded is false (pid was null)'
check "$s1_out" '"lane_outcome":"completed"' 'S1: lane_outcome is completed'

# ============================================================================
# S2: B8 lock — must stay alive.
# fresh session.log, no pid, mapped codex job status=cancelled, NO sentinel/run dir.
# Expected: alive.
# ============================================================================
echo "=== S2: B8 lock — fresh log + provider cancelled + no sentinel → alive ==="
cat > "$tmp/bin/codex-task-cancelled.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[],"recent":[{"id":"cancelled-job","status":"cancelled","phase":"cancelled","createdAt":"2026-07-28T00:00:00Z"}]}'
SH
chmod +x "$tmp/bin/codex-task-cancelled.sh"
s2_dir="$repo/docs/handoff/S2-FRESH-CANCELLED"; mkdir -p "$s2_dir"
printf 'still going\n' > "$s2_dir/session.log"
printf '{"job_id":"cancelled-job"}\n' > "$s2_dir/codex-plan.json"
printf 'sessions: []\n' > "$active"
s2_out="$(LEADV2_PROJECT_ROOT="$repo" CODEX_TASK_SH="$tmp/bin/codex-task-cancelled.sh" bash "$HELPER" --project-root "$repo" --lane S2-FRESH-CANCELLED --json)"
check "$s2_out" '"verdict":"alive"' 'S2: fresh log + provider cancelled + no sentinel → alive'

# ============================================================================
# S3: sentinel + LIVE pgid → alive (unchanged).
# .finalized old, pgid = a live sleep process group.
# ============================================================================
echo "=== S3: sentinel + live pgid → alive ==="
# Use the test script's own process group — guaranteed alive while the test runs.
s3_pgid="$(python3 -c 'import os; print(os.getpgrp())')"
s3_run_id="260806-050000-test0003-0003"
s3_run_dir="$glm_runs/$s3_run_id"; mkdir -p "$s3_run_dir"
touch "$s3_run_dir/.finalized"; set_mtime_ago "$s3_run_dir/.finalized" 600
printf '%s\n' "$s3_pgid" > "$s3_run_dir/pgid"
s3_lane="$repo/docs/handoff/dispatch-test0003"; mkdir -p "$s3_lane"
printf '{"type":"assistant"}\n' > "$s3_lane/developer.stream.jsonl"; set_mtime_ago "$s3_lane/developer.stream.jsonl" 200
printf '%s\n' "$s3_run_id" > "$s3_lane/.glm-session-runner.run-id"
printf 'sessions:\n  - task_id: dispatch-test0003\n    pid: null\n    log_path: docs/handoff/dispatch-test0003/developer.stream.jsonl\n' > "$active"
s3_out="$(GLM_RUNS_DIR="$glm_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0003 --json --no-codex)"
check "$s3_out" '"verdict":"alive"' 'S3: sentinel + live pgid → alive'

# ============================================================================
# S4: sentinel inside settle window → alive (unchanged).
# .finalized mtime = now−5s (< 60s settle default).
# ============================================================================
echo "=== S4: sentinel inside settle window → alive ==="
s4_run_id="260806-060000-test0004-0004"
s4_run_dir="$glm_runs/$s4_run_id"; mkdir -p "$s4_run_dir"
touch "$s4_run_dir/.finalized"; set_mtime_ago "$s4_run_dir/.finalized" 5
printf '%s\n' "$DEAD_PGID" > "$s4_run_dir/pgid"
s4_lane="$repo/docs/handoff/dispatch-test0004"; mkdir -p "$s4_lane"
printf '{"type":"assistant"}\n' > "$s4_lane/developer.stream.jsonl"; set_mtime_ago "$s4_lane/developer.stream.jsonl" 200
printf '%s\n' "$s4_run_id" > "$s4_lane/.glm-session-runner.run-id"
printf 'sessions:\n  - task_id: dispatch-test0004\n    pid: null\n    log_path: docs/handoff/dispatch-test0004/developer.stream.jsonl\n' > "$active"
s4_out="$(GLM_RUNS_DIR="$glm_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0004 --json --no-codex)"
check "$s4_out" '"verdict":"alive"' 'S4: .finalized too new (< settle window) → alive'

# ============================================================================
# S5: kill switch — S1 fixture + LEADV2_LANE_SENTINEL_DEAD=0 → alive (HEAD behavior).
# ============================================================================
echo "=== S5: kill switch LEADV2_LANE_SENTINEL_DEAD=0 → alive ==="
# Re-use S1 fixture
printf '%s\n' "$run_id" > "$lane_dir/.glm-session-runner.run-id"
printf 'sessions:\n  - task_id: dispatch-test0001\n    pid: null\n    log_path: docs/handoff/dispatch-test0001/developer.stream.jsonl\n' > "$active"
s5_out="$(LEADV2_LANE_SENTINEL_DEAD=0 GLM_RUNS_DIR="$glm_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0001 --json --no-codex)"
check "$s5_out" '"verdict":"alive"' 'S5: kill switch off → alive (exact HEAD behavior)'

# ============================================================================
# S6: kimi arm — same fixture under .kimi-session-runner.run-id + $KIMI_RUNS_DIR.
# Expected: dead:sentinel_finalized, arm=kimi.
# ============================================================================
echo "=== S6: kimi arm → dead:sentinel_finalized, arm=kimi ==="
kimi_runs="$tmp/kimi-runs"; mkdir -p "$kimi_runs"
s6_run_id="260806-070000-test0006-0006"
s6_run_dir="$kimi_runs/$s6_run_id"; mkdir -p "$s6_run_dir"
touch "$s6_run_dir/.finalized"; set_mtime_ago "$s6_run_dir/.finalized" 600
printf '%s\n' "$DEAD_PGID" > "$s6_run_dir/pgid"
printf 'outcome=died-clean\n' > "$s6_run_dir/.outcome"
s6_lane="$repo/docs/handoff/dispatch-test0006"; mkdir -p "$s6_lane"
printf '{"type":"assistant"}\n' > "$s6_lane/developer.stream.jsonl"; set_mtime_ago "$s6_lane/developer.stream.jsonl" 300
printf '%s\n' "$s6_run_id" > "$s6_lane/.kimi-session-runner.run-id"
printf 'sessions:\n  - task_id: dispatch-test0006\n    pid: null\n    log_path: docs/handoff/dispatch-test0006/developer.stream.jsonl\n' > "$active"
s6_out="$(KIMI_RUNS_DIR="$kimi_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0006 --json --no-codex)"
check "$s6_out" '"verdict":"dead:sentinel_finalized"' 'S6: kimi arm → dead:sentinel_finalized'
check "$s6_out" '"arm":"kimi"' 'S6: arm is kimi'

# ============================================================================
# S8: .done alone is NOT a sentinel.
# Run dir with .done + dead pgid, NO .finalized → alive.
# ============================================================================
echo "=== S8: .done alone (no .finalized) → alive ==="
s8_run_id="260806-080000-test0008-0008"
s8_run_dir="$glm_runs/$s8_run_id"; mkdir -p "$s8_run_dir"
touch "$s8_run_dir/.done"
# No .finalized!
printf '%s\n' "$DEAD_PGID" > "$s8_run_dir/pgid"
s8_lane="$repo/docs/handoff/dispatch-test0008"; mkdir -p "$s8_lane"
printf '{"type":"assistant"}\n' > "$s8_lane/developer.stream.jsonl"; set_mtime_ago "$s8_lane/developer.stream.jsonl" 200
printf '%s\n' "$s8_run_id" > "$s8_lane/.glm-session-runner.run-id"
printf 'sessions:\n  - task_id: dispatch-test0008\n    pid: null\n    log_path: docs/handoff/dispatch-test0008/developer.stream.jsonl\n' > "$active"
s8_out="$(GLM_RUNS_DIR="$glm_runs" LEADV2_PROJECT_ROOT="$repo" bash "$HELPER" --project-root "$repo" --lane dispatch-test0008 --json --no-codex)"
check "$s8_out" '"verdict":"alive"' 'S8: .done alone (no .finalized) → alive'

echo ""
echo "=== Results: ${pass} passed, ${fail} failed ==="
if [[ "$fail" -gt 0 ]]; then exit 1; fi
printf '\n[TEST-SAFETY] tripwire: '; lv2_tripwire
