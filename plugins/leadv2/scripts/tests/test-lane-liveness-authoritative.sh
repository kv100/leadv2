#!/usr/bin/env bash
# FIX-LANE-LIVENESS-AUTHORITATIVE-01: provider status outranks sidecars/ps.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
SUPERVISE="${PLUGIN_DIR}/scripts/leadv2-supervise.sh"
STATE_PATH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
tmp="$(lv2_mktemp_dir lane-liveness)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; state="$tmp/state"; mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$tmp/bin" "$state"
(cd "$repo" && git init -q)
# TEST SAFETY (B1 root cause, fix-round-2): hard-abort unless this is
# provably a throwaway fixture — see lv2_assert_scratch_repo in leadv2-temp.sh.
lv2_assert_scratch_repo "$repo"
active="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH" active.yaml)"
mkdir -p "$(dirname "$active")"; printf 'sessions: []\n' > "$active"
cat > "$tmp/bin/codex-task.sh" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"cancelled-job"* ]]; then
  printf '%s\n' '{"workspaceRoot":"x","job":{"id":"cancelled-job","status":"cancelled","phase":"cancelled","createdAt":"2026-07-28T00:00:00Z"}}'
else
  printf '%s\n' '{"workspaceRoot":"x","running":[{"id":"running-job","status":"running","phase":"verifying","createdAt":"2026-07-28T00:00:00Z"}],"recent":[]}'
fi
SH
chmod +x "$tmp/bin/codex-task.sh"
pass=0
check() { grep -q "$2" <<<"$1" && { printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1)); } || { printf '[TEST] FAIL: %s\n%s\n' "$3" "$1"; exit 1; }; }

# No codex-guard process is created: running must remain running.
running="$(CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --json)"
check "$running" '"verdict": "running"' 'running job is not classified dead without codex-guard'
cancelled="$(CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --job cancelled-job --json)"
check "$cancelled" '"verdict": "cancelled"' 'cancelled job is reported as cancelled, not dead'
supervised="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
check "$supervised" 'codex:running-job' 'supervise enumerates Codex app-server job'
check "$supervised" '"phase": "verifying"' 'supervise preserves authoritative Phase'

# The registry is intentionally empty: a fresh lane log must still create a
# table row, which is the regression for the former false "none" snapshot.
mkdir -p "$repo/docs/handoff/LOG-ONLY"
printf 'worker is alive\n' > "$repo/docs/handoff/LOG-ONLY/session.log"
lane="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane LOG-ONLY --json)"
check "$lane" '"verdict":"alive"' 'fresh session.log is alive without active.yaml row'
check "$lane" '"source":".*/session.log"' 'session.log path is recorded as liveness source'
union="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
check "$union" '"task_id": "LOG-ONLY"' 'supervise emits log-only lane while registry is empty'
threshold="$(LEADV2_LANE_SILENT_MAX_S=0 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane LOG-ONLY)"
check "$threshold" 'silent:' 'silence threshold controls log-only lane verdict'

# A recorded live PID changes stale/dead split only; it never becomes stuck.
mkdir -p "$repo/docs/handoff/PID-ALIVE"
printf 'old worker output\n' > "$repo/docs/handoff/PID-ALIVE/session.log"
python3 - "$repo/docs/handoff/PID-ALIVE/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 60, time.time() - 60))
PY
printf 'sessions:\n  - task_id: PID-ALIVE\n    pid: %s\n    started_at: "2020-01-01T00:00:00Z"\n' "$$" > "$active"
pid_silent="$(LEADV2_LANE_SILENT_MAX_S=1 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane PID-ALIVE)"
check "$pid_silent" 'silent:' 'pid-alive silent lane remains silent'
pid_snapshot="$(LEADV2_LANE_SILENT_MAX_S=1 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$SUPERVISE" --json)"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert "PID-ALIVE" not in [x["task_id"] for x in d.get("stuck", [])]' <<<"$pid_snapshot"; then
  printf '[TEST] PASS: pid-alive silent lane is absent from stuck\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: pid-alive silent lane entered stuck\n%s\n' "$pid_snapshot"; exit 1
fi
# SUPERVISOR-AUDIT-01 fix-round regression: a self-reported provider
# queued/running status must never short-circuit to "alive" ahead of log
# mtime — a stale log with no PID evidence must resolve silent/dead.
mkdir -p "$repo/docs/handoff/STALE-RUNNING"
printf 'old output\n' > "$repo/docs/handoff/STALE-RUNNING/session.log"
python3 - "$repo/docs/handoff/STALE-RUNNING/session.log" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 5000, time.time() - 5000))
PY
printf '{"job_id":"running-job"}\n' > "$repo/docs/handoff/STALE-RUNNING/codex-plan.json"
stale_running="$(LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --lane STALE-RUNNING)"
check "$stale_running" 'silent:' 'self-reported provider running + stale log -> silent, not alive'
rollback_running="$(LEADV2_LANE_LIVENESS_V2=0 LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task.sh" bash "$HELPER" --project-root "$repo" --lane STALE-RUNNING)"
check "$rollback_running" 'alive' 'LEADV2_LANE_LIVENESS_V2=0 reproduces exact prior (self-report trusted) behavior'

