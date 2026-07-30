#!/usr/bin/env bash
# test-codex-task-reap.sh — CODEX-REAP-01 + wave2 findings 1/2/9 + wave2 round2 finding 2.
#
# Exercises the REAL `codex-task.sh reap` sweep (never a hand-reimplemented copy of
# reap_one/_sync_state_index) against real job fixtures seeded via the plugin's own
# writeJobFile/upsertJob (state.mjs) -- same discipline as test-leadv2-dispatch-outcome-
# ledger.sh. Covers:
#   1. queued job, dead pid, past CODEX_QUEUED_KILL_MIN -> reaped, both jobs/<id>.json
#      AND the canonical state.json index show status=failed (wave2 finding 1).
#   2. running job, no pid ever recorded, past the grace window -> reaped with the
#      distinct running_no_pid cause, not the tighter dead-worker path (wave2 finding 9).
#   3. running job, dead pid, past CODEX_RUNNING_DEAD_KILL_MIN -> reaped (worker_died_stale).
#   4. a live (untouched) queued job and a live running job are left alone.
#   5. round2 finding 2: upsertJob failure (simulated via a bad LIB_DIR override for one
#      reap invocation) does NOT lose the divergence -- a repair marker is written next
#      to the job file, and a LATER sweep (with LIB_DIR restored) reconciles it, bringing
#      state.json in sync without re-reaping the job file itself.
#   6. idempotent re-run: a second sweep over already-reaped jobs reaps nothing new, no
#      stale .lock dirs left behind.
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

read_index_status() { # <job_id> -> prints state.json's status for that id, or "MISSING"
  node -e '
(async () => {
  const [libDir, cwd, jobId] = process.argv.slice(1);
  const { listJobs } = await import(libDir + "/state.mjs");
  const job = listJobs(cwd).find((j) => j.id === jobId);
  console.log(job ? job.status : "MISSING");
})();
' "${LIB_DIR}" "${CWD}" "$1" 2>/dev/null
}

# --- fixtures ---------------------------------------------------------------
# NOTE: task-repair is deliberately created LATER (right before the round2 finding-2
# block below), never in this batch -- `codex-task.sh reap` sweeps EVERY stale job in
# the store, not just a named target, so an old-enough task-repair fixture created here
# would get swept (and its index synced) by the very first `reap` call below, leaving
# nothing left to prove the repair-marker path against.
create_job "${LIB_DIR}" task-queued-dead   queued  99999 20 -      # dead pid, 20min old queued
create_job "${LIB_DIR}" task-norunpid      running null  25 -      # running, pid never recorded, 25min old (finding 9)
create_job "${LIB_DIR}" task-worker-died   running 99999 10 8      # dead pid, started 8min ago (finding: worker_died_stale)
create_job "${LIB_DIR}" task-live-queued   queued  $$    1  -      # THIS process's own pid -- alive, untouched
create_job "${LIB_DIR}" task-live-running  running $$    10 8      # alive pid, untouched despite being "old"

# --- round1 findings 1/9 + a dead worker_died_stale case --------------------
out1="$(bash "${CODEX_TASK_SH}" reap 2>"${SANDBOX}/reap1.err")"

for jid in task-queued-dead task-norunpid task-worker-died; do
  echo "${out1}" | grep -q "^${jid} " || fail "reap output missing ${jid}"
done
echo "${out1}" | grep -q "^task-norunpid running_no_pid_timeout" \
  || fail "task-norunpid should reap with running_no_pid_timeout cause (finding 9), got: $(echo "${out1}" | grep task-norunpid)"
echo "${out1}" | grep -q "^task-worker-died worker_died_stale" \
  || fail "task-worker-died should reap with worker_died_stale cause"
echo "${out1}" | grep -q "^task-queued-dead queued_timeout" \
  || fail "task-queued-dead should reap with queued_timeout cause"

