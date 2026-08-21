#!/usr/bin/env bash
# test-codex-reap-pgid-liveness-01.sh — CODEX-REAP-PGID-01
#
# Regression: CODEX-DETACH-01's setsid_wrapper() gives a --background codex
# worker its own session/process-group so it survives a SIGTERM to the
# launcher's process group. But the recorded job pid can still go dead while
# a live descendant keeps doing real work in the SAME process group (every
# detach path here — os.setsid() in setsid_wrapper, Node's spawn(detached:
# true), GNU timeout forking the setsid'd child — makes the group id equal
# the pid that got recorded). The OLD reaper only checked `os.kill(pid, 0)`,
# so it declared the job worker_died_stale and killed it mid-flight even
# though the worker was alive and unfinished. Root-caused 2026-08-21: 4/4
# healthy lanes reaped inside 15s of an unrelated `codex-task.sh status`
# sweep. Fix: pid_alive() falls back to a process-group liveness probe
# (os.killpg) before declaring a job dead — see codex-task.sh:592.
#
# Covers:
#   1. RED-before-fix / GREEN-after-fix: a detached, still-running worker
#      whose recorded pid has exited but whose process GROUP still has a
#      live member survives a reap sweep past CODEX_RUNNING_DEAD_KILL_MIN.
#   2. A genuinely dead worker (recorded pid gone AND no live group member)
#      is still reaped as worker_died_stale — the fail-safe must not become
#      a permanent leak.
#   3. queued_timeout and running_no_pid_timeout branches still fire
#      unchanged (untouched by this fix — they never reach the pid-liveness
#      check at all).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_TASK_SH="${HERE}/codex-task.sh"

COMPANION="$(find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs -path '*/scripts/*' 2>/dev/null | sort -V | tail -1)"
if [[ -z "${COMPANION}" ]]; then
  echo "SKIP: codex-companion.mjs not found (openai-codex plugin not installed) -- cannot run this test"
  exit 0
fi
LIB_DIR="$(dirname "${COMPANION}")/lib"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT
export CLAUDE_PLUGIN_DATA="${SANDBOX}/plugin-data"
export CODEX_GUARD_STATE_ROOT="${SANDBOX}/plugin-data/state"
export CODEX_QUEUED_KILL_MIN=1
export CODEX_RUNNING_DEAD_KILL_MIN=1
CWD="${SANDBOX}/project"
mkdir -p "${CWD}"

FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=1; }

past_ts() { # <minutes-ago>
  python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=$1)).strftime('%Y-%m-%dT%H:%M:%S.000Z'))"
}

# create_job <lib_dir> <job_id> <status> <pid|null> <created_ago_min> <started_ago_min|->
create_job() {
  local lib_dir="$1" job_id="$2" status="$3" pid="$4" created_ago="$5" started_ago="${6:--}"
  local created_at started_at
  created_at="$(past_ts "${created_ago}")"
  started_at="-"
  [[ "${started_ago}" != "-" ]] && started_at="$(past_ts "${started_ago}")"
  node -e '
(async () => {
  const [libDir, cwd, jobId, status, pidStr, createdAt, startedAt] = process.argv.slice(1);
  const { writeJobFile, upsertJob } = await import(libDir + "/state.mjs");
  const pid = pidStr === "null" ? null : Number(pidStr);
  const record = {
    id: jobId, status, phase: status, kind: "task", kindLabel: "task", jobClass: "task",
    pid, createdAt, workspaceRoot: cwd,
  };
  if (startedAt !== "-") record.startedAt = startedAt;
  writeJobFile(cwd, jobId, record);
  upsertJob(cwd, record);
})().catch((e) => { console.error(String(e)); process.exit(1); });
' "${lib_dir}" "${CWD}" "${job_id}" "${status}" "${pid}" "${created_at}" "${started_at}" \
    || { echo "FIXTURE SETUP FAILED for ${job_id}" >&2; exit 1; }
}

read_job_status() { # <job_id> -> prints jobs/<id>.json's status
  node -e '
(async () => {
  const [libDir, cwd, jobId] = process.argv.slice(1);
  const { resolveJobFile } = await import(libDir + "/state.mjs");
  const fs = await import("node:fs");
  const data = JSON.parse(fs.readFileSync(resolveJobFile(cwd, jobId), "utf8"));
  console.log(data.status);
})();
' "${LIB_DIR}" "${CWD}" "$1" 2>/dev/null
}