# B8 (SUPERVISOR-AUDIT-01 fix-round-3, review-verdict-3.md): reviewer's exact
# probe — a FRESH session.log, no PID, and the mapped provider job reporting
# "cancelled" must NOT short-circuit to dead:provider_cancelled. A terminal
# provider self-report is only trusted once the log has ALSO gone stale.
# The shared codex-task.sh stub only reports "cancelled-job" via --job
# (single-job lookup); --lane resolution queries --all, so a dedicated stub
# is needed that surfaces the terminal job through the --all/"recent" shape
# leadv2-lane-liveness.sh's provider_jobs() actually reads for lane lookups.
cat > "$tmp/bin/codex-task-cancelled.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"workspaceRoot":"x","running":[],"recent":[{"id":"cancelled-job","status":"cancelled","phase":"cancelled","createdAt":"2026-07-28T00:00:00Z"}]}'
SH
chmod +x "$tmp/bin/codex-task-cancelled.sh"
mkdir -p "$repo/docs/handoff/FRESH-CANCELLED"
printf 'still going\n' > "$repo/docs/handoff/FRESH-CANCELLED/session.log"
printf '{"job_id":"cancelled-job"}\n' > "$repo/docs/handoff/FRESH-CANCELLED/codex-plan.json"
fresh_cancelled="$(LEADV2_LANE_SILENT_MAX_S=900 LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$tmp/bin/codex-task-cancelled.sh" bash "$HELPER" --project-root "$repo" --lane FRESH-CANCELLED --json)"
check "$fresh_cancelled" '"verdict":"alive"' 'fresh log + no PID + provider cancelled -> alive, terminal status never overrides a fresh log'
check "$fresh_cancelled" '"age_s":[0-9]' 'fresh-cancelled row carries a real age_s'

# B9/B14 regression (SUPERVISOR-AUDIT-01 fix-round-2): a real
# leadv2-fanout.sh single-worker-funnel lane never writes under
# docs/handoff/<task_id>/ -- it writes docs/handoff/dispatch-<sig8>/
# developer.stream.jsonl and records THAT path in the active.yaml row's
# log_path field. Use the REAL fanout artifact layout here (not a synthetic
# FUNNEL-1/session.log fixture) so this proves the actual bug: a fresh
# funnel dispatch must resolve alive via log_path, never
# dead:no_handoff_dir, and the docs/handoff/FUNNEL-TASK/ directory must
# never be created at all.
mkdir -p "$repo/docs/handoff/dispatch-abc12345"
printf '{"type":"assistant","text":"working"}\n' > "$repo/docs/handoff/dispatch-abc12345/developer.stream.jsonl"
printf 'sessions:\n  - task_id: FUNNEL-TASK\n    phase: build\n    pid: null\n    log_path: docs/handoff/dispatch-abc12345/developer.stream.jsonl\n' > "$active"
funnel_alive="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane FUNNEL-TASK --json)"
check "$funnel_alive" '"verdict":"alive"' 'funnel lane with recorded log_path is alive, not dead:no_handoff_dir'
check "$funnel_alive" 'dispatch-abc12345/developer.stream.jsonl' 'funnel lane liveness source is the recorded log_path, not a directory scan'
if [[ -d "$repo/docs/handoff/FUNNEL-TASK" ]]; then
  printf '[TEST] FAIL: docs/handoff/FUNNEL-TASK/ must never be created for a funnel-dispatched lane\n'; exit 1
else
  printf '[TEST] PASS: no docs/handoff/FUNNEL-TASK/ directory created for a funnel-dispatched lane\n'; pass=$((pass+1))
fi
# A stale funnel log_path (file no longer exists) must fall through to the
# unchanged directory-scan behavior rather than silently resolving alive.
printf 'sessions:\n  - task_id: FUNNEL-GONE\n    phase: build\n    pid: null\n    log_path: docs/handoff/dispatch-doesnotexist/developer.stream.jsonl\n' > "$active"
funnel_gone="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane FUNNEL-GONE)"
check "$funnel_gone" 'dead:no_handoff_dir' 'funnel lane with a missing log_path target falls through to the directory scan unchanged'

printf '[TEST] %d authoritative-liveness assertions passed\n' "$pass"