for jid in task-queued-dead task-norunpid task-worker-died; do
  [[ "$(read_job_status "${jid}")" == "failed" ]] || fail "${jid}: jobs/<id>.json status not failed after reap"
  [[ "$(read_index_status "${jid}")" == "failed" ]] || fail "${jid}: state.json index status not failed after reap (finding 1: index sync)"
done

for jid in task-live-queued task-live-running; do
  [[ "$(read_job_status "${jid}")" != "failed" ]] || fail "${jid}: a LIVE job was reaped"
done

if [[ ${FAIL} -eq 0 ]]; then pass "round1 findings 1/9 + worker_died_stale: reaped correctly, index in sync, live jobs untouched"; fi

# --- idempotent re-run: nothing new reaped, no stale .lock dirs -------------
out2="$(bash "${CODEX_TASK_SH}" reap 2>"${SANDBOX}/reap2.err")"
if echo "${out2}" | grep -qE "^(task-queued-dead|task-norunpid|task-worker-died) "; then
  fail "idempotent re-run reaped an already-reaped job again"
else
  pass "idempotent re-run reaps nothing new for already-terminal jobs"
fi
stale_locks="$(find "${CODEX_GUARD_STATE_ROOT}" -name '*.lock' -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "${stale_locks}" -eq 0 ]] || fail "found ${stale_locks} stale .lock dir(s) after reap"

# --- round2 finding 2: upsertJob failure -> repair marker -> later sweep repairs ---
# task-repair is created HERE (not in the earlier fixture batch) -- it must still be
# `queued` when the broken-COMPANION reap call below runs, so it needs to be newer than
# the round1/idempotent sweeps already executed above.
create_job "${LIB_DIR}" task-repair queued 99998 20 -
JOB_FILE_DIR="$(node -e '
(async () => {
  const [libDir, cwd] = process.argv.slice(1);
  const { resolveJobsDir } = await import(libDir + "/state.mjs");
  console.log(resolveJobsDir(cwd));
})();
' "${LIB_DIR}" "${CWD}")"
JOB_FILE="${JOB_FILE_DIR}/task-repair.json"
REPAIR_MARKER="${JOB_FILE}.repair"

# Simulate: reap_one() itself succeeds (writes jobs/task-repair.json -> failed) but
# _sync_state_index's own node call fails because COMPANION resolves to a broken lib dir.
# _codex_reap resolves lib_dir once via `dirname "$COMPANION"/lib` -- a REAL copy of the
# companion's lib dir with state.mjs deleted reproduces the EXACT failure surface (a
# broken index sync, not a broken reap): `import(libDir + "/state.mjs")` throws inside
# the node subprocess, which is a genuine failed subprocess call, not a hand-mocked stub.
cp -R "$(dirname "${LIB_DIR}")" "${SANDBOX}/companion-copy"
BROKEN_COMPANION="${SANDBOX}/companion-copy/codex-companion.mjs"
rm -f "${SANDBOX}/companion-copy/lib/state.mjs"  # break the import target for THIS copy only

# Run reap using a codex-task.sh invocation whose COMPANION resolves to the BROKEN copy
# (bypasses the `find ~/.claude/...` autodetect via PATH trick: codex-task.sh always
# re-finds COMPANION itself, so instead we call bash with a stub `find` shadowing it).
STUB_BIN_DIR="${SANDBOX}/stubbin"
mkdir -p "${STUB_BIN_DIR}"
cat > "${STUB_BIN_DIR}/find" <<EOF
#!/usr/bin/env bash
echo "${BROKEN_COMPANION}"
EOF
chmod +x "${STUB_BIN_DIR}/find"
PATH="${STUB_BIN_DIR}:${PATH}" bash "${CODEX_TASK_SH}" reap task-repair >"${SANDBOX}/reap3.out" 2>"${SANDBOX}/reap3.err" || true

if [[ -f "${REPAIR_MARKER}" ]]; then
  pass "round2 finding 2: upsertJob failure (broken lib_dir) persisted a repair marker"