# --- fixture: a "detached worker" whose recorded pid is the (now-dead)
# process-group LEADER, while a live descendant is still in the same group.
# os.setsid() in the parent makes it the leader (pgid == its own pid); fork()
# makes the child inherit that SAME pgid; the parent then exits (recorded pid
# dies) while the child keeps sleeping, closed FDs so command substitution
# doesn't block on the child's inherited stdout/stderr.
survivor_leader_pid="$(python3 -c '
import os, sys, time
os.setsid()
child = os.fork()
if child == 0:
    os.close(0)
    os.close(1)
    os.close(2)
    time.sleep(25)
    os._exit(0)
else:
    print(os.getpid())
    sys.exit(0)
')"

# --- fixture: a genuinely dead worker -- setsid()d, no children spawned, so
# once it exits both the exact pid AND its process group are fully gone.
truly_dead_pid="$(python3 -c '
import os, sys
os.setsid()
print(os.getpid())
sys.exit(0)
')"
# belt-and-suspenders: confirm it is actually gone before trusting the fixture
for _i in 1 2 3 4 5; do
  kill -0 "${truly_dead_pid}" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "${truly_dead_pid}" 2>/dev/null; then
  echo "FIXTURE SETUP FAILED: truly_dead_pid ${truly_dead_pid} did not exit" >&2
  exit 1
fi

create_job "${LIB_DIR}" task-group-survivor running "${survivor_leader_pid}" 10 8
create_job "${LIB_DIR}" task-truly-dead     running "${truly_dead_pid}"     10 8
create_job "${LIB_DIR}" task-queued-dead    queued  99999                  20 -
create_job "${LIB_DIR}" task-norunpid       running null                   25 -

out="$(bash "${CODEX_TASK_SH}" reap 2>"${SANDBOX}/reap.err")"

# --- Case 1 (the regression): recorded pid dead, process GROUP still alive
# -> must NOT be reaped.
if echo "${out}" | grep -q "^task-group-survivor "; then
  fail "task-group-survivor: a live detached worker (group still has a live member) was reaped -- $(echo "${out}" | grep task-group-survivor)"
elif [[ "$(read_job_status task-group-survivor)" == "failed" ]]; then
  fail "task-group-survivor: reap output silent but job status was still flipped to failed"
else
  pass "task-group-survivor survives the reap sweep past CODEX_RUNNING_DEAD_KILL_MIN (regression fixed)"
fi

# --- Case 2: recorded pid dead AND group empty -> must still be reaped
# (fail-safe direction must not become a permanent leak).
if echo "${out}" | grep -q "^task-truly-dead worker_died_stale"; then
  pass "task-truly-dead (pid gone, group empty) still reaped as worker_died_stale"
else
  fail "task-truly-dead should have been reaped as worker_died_stale, got: $(echo "${out}" | grep task-truly-dead || echo '<no output line>')"
fi
[[ "$(read_job_status task-truly-dead)" == "failed" ]] \
  || fail "task-truly-dead: jobs/<id>.json status not failed after reap"

# --- Case 3: queued_timeout / running_no_pid_timeout branches unaffected
# (they never reach the pid-liveness check at all -- queued jobs go straight
# to the age check, and a `running` job with pid never recorded takes the
# `not has_pid` branch).
if echo "${out}" | grep -q "^task-queued-dead queued_timeout"; then
  pass "task-queued-dead still reaps with queued_timeout cause"
else
  fail "task-queued-dead should reap with queued_timeout cause, got: $(echo "${out}" | grep task-queued-dead || echo '<no output line>')"
fi
if echo "${out}" | grep -q "^task-norunpid running_no_pid_timeout"; then
  pass "task-norunpid still reaps with running_no_pid_timeout cause"
else
  fail "task-norunpid should reap with running_no_pid_timeout cause, got: $(echo "${out}" | grep task-norunpid || echo '<no output line>')"
fi

# cleanup the still-sleeping survivor child so the test doesn't leak a
# background process (kill the whole group -- the leader is already dead).
kill -- "-${survivor_leader_pid}" 2>/dev/null || true

if [[ ${FAIL} -eq 0 ]]; then
  echo "[TEST] ALL PASS"
  exit 0
else
  echo "[TEST] FAILURES ABOVE"
  exit 1
fi