else
  fail "round2 finding 2: no repair marker written despite a broken index-sync target ($(cat "${SANDBOX}/reap3.err" 2>/dev/null))"
fi
[[ "$(read_job_status task-repair)" == "failed" ]] || fail "task-repair: jobs/<id>.json should still be failed even though index sync failed"
idx_after_break="$(read_index_status task-repair)"
if [[ "${idx_after_break}" == "failed" ]]; then
  fail "round2 finding 2 setup invalid: state.json was somehow synced despite the broken lib_dir (test cannot prove the repair path)"
fi

# Now sweep again with the REAL (working) lib_dir -- the repair marker should be found
# and retried, reconciling state.json without re-reaping the job file.
bash "${CODEX_TASK_SH}" reap >"${SANDBOX}/reap4.out" 2>"${SANDBOX}/reap4.err" || true
[[ "$(read_index_status task-repair)" == "failed" ]] \
  || fail "round2 finding 2: a later sweep did not repair the state.json divergence"
[[ -f "${REPAIR_MARKER}" ]] && fail "round2 finding 2: repair marker was not removed after a successful repair"
if [[ ${FAIL} -eq 0 ]]; then :; else :; fi
pass "round2 finding 2: a later sweep with the real lib_dir reconciled the divergence and cleared the marker"

# --- round3 finding 4: marker persistence ALSO fails (not just index sync) -> reap must
#     surface this as an explicit, non-swallowed failure: nonzero exit + a stderr line,
#     not the old unconditional `exit 0` regardless of what happened inside the sweep.
#     review-wave2-verdict-5 finding 3: _write_repair_marker now falls back to
#     CODEX_REPAIR_DIR when the local (job-dir) marker write fails -- to still prove the
#     TRULY unrecoverable case, this block blocks BOTH: the local marker path (directory
#     trick, as before) AND the fallback dir itself (pre-created as a plain FILE, so
#     os.makedirs(repair_dir, exist_ok=True) raises instead of silently succeeding).
export CODEX_REPAIR_DIR="${SANDBOX}/repair-blocked"
touch "${CODEX_REPAIR_DIR}"
create_job "${LIB_DIR}" task-repair2 queued 99997 20 -
REPAIR_MARKER2="${JOB_FILE_DIR}/task-repair2.json.repair"
# Pre-create the marker PATH as a directory: _write_repair_marker's own os.replace(tmp,
# marker_path) then fails with IsADirectoryError (a real, reproducible marker-write
# failure -- not a hand-mocked stub) while reap_one()'s own job_path write (a DIFFERENT
# file) and the broken-COMPANION index-sync failure both proceed completely normally, so
# this isolates the marker-persist failure from everything else that already has coverage
# above.
mkdir -p "${REPAIR_MARKER2}"
_REAP2_RC=0
PATH="${STUB_BIN_DIR}:${PATH}" bash "${CODEX_TASK_SH}" reap task-repair2 \
  >"${SANDBOX}/reap5.out" 2>"${SANDBOX}/reap5.err" || _REAP2_RC=$?
if [[ "${_REAP2_RC}" -eq 0 ]]; then
  fail "round3 finding 4: reap exited 0 despite a repair-marker write failure"
else
  pass "round3 finding 4: reap exited nonzero (rc=${_REAP2_RC}) when a repair marker could not be persisted"
fi
if grep -q "REAP FAILED" "${SANDBOX}/reap5.out" 2>/dev/null || grep -q "REAP FAILED" "${SANDBOX}/reap5.err" 2>/dev/null; then
  pass "round3 finding 4: an explicit REAP FAILED line was emitted"
else
  fail "round3 finding 4: no explicit REAP FAILED line found (out=$(cat "${SANDBOX}/reap5.out" 2>/dev/null) err=$(cat "${SANDBOX}/reap5.err" 2>/dev/null))"
fi
grep -q "task-repair2 " "${SANDBOX}/reap5.out" 2>/dev/null \
  || fail "round3 finding 4: reap output should still list task-repair2 as reaped despite the marker failure"
[[ "$(read_job_status task-repair2)" == "failed" ]] \
  || fail "round3 finding 4: task-repair2's own job file should still be marked failed even though its marker/index diverge"
[[ -d "${REPAIR_MARKER2}" ]] \
  || fail "round3 finding 4: the pre-created marker-path directory should be untouched (proves the write genuinely failed, was not silently skipped)"

# --- round4 finding 2: the DEFAULT AUTOREAP path (every subcommand OTHER than the
#     explicit `reap` -- e.g. `status --all`) must ALSO surface a marker-persist failure,
#     not just the explicit `reap` subcommand covered by round3 finding 4 above. The old
#     `2>/dev/null || true` on this path discarded the failure entirely -- no warning, no
#     nonzero rc, nothing. `_sync_state_index` returns False (without needing a broken
#     companion) whenever a job record has no `workspaceRoot` field at all, so this fixture
#     omits it on purpose to trigger the marker-write attempt via the SAME code path as
#     round3 finding 4's index-sync failure, but without touching COMPANION -- the wrapped
#     `status --all` subcommand must keep using the REAL, working companion and succeed
#     normally regardless of what happened inside the amortized autoreap sweep.
create_job "${LIB_DIR}" task-autoreap-marker queued 99994 20 -
# create_job() above always sets workspaceRoot=CWD -- overwrite the fixture with an
# equivalent record that OMITS workspaceRoot, the exact shape reap_one() encounters when
# a job's own record never carried one (the round4 finding 2 trigger, no broken companion
# needed).
node -e '
(async () => {
  const [libDir, cwd, jobId] = process.argv.slice(1);
  const fs = await import("node:fs");
  const { resolveJobFile, writeJobFile, upsertJob } = await import(libDir + "/state.mjs");
  const existing = JSON.parse(fs.readFileSync(resolveJobFile(cwd, jobId), "utf8"));
  delete existing.workspaceRoot;
  writeJobFile(cwd, jobId, existing);
  upsertJob(cwd, existing);
})().catch((e) => { console.error(String(e)); process.exit(1); });
' "${LIB_DIR}" "${CWD}" task-autoreap-marker \
  || { echo "FIXTURE SETUP FAILED for task-autoreap-marker (strip workspaceRoot)" >&2; exit 1; }
AUTOREAP_MARKER="${JOB_FILE_DIR}/task-autoreap-marker.json.repair"
mkdir -p "${AUTOREAP_MARKER}"

AUTOREAP_OUT="$(bash "${CODEX_TASK_SH}" status --all --cwd "${CWD}" --json 2>"${SANDBOX}/autoreap.err")"
AUTOREAP_RC=$?
if [[ ${AUTOREAP_RC} -eq 0 ]]; then
  pass "round4 finding 2: the wrapped 'status --all' subcommand was NOT aborted by the autoreap marker failure (rc=0)"
else
  fail "round4 finding 2: the wrapped subcommand's own exit code was corrupted by autoreap (rc=${AUTOREAP_RC})"
fi
echo "${AUTOREAP_OUT}" | python3 -c 'import json,sys; json.load(sys.stdin)' \
  && pass "round4 finding 2: 'status --all' still returned valid JSON despite the autoreap failure" \
  || fail "round4 finding 2: 'status --all' output was not valid JSON (out=${AUTOREAP_OUT})"
if grep -q "WARNING: background autoreap failed" "${SANDBOX}/autoreap.err"; then
  pass "round4 finding 2: an explicit autoreap WARNING line was emitted on stderr"
else
  fail "round4 finding 2: no autoreap WARNING line found (err=$(cat "${SANDBOX}/autoreap.err" 2>/dev/null))"
fi
[[ "$(read_job_status task-autoreap-marker)" == "failed" ]] \
  || fail "round4 finding 2: task-autoreap-marker's own job file should still be marked failed (durable partial win) even though its marker diverges"
[[ -d "${AUTOREAP_MARKER}" ]] \
  || fail "round4 finding 2: the pre-created marker-path directory should be untouched (proves the write genuinely failed, was not silently skipped)"

# --- review-wave2-verdict-5 finding 3: fallback repair location -- upsertJob fails AND the
#     LOCAL (job-dir) marker write also fails, but a WORKING CODEX_REPAIR_DIR is available
#     (unlike round3/round4 above, which block it too, to prove the truly-unrecoverable
#     case) -- _write_repair_marker must fall back to it instead of losing the divergence,
#     and a LATER explicit reap (real, working companion) must find and reconcile the
#     fallback marker without re-reaping the job file.
export CODEX_REPAIR_DIR="${SANDBOX}/repair-fallback"
create_job "${LIB_DIR}" task-repair-fallback queued 99996 20 -
FALLBACK_JOB_FILE="${JOB_FILE_DIR}/task-repair-fallback.json"
FALLBACK_LOCAL_MARKER="${FALLBACK_JOB_FILE}.repair"
FALLBACK_MARKER="${CODEX_REPAIR_DIR}/task-repair-fallback.json"
mkdir -p "${FALLBACK_LOCAL_MARKER}"  # block ONLY the local marker path

_REAP_FB_RC=0
PATH="${STUB_BIN_DIR}:${PATH}" bash "${CODEX_TASK_SH}" reap task-repair-fallback \
  >"${SANDBOX}/reap-fb1.out" 2>"${SANDBOX}/reap-fb1.err" || _REAP_FB_RC=$?
if [[ "${_REAP_FB_RC}" -eq 0 ]]; then
  pass "review-wave2-verdict-5 finding 3: reap exited 0 -- the CODEX_REPAIR_DIR fallback absorbed the local marker-write failure"
else
  fail "review-wave2-verdict-5 finding 3: reap still failed (rc=${_REAP_FB_RC}) despite a working fallback dir (err=$(cat "${SANDBOX}/reap-fb1.err" 2>/dev/null))"
fi
[[ -f "${FALLBACK_MARKER}" ]] \
  || fail "review-wave2-verdict-5 finding 3: no fallback marker was written to CODEX_REPAIR_DIR despite the local write failing"
[[ "$(read_job_status task-repair-fallback)" == "failed" ]] \
  || fail "review-wave2-verdict-5 finding 3: task-repair-fallback's own job file should be failed after the initial reap"
idx_before_fb_fix="$(read_index_status task-repair-fallback)"
if [[ "${idx_before_fb_fix}" == "failed" ]]; then
  fail "review-wave2-verdict-5 finding 3 setup invalid: state.json was somehow synced despite the broken lib_dir (test cannot prove the fallback reconcile path)"
fi

# Sweep again with the REAL (working) lib_dir/companion -- the fallback marker should be
# found and retried, reconciling state.json without re-reaping the job file.
bash "${CODEX_TASK_SH}" reap >"${SANDBOX}/reap-fb2.out" 2>"${SANDBOX}/reap-fb2.err" || true
[[ "$(read_index_status task-repair-fallback)" == "failed" ]] \
  || fail "review-wave2-verdict-5 finding 3: a later sweep did not reconcile state.json via the fallback marker"
if [[ -f "${FALLBACK_MARKER}" ]]; then
  fail "review-wave2-verdict-5 finding 3: fallback marker was not removed after a successful reconcile"
fi
pass "review-wave2-verdict-5 finding 3: fallback repair marker persisted and later reconciled by a working sweep"

if [[ ${FAIL} -eq 0 ]]; then
  echo 'PASS: codex-task.sh reap (findings 1/2/9, idempotent, repair-marker reconciliation, round3 marker-write-failure, round4 default-autoreap-wrapper-path, wave2v5 fallback-repair-dir reconcile)'
  exit 0
fi
exit 1
