#!/bin/bash
set -euo pipefail
# Codex convenience wrapper — finds codex-companion.mjs and forwards all args
# Zero Claude tokens consumed. Uses OpenAI/Codex tokens.
#
# Usage:
#   codex-task.sh task "review my approach for X"
#   codex-task.sh adversarial-review --wait
#   codex-task.sh adversarial-review --wait --tier top     # pin to gpt-5.6 tier
#   codex-task.sh status [job-id]
#   codex-task.sh result [job-id]
#   codex-task.sh cancel [job-id]
#
# --tier <top|standard|volume>  Resolves to a Codex model (+ effort where the
#   subcommand accepts one) using the SAME tier table as leadv2-codex-planner.sh:
#     top      -> gpt-5.6-sol/high, falls back to gpt-5.6-terra/xhigh if sol is
#                 absent from ~/.codex/models_cache.json (gov-gated)
#     standard -> gpt-5.6-terra/medium  (EFFORT-RECAL 2026-07-10, was /high)
#     volume   -> gpt-5.6-luna/low      (EFFORT-RECAL 2026-07-10, was /medium)
#   Applies to `task` (model+effort) and `adversarial-review`/`review`
#   (model only — codex-companion's review command does not accept --effort;
#   passing it there would corrupt the focus-text positionals). Ignored (WARN)
#   for any other subcommand. An explicit --model already on the command line
#   always wins over --tier.
#
# --wait  Real flag in ANY position (P0, CODEX-WAIT-AND-TIER-01). Stripped here
#   so it never lands in the prompt (codex-companion `task` has no --wait option
#   and would fold it into the prompt text). Forces the FOREGROUND blocking path
#   for `task`/`review` (strips --background) so the wrapper blocks until the job
#   reaches a terminal state — the only way a long Codex job survives, since a
#   job dies the instant its launching client drops the app-server connection.
#   `adversarial-review` always blocks already (auto-injected for companion).
#
# --reason "<text>"  REQUIRED by --tier top (P1). `top` is the scarce Codex tier
#   (adversarial review + Heavy/arch plans); standard is the default, volume for
#   mechanical/bulk. Without --reason, --tier top exits non-zero.
#
# Output filter: by default strips codex-companion's noisy [codex] meta lines
# (Running command / Command completed / Calling ... / Tool ... completed/failed /
# Assistant message captured — mid-stream previews).
# Kept: pure content (the final Findings/verdict body that has no [codex] prefix).
# Override: CODEX_VERBOSE=1 to see all meta lines.

COMPANION=$(find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs -path "*/scripts/*" 2>/dev/null | sort -V | tail -1)

if [[ -z "$COMPANION" ]]; then
  echo "ERROR: codex-companion.mjs not found. Is the Codex plugin installed?" >&2
  exit 1
fi

# ── T-f (CODEX-REAP-01) -- hung jobs die without a babysitter ──────────────
# Known hole (tf-diagnosis.md): the zombie reaper (codex-guard.sh TF-02) only
# runs inside an active guard poll. A job stuck `queued` with a dead pid, or
# `running` whose pid died, stays "running" forever in the job store when no
# guard happens to be watching it. `_codex_reap` gives every codex-task.sh
# invocation its own babysitter sweep -- no cron, no daemon.
#
# CODEX_AUTOREAP=1 (default) -- runs the sweep at the top of every subcommand
# (amortized: the next interaction sweeps first). =0 disables it entirely
# (byte-identical to pre-T-f behavior; only an active codex-guard.sh or an
# explicit `codex-task.sh reap` call reaps anything).
# CODEX_QUEUED_KILL_MIN=15   -- a `queued` job with no live pid past this age is dead.
# CODEX_RUNNING_DEAD_KILL_MIN=5 -- a `running` job whose pid died past this age is dead.
CODEX_REAP_STATE_ROOT="${CODEX_GUARD_STATE_ROOT:-$HOME/.claude/plugins/data/codex-openai-codex/state}"
CODEX_QUEUED_KILL_MIN="${CODEX_QUEUED_KILL_MIN:-15}"
CODEX_RUNNING_DEAD_KILL_MIN="${CODEX_RUNNING_DEAD_KILL_MIN:-5}"
CODEX_AUTOREAP="${CODEX_AUTOREAP:-1}"
# review-wave2-verdict-5 finding 3: a repair marker written next to the job file can itself
# fail (directory unwritable, disk full, the job dir gone entirely) -- an independent
# fallback location, outside the job store, gives a repair a second place to land so a
# later `reap` still has something to reconcile against instead of nothing.
CODEX_REPAIR_DIR="${CODEX_REPAIR_DIR:-$HOME/.claude/cache/codex-repair}"

# _codex_reap [job_id] -- scans $CODEX_REAP_STATE_ROOT (or just one job's file
# when job_id is given, forcing the age check regardless of elapsed time) for
# jobs stuck without a live babysitter and marks them terminal failed with a
# reap cause. Participates in the SAME mkdir-lock + owner.pid provably-stale
# protocol as state.mjs's withJobFileLock (JOB-LOCK-SHARED-01) and
# codex-guard.sh's acquire_job_lock -- one shared cross-process mutex, not a
# 4th convention. Prints "<jobId> <cause>" per job it reaps; silent (no
# output) when nothing needed reaping.
_codex_reap() {
  local target="${1:-}" _lib_dir
  _lib_dir="$(dirname "$COMPANION")/lib"
  python3 - "$CODEX_REAP_STATE_ROOT" "$CODEX_QUEUED_KILL_MIN" "$CODEX_RUNNING_DEAD_KILL_MIN" "$target" "$_lib_dir" "$CODEX_REPAIR_DIR" <<'PY'
import json, os, shutil, subprocess, sys, time
from datetime import datetime, timezone

state_root, queued_kill_min, running_kill_min, target, lib_dir, repair_dir = (
    sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6],
)


def parse_iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pid_alive(pid):
    if pid is None:
        return False
    try:
        os.kill(int(pid), 0)
        return True
    except (ProcessLookupError, ValueError):
        return False
    except PermissionError:
        return True  # exists, owned elsewhere -- can't prove dead, never reap


def lock_owner(lock_dir):
    try:
        with open(os.path.join(lock_dir, "owner.pid")) as f:
            return int(f.read().strip())
    except Exception:
        return None


def acquire_lock(job_path):
    lock_dir = job_path + ".lock"
    waited = 0
    while True:
        try:
            os.mkdir(lock_dir)
        except FileExistsError:
            try:
                age = time.time() - os.stat(lock_dir).st_mtime
            except FileNotFoundError:
                continue
            if age > 60:
                owner = lock_owner(lock_dir)
                if owner is None or not pid_alive(owner):
                    shutil.rmtree(lock_dir, ignore_errors=True)
                    continue
            if waited >= 100:  # ~10s at 0.1s/poll
                return None
            time.sleep(0.1)
            waited += 1
            continue
        try:
            with open(os.path.join(lock_dir, "owner.pid"), "w") as f:
                f.write(str(os.getpid()))
        except Exception:
            pass
        return lock_dir


def release_lock(lock_dir):
    if lock_dir:
        shutil.rmtree(lock_dir, ignore_errors=True)


# wave2 finding 2: kill_leftover_group used to run getpgid/killpg on a pid that had
# JUST answered dead to kill(pid, 0) above -- but a dead pid can be reused by the OS
# for an unrelated process between that check and the getpgid/killpg calls a moment
# later, with no birth-time token here to prove it is still the SAME process this job
# ever spawned. That window lets a reap kill a completely unrelated process group
# while still failing to clean up the actual orphan (which, by definition, is no
# longer at that pid). Removed entirely rather than guarded: validating process
# identity would need a persisted birth-time/start-token per pid, which is more
# machinery than an orphan-cleanup safety net is worth; a leftover child process is
# the strictly safer failure mode than killing the wrong one.


def _sync_state_index(job_id, workspace_root, patch, lib_dir):
    # wave2 finding 1: the reaper used to rewrite ONLY jobs/<id>.json. status/result/
    # resume all discover jobs through state.json (state.mjs's listJobs/loadState), so a
    # reaped job stayed "queued"/"running" in every normal interface even though its own
    # job file said failed. Patch the SAME canonical index through the plugin's own
    # upsertJob() (state.mjs) -- the ONE writer every other caller already goes through
    # (mirrors `_record_spawn_failure`'s own dynamic-import pattern below) -- rather than
    # a second, drifting reimplementation of state.json's shape in Python. Best-effort:
    # workspaceRoot is read straight off the job record; a job with none (or no lib_dir
    # resolved) skips the index sync silently -- the per-job file write already landed,
    # so this is a partial win, not a failure to escalate.
    #
    # wave2 round2 finding 2: `check=False` + the node script's own `process.exit(0)` on
    # catch used to mean this NEVER reported failure -- an upsertJob error or subprocess
    # timeout was silently swallowed and the caller had no way to tell state.json stayed
    # stale. The script now exits 1 on failure and this returns a real bool so the caller
    # can persist a repair marker instead of losing the divergence.
    if not workspace_root or not lib_dir:
        return False
    script = (
        "(async () => {"
        "const [libDir, cwd, patchJson] = process.argv.slice(1);"
        "const { upsertJob } = await import(libDir + '/state.mjs');"
        "await upsertJob(cwd, JSON.parse(patchJson));"
        "})().catch((e) => {"
        "process.stderr.write('[codex-task] WARN: reap could not sync state index: '"
        " + (e && e.message ? e.message : e) + \"\\n\");"
        "process.exit(1);"
        "});"
    )
    try:
        proc = subprocess.run(
            ["node", "-e", script, lib_dir, workspace_root, json.dumps(patch)],
            check=False, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return proc.returncode == 0
    except Exception:
        return False


def _repair_marker_path(job_path):
    return f"{job_path}.repair"


def _fallback_marker_path(repair_dir, job_id):
    return os.path.join(repair_dir, f"{job_id}.json")


def _write_marker_file(marker_path, payload):
    tmp = f"{marker_path}.tmp.{os.getpid()}"
    try:
        os.makedirs(os.path.dirname(marker_path), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, marker_path)
        return True
    except Exception as e:
        try:
            os.remove(tmp)
        except Exception:
            pass
        return e


def _write_repair_marker(job_path, job_id, workspace_root, patch, repair_dir):
    # wave2 round2 finding 2: persisted next to the job file (same dir, same lock
    # discipline) so a later sweep -- possibly a different process -- can find and
    # retry it without needing to re-derive job_id/workspaceRoot/patch from scratch.
    #
    # wave2 round3 finding 4: this is the LAST line of defense against a permanent
    # state.json/index divergence (upsertJob already failed once, in _sync_state_index,
    # by the time this is called) -- swallowing a write/rename failure here silently
    # meant the divergence could never be recovered, by this process or any later sweep,
    # with no trace it ever happened. Returns True/False instead of always succeeding
    # silently; the caller surfaces False as an explicit reap failure (see below).
    #
    # review-wave2-verdict-5 finding 3: a job-dir-local marker can share the SAME failure
    # mode that broke the index sync in the first place (unwritable dir, disk full, the
    # job store itself gone) -- CODEX_REPAIR_DIR is an INDEPENDENT location, so it is tried
    # whenever the local write fails, giving a later `reap` a second place to look before
    # this divergence is declared unrecoverable.
    marker_path = _repair_marker_path(job_path)
    payload = {"jobId": job_id, "workspaceRoot": workspace_root, "patch": patch}
    local_err = _write_marker_file(marker_path, payload)
    if local_err is True:
        return True
    fallback_path = _fallback_marker_path(repair_dir, job_id)
    fallback_err = _write_marker_file(fallback_path, payload)
    if fallback_err is True:
        sys.stderr.write(
            f"[codex-task] WARN: repair marker for job {job_id} could not be written "
            f"at {marker_path} ({local_err}); persisted to fallback location "
            f"{fallback_path} instead\n"
        )
        return True
    sys.stderr.write(
        f"[codex-task] ERROR: could not persist repair marker for job {job_id} "
        f"at {marker_path} ({local_err}) or fallback {fallback_path} ({fallback_err})\n"
    )
    return False


def _retry_one_marker(marker_path, lib_dir):
    try:
        with open(marker_path) as f:
            payload = json.load(f)
    except Exception:
        return None
    job_id = payload.get("jobId")
    workspace_root = payload.get("workspaceRoot")
    patch = payload.get("patch")
    if not job_id or not patch:
        try:
            os.remove(marker_path)
        except Exception:
            pass
        return None
    if _sync_state_index(job_id, workspace_root, patch, lib_dir):
        try:
            os.remove(marker_path)
        except Exception:
            pass
        return job_id
    return None


def _retry_repair_markers(state_root, lib_dir, repair_dir):
    # wave2 round2 finding 2: runs BEFORE the normal sweep on every invocation (not just
    # when CODEX_AUTOREAP fires a new reap) so a prior sync failure gets reconciled even
    # if no new job needs reaping this round.
    #
    # review-wave2-verdict-5 finding 3: also consumes markers persisted to the independent
    # CODEX_REPAIR_DIR fallback (written when the job-dir-local marker itself failed) --
    # same reconciliation, second source.
    repaired = []
    for root, _dirs, files in os.walk(state_root):
        if os.path.basename(root) != "jobs":
            continue
        for name in files:
            if not name.endswith(".repair"):
                continue
            job_id = _retry_one_marker(os.path.join(root, name), lib_dir)
            if job_id:
                repaired.append(job_id)
    if os.path.isdir(repair_dir):
        for name in os.listdir(repair_dir):
            if not name.endswith(".json"):
                continue
            job_id = _retry_one_marker(os.path.join(repair_dir, name), lib_dir)
            if job_id:
                repaired.append(job_id)
    return repaired


def reap_one(job_path, force=False):
    lock_dir = acquire_lock(job_path)
    if lock_dir is None:
        return None  # lock contended by a live holder -- try again next sweep
    try:
        try:
            with open(job_path) as f:
                data = json.load(f)
        except Exception:
            return None

        status = data.get("status")
        if status not in ("queued", "running"):
            return None

        pid = data.get("pid")
        has_pid = pid is not None and str(pid).strip() != ""
        if has_pid and pid_alive(pid):
            return None  # ALIVE -- untouched, no exceptions

        now = time.time()
        cause = None
        if status == "queued":
            created = parse_iso(data.get("createdAt"))
            age_min = ((now - created) / 60) if created else None
            if force or (age_min is not None and age_min >= queued_kill_min):
                cause = f"queued_timeout_{queued_kill_min:g}min"
        elif not has_pid:
            # wave2 finding 9: `running` with no pid EVER recorded never had a worker
            # attached at all -- treat it like a stalled queued job (same grace period
            # off createdAt) instead of the tighter dead-worker threshold below, which
            # assumes a worker started and then died (a stronger claim than this state
            # supports).
            created = parse_iso(data.get("createdAt"))
            age_min = ((now - created) / 60) if created else None
            if force or (age_min is not None and age_min >= queued_kill_min):
                cause = f"running_no_pid_timeout_{queued_kill_min:g}min"
        else:
            ref = parse_iso(data.get("startedAt")) or parse_iso(data.get("createdAt"))
            age_min = ((now - ref) / 60) if ref else None
            if force or (age_min is not None and age_min >= running_kill_min):
                cause = "worker_died_stale"

        if cause is None:
            return None

        job_id = os.path.basename(job_path)[:-5]
        completed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        data["status"] = "failed"
        data["phase"] = "failed"
        data["pid"] = None
        data["errorMessage"] = f"reaped: {cause}"
        data["completedAt"] = completed_at

        tmp = f"{job_path}.tmp.{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, job_path)
        patch = {
            "id": job_id,
            "status": "failed",
            "phase": "failed",
            "pid": None,
            "errorMessage": f"reaped: {cause}",
            "completedAt": completed_at,
        }
        return (job_id, cause, data.get("workspaceRoot"), patch)
    finally:
        release_lock(lock_dir)


# wave2 round2 finding 2: reconcile any file/index divergence left by a PRIOR sweep's
# failed upsertJob before reaping anything new this round.
_retry_repair_markers(state_root, lib_dir, repair_dir)

reaped = []
_marker_persist_failed = False
for root, _dirs, files in os.walk(state_root):
    if os.path.basename(root) != "jobs":
        continue
    for name in files:
        if not name.endswith(".json"):
            continue
        job_id = name[:-5]
        if target and job_id != target:
            continue
        job_path = os.path.join(root, name)
        result = reap_one(job_path, force=bool(target))
        if result:
            reaped_job_id, cause, workspace_root, patch = result
            # Runs AFTER reap_one's own `finally: release_lock(...)` above -- upsertJob
            # never touches the per-job-file lock (only writeJobFile does), so there is
            # no lock-reentry/deadlock risk calling it here.
            if not _sync_state_index(reaped_job_id, workspace_root, patch, lib_dir):
                if not _write_repair_marker(job_path, reaped_job_id, workspace_root, patch, repair_dir):
                    _marker_persist_failed = True
            reaped.append((reaped_job_id, cause))

for job_id, cause in reaped:
    print(f"{job_id} {cause}")

# wave2 round3 finding 4: the job itself WAS reaped (status=failed already landed in
# job_path above) -- what is at risk is only the state.json index + this last-resort
# retry marker, and that risk must not be invisible. Exit nonzero + an explicit stderr
# line whenever ANY repair marker failed to persist this round, instead of always
# returning 0 regardless of what happened inside this sweep.
if _marker_persist_failed:
    sys.stderr.write(
        "[codex-task] ERROR: reap completed but a repair marker failed to persist -- "
        "state.json index divergence for one or more jobs may be permanent without "
        "manual reconciliation (see the marker-specific error above)\n"
    )
    sys.exit(1)
PY
}

# _record_spawn_failure <cwd> <error-text> -- CODEX-REAP-01 item 3 (spawn
# failure visibility). When a background dispatch's launcher output carries
# no parseable jobId (the "no live job record" case: codex-companion never
# even reached its own writeJobFile), nothing tracks the failure and it
# vanishes -- no job.json, no guard armed, no /codex:status entry. This
# writes a synthetic terminal job record via the plugin's OWN state.mjs
# functions (generateJobId/writeJobFile/upsertJob), so the failure shows up
# in `codex-task.sh status --all` like any other job instead of disappearing.
# Uses the plugin's exported API only -- no mjs file is edited or patched.
_record_spawn_failure() {
  local cwd="$1" errtext="$2" lib_dir
  lib_dir="$(dirname "$COMPANION")/lib"
  node -e '
(async () => {
  const [libDir, cwd, err] = process.argv.slice(1);
  const { generateJobId, writeJobFile, upsertJob } = await import(libDir + "/state.mjs");
  const jobId = generateJobId("spawnfail");
  const now = new Date().toISOString();
  const record = {
    id: jobId,
    status: "failed",
    phase: "failed",
    kind: "spawn-failure",
    kindLabel: "spawn-failure",
    jobClass: "task",
    pid: null,
    createdAt: now,
    completedAt: now,
    errorMessage: "spawn_failed: " + String(err).slice(0, 500)
  };
  writeJobFile(cwd, jobId, record);
  upsertJob(cwd, record);
  console.error("[codex-task] recorded spawn failure as " + jobId + " (job store, status=failed cause=spawn_failed)");
})().catch((e) => {
  console.error("[codex-task] WARN: could not record spawn failure to job store: " + (e && e.message ? e.message : e));
  process.exit(0);
});
' "$lib_dir" "$cwd" "$errtext"
}

# ── --tier extraction (must run before the spark ban + subcommand dispatch,
# since codex-companion has no concept of --tier — it only understands
# --model/--effort). Strip --tier out of "$@" and resolve it to concrete
# --model/--effort values, identical resolution table to leadv2-codex-planner.sh.
# Strip --tier / --reason / --wait out of "$@" (every position) so codex-companion
# never sees them folded into the prompt. codex-companion understands only
# --model/--effort and (for review subcommands) --wait/--background -- `task` has
# NO --wait option, so an unstripped --wait lands verbatim in the prompt text and
# the call returns immediately (the CODEX-WAIT-AND-TIER-01 P0 bug).
_TIER=""
_REASON=""
_WAIT=0
_pre_args=()
_i=1
while [[ $_i -le $# ]]; do
  _arg="${!_i}"
  case "$_arg" in
    --tier|--tier=*)
      if [[ "$_arg" == --tier=* ]]; then _TIER="${_arg#--tier=}"; else _i=$((_i + 1)); _TIER="${!_i:-}"; fi ;;
    --reason|--reason=*)
      if [[ "$_arg" == --reason=* ]]; then _REASON="${_arg#--reason=}"; else _i=$((_i + 1)); _REASON="${!_i:-}"; fi ;;
    --wait|--wait=*)
      _WAIT=1 ;;
    *)
      _pre_args+=("$_arg") ;;
  esac
  _i=$((_i + 1))
done
set -- "${_pre_args[@]}"

# P1 (CODEX-WAIT-AND-TIER-01) -- --tier top must earn its cost. Measured before
# this gate: 17 runs on top (Sol), 9 on standard (Terra), 0 on volume (Luna) --
# 65% on the priciest tier, burning Codex to 27%. `top` is the scarce tier
# (adversarial review + Heavy/arch plans ONLY); standard is the default, volume
# for mechanical/bulk. Sol->Terra-ultra gov-gated fallback (below) is unaffected
# -- it fires on _TIER=="top" regardless of which model resolves. standard/volume
# pass through unchanged.
if [[ "${_TIER:-}" == "top" && -z "${_REASON:-}" ]]; then
  cat >&2 <<'EOF'
[codex-task] REFUSED: --tier top requires --reason "<why this run earns top>".
  Founder rule (CODEX-WAIT-AND-TIER-01): `top` (Sol -> Terra-ultra) is the scarce
  Codex tier, reserved for adversarial review + Heavy/arch plans. Default is
  `standard` (Terra/medium); use `volume` (Luna/low) for mechanical/bulk work.
  Re-run with --reason "<text>" to attest this run earns top, or drop --tier.
EOF
  exit 2
fi

SUB="${1:-}"

# `codex-task.sh reap` -- explicit manual sweep (not a real codex-companion
# subcommand, intercepted here before anything is forwarded to node).
if [[ "$SUB" == "reap" ]]; then
  # wave2 round3 finding 4: capture the sweep's own exit code explicitly (the `||`
  # keeps this line exempt from `set -e` so a nonzero rc is reported, not silently
  # aborting before the reaped-jobs output below is ever printed) -- a repair-marker
  # persistence failure inside _codex_reap now surfaces here as a real reap failure,
  # not an unconditional success.
  _REAP_RC=0
  _REAP_OUT="$(_codex_reap)" || _REAP_RC=$?
  if [[ -n "$_REAP_OUT" ]]; then
    printf 'reaped:\n%s\n' "$_REAP_OUT"
  else
    echo "no stale jobs found"
  fi
  if [[ "$_REAP_RC" -ne 0 ]]; then
    echo "[codex-task] REAP FAILED: a repair marker could not be persisted for one or more jobs -- state.json index divergence needs manual reconciliation (see stderr above)" >&2
    exit "$_REAP_RC"
  fi
  exit 0
fi

# CODEX_AUTOREAP (default 1): every other subcommand sweeps the job store
# first, amortized -- this is the "no cron, no daemon" automatic caller the
# fix requires. Best-effort: never blocks or fails the real subcommand.
#
# wave2 round4 finding 2: the old `2>/dev/null || true` here discarded BOTH the repair-
# marker failure detail AND its exit code -- unlike the explicit `reap` subcommand above
# (round3 finding 4), this amortized path left a marker-persistence failure with literally
# no operator signal, silent even by CODEX_VERBOSE=1's standard. `|| _AUTOREAP_RC=$?` is the
# same errexit-exempt idiom as the explicit reap call site: it captures the real rc without
# ever aborting the requested subcommand (still best-effort). The marker file itself (or the
# lack of one) is the durable state note -- _write_repair_marker/_retry_repair_markers
# already persist/retry it on disk regardless of this wrapper's own redirection; this fix
# only restores VISIBILITY of that failure to whoever is watching stderr.
if [[ "$CODEX_AUTOREAP" == "1" ]]; then
  _AUTOREAP_RC=0
  # review-wave2-verdict-5 finding 3: the old `2>/dev/null` here discarded the marker-
  # specific ERROR line (job id + job file path) _write_repair_marker already writes to
  # stderr, leaving the WARNING below with no way to say WHICH job needs attention.
  # Captured to a tempfile instead so those lines can be surfaced alongside it.
  _AUTOREAP_ERRFILE="$(mktemp 2>/dev/null || printf '%s/.codex-autoreap-err.%s' "${TMPDIR:-/tmp}" "$$")"
  _AUTOREAP_OUT="$(_codex_reap 2>"$_AUTOREAP_ERRFILE")" || _AUTOREAP_RC=$?
  if [[ -n "$_AUTOREAP_OUT" && "${CODEX_VERBOSE:-0}" == "1" ]]; then
    printf '[codex-task] autoreap:\n%s\n' "$_AUTOREAP_OUT" >&2
  fi
  if [[ "$_AUTOREAP_RC" -ne 0 ]]; then
    echo "[codex-task] WARNING: background autoreap failed (rc=${_AUTOREAP_RC}) -- a repair marker could not be persisted for one or more jobs; run 'codex-task.sh reap' to see details and retry" >&2
    # Round-6 review: unguarded grep exits 1/2 under set -e when the marker line is absent
    # or the errfile is unreadable, aborting the WRAPPED command -- diagnostics must never
    # outrank the requested subcommand.
    grep -E '^\[codex-task\] ERROR: could not persist repair marker' "$_AUTOREAP_ERRFILE" >&2 2>/dev/null || true
  fi
  rm -f "$_AUTOREAP_ERRFILE" 2>/dev/null
fi

# ST-2 — direct Codex tasks do not pass through dispatch-code.sh, so give them
# the same blocking-question protocol here. Dispatch missions already contain
# it; do not append a duplicate in that path.
if [[ "$SUB" == "task" && " $* " != *"leadv2-ask.sh"* ]]; then
  _QUESTION_TASK_ID="${LEADV2_TASK_ID:-codex-task}"
  _QUESTION_PROTOCOL="

---
If you hit a decision you cannot safely make yourself, call the blocking
question channel and wait for the answer rather than guessing:
  bash \"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-ask.sh\" \"${_QUESTION_TASK_ID}\" \"<question>\" \\
    --option \"a|<reversible label>\" --option \"b|<label>\" --default-option \"a\" [--timeout <sec=1800>]
Every question must name its clearly reversible option with --default-option,
so a timeout proceeds visibly and never holds a lane. Do not use this for
routine progress or confirmation-seeking."
  set -- "$@" "${_QUESTION_PROTOCOL}"
fi

# EFFICIENCY-TUNE-01 C: job registry for supervise-loop stall detection.
# One line per spawn: /tmp/leadv2-job-registry/<session_id>/<job_id> = "run_dir\tstarted_at\tkind".
# Registry-clear rides the wrapper's own EXIT trap — the completion point that
# actually exists in this synchronous/--wait wrapper (foreground `node` call
# returning). Detached `--background` dispatches exit the wrapper immediately
# after parsing jobId, so their registry entry is cleared then too — no
# completion-tracking regression vs today (background completion is already
# tracked separately via codex-guard.sh's jobId watch, not this registry).
if [[ "$SUB" == "task" || "$SUB" == "review" || "$SUB" == "adversarial-review" ]]; then
  _JOB_REG_SID="${CLAUDE_SESSION_ID:-nosession}"
  _JOB_REG_DIR="/tmp/leadv2-job-registry/${_JOB_REG_SID}"
  _JOB_REG_ID="${SUB}-$(date +%s)-$$"
  mkdir -p "$_JOB_REG_DIR" 2>/dev/null \
    && printf -- '%s\t%s\t%s\n' "$PWD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "codex" \
       > "${_JOB_REG_DIR}/${_JOB_REG_ID}" 2>/dev/null || true
  trap 'rm -f "${_JOB_REG_DIR}/${_JOB_REG_ID}" 2>/dev/null || true' EXIT
fi

# P0 (CODEX-WAIT-AND-TIER-01) -- --wait forces foreground blocking. `task`/
# `review` detach ONLY with --background; without it they already block in the
# foreground (codex-companion runForegroundCommand holds the app-server
# connection until the job reaches a terminal state). So when --wait is set we
# strip --background to guarantee the blocking path -- a backgrounded --wait is
# contradictory and the job dies the instant the launcher returns (proven: 5
# launch methods -> 5 deaths). adversarial-review already auto-injects --wait
# for companion below, so it is unaffected here.
if [[ "${_WAIT:-0}" -eq 1 && ( "${SUB:-}" == "task" || "${SUB:-}" == "review" ) ]]; then
  _bg_seen=0
  _wa_args=()
  for _a in "$@"; do
    if [[ "$_a" == "--background" ]]; then
      _bg_seen=1
    else
      _wa_args+=("$_a")
    fi
  done
  if [[ "$_bg_seen" -eq 1 ]]; then
    set -- "${_wa_args[@]}"
    echo "[codex-task] --wait set: stripping --background -- running foreground and blocking until terminal state (a backgrounded --wait would die on launcher exit)" >&2
  fi
fi

_has_flag() {
  # _has_flag <long> <short> "$@" -- true if either flag literal is present
  local long="$1" short="$2"; shift 2
  for _a in "$@"; do
    [[ "$_a" == "$long" || ( -n "$short" && "$_a" == "$short" ) ]] && return 0
  done
  return 1
}

if [[ -n "$_TIER" ]]; then
  MODELS_CACHE="${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}"
  case "$_TIER" in
    top)
      if command -v jq >/dev/null 2>&1 && [[ -f "$MODELS_CACHE" ]] \
         && jq -e '.models[]? | select(.slug=="gpt-5.6-sol")' "$MODELS_CACHE" >/dev/null 2>&1; then
        TIER_MODEL="gpt-5.6-sol"; TIER_EFFORT="high"
      else
        # lean: sol is gov-gated and currently absent from models_cache.json --
        # fall back to terra/ultra. upgrade when sol lands on this plan.
        TIER_MODEL="gpt-5.6-terra"; TIER_EFFORT="ultra"
      fi
      ;;
    standard)
      # EFFORT-RECAL 2026-07-10 (OpenAI 5.6: one-level-lower holds quality; rollback: standard=high, volume=medium)
      TIER_MODEL="gpt-5.6-terra"; TIER_EFFORT="medium"
      ;;
    volume)
      # EFFORT-RECAL 2026-07-10 (OpenAI 5.6: one-level-lower holds quality; rollback: standard=high, volume=medium)
      TIER_MODEL="gpt-5.6-luna"; TIER_EFFORT="low"
      ;;
    *)
      echo "[codex-task] unknown --tier: $_TIER (expected top|standard|volume)" >&2
      exit 1
      ;;
  esac
  # codex-companion only accepts {none,minimal,low,medium,high,xhigh} on the wire --
  # "ultra" is a logical top-tier label only. Same translation as the planner.
  WIRE_EFFORT="$TIER_EFFORT"
  [[ "$WIRE_EFFORT" == "ultra" ]] && WIRE_EFFORT="xhigh"

  case "$SUB" in
    adversarial-review|review)
      if _has_flag --model -m "$@"; then
        echo "[codex-task] --tier ignored: explicit --model already present" >&2
      else
        set -- "$@" --model "$TIER_MODEL"
      fi
      echo "[codex-task] tier=$_TIER -> model=$TIER_MODEL (sub=$SUB; review has no --effort wire)" >&2
      ;;
    task)
      if _has_flag --model -m "$@"; then
        echo "[codex-task] --tier ignored: explicit --model already present" >&2
      else
        set -- "$@" --model "$TIER_MODEL"
      fi
      if _has_flag --effort "" "$@"; then
        echo "[codex-task] --tier effort ignored: explicit --effort already present" >&2
      else
        set -- "$@" --effort "$WIRE_EFFORT"
      fi
      echo "[codex-task] tier=$_TIER -> model=$TIER_MODEL effort=$WIRE_EFFORT (sub=$SUB)" >&2
      ;;
    *)
      echo "[codex-task] WARN: --tier has no effect on subcommand '$SUB' -- ignoring" >&2
      ;;
  esac
fi

# Hard ban: spark is never used in this project (founder directive 2026-04-28).
# Reject both the CLI alias ("spark") and its resolved model id
# (gpt-5.3-codex-spark, per codex-companion.mjs MODEL_ALIASES) so a caller can't
# route around the ban by passing the resolved slug directly (H4).
for ((_i = 1; _i <= $#; _i++)); do
  if [[ "${!_i}" == "--model" || "${!_i}" == "-m" ]]; then
    _next=$((_i + 1))
    _next_val="${!_next:-}"
    if [[ "$_next_val" == "spark" || "$_next_val" == "gpt-5.3-codex-spark" ]]; then
      echo "[codex-task] spark model is banned in this project. Use default (gpt-5.5) or --tier <top|standard|volume>." >&2
      exit 1
    fi
  fi
done

# Default (no --tier given): plugin 1.0.4 (codex-plugin-cc#270) ships gpt-5.5
# with working structured output for adversarial-review -- empirically verified
# 2026-04-28. No model pin in that case; codex-companion inherits its default
# model (gpt-5.5). --tier (above) is the only thing that pins a model now --
# keep this comment in sync if the default model changes.

# adversarial-review MUST run synchronously. Without --wait, codex-companion starts an
# async job and returns immediately — the findings land in the plugin job-log and the
# caller's captured stdout gets only the start banner (the 2026-05-17 empty-output bug).
# Auto-inject --wait so the wrapper always blocks and the full review reaches stdout.
if [[ "$SUB" == "adversarial-review" ]]; then
  _has_wait=0
  for _a in "$@"; do [[ "$_a" == "--wait" ]] && _has_wait=1; done
  [[ "$_has_wait" -eq 0 ]] && set -- "$@" --wait

  # G2 -- default findings cap
  _MAX_FINDINGS="${CODEX_MAX_FINDINGS:-8}"
  _CAP_PREFIX="Review ONLY the changed files in the diff. Return at most ${_MAX_FINDINGS} findings, Critical/High severity only, one sentence each, with file:line. If a zone is clean say 'clean' -- do not pad."
  _new_args=()
  _found_focus=0
  # Bash positional params are 1-indexed ($1..$#); $0 is the script path.
  # Iterate [1, $#] inclusive -- starting at 0 forwarded $0 as the subcommand
  # ("Unknown subcommand: <path>") and dropped the final arg.
  _idx=1
  while [[ $_idx -le $# ]]; do
    _arg="${!_idx}"
    _idx=$((_idx + 1))
    if [[ "$_arg" == "--focus" ]]; then
      _found_focus=1
      _next_val="${!_idx:-}"
      _idx=$((_idx + 1))
      _new_args+=("--focus" "${_CAP_PREFIX} ${_next_val}")
    else
      _new_args+=("$_arg")
    fi
  done
  if [[ "$_found_focus" -eq 0 ]]; then
    _new_args+=("--focus" "$_CAP_PREFIX")
  fi
  set -- "${_new_args[@]}"

fi


# G1 -- hard timeout + auto-kill
# Controlled by CODEX_TIMEOUT env (default 600). Override per-repo via
# codex_review_timeout_sec in codex-policy.yaml.
#
# D-g tier-aware default (SUPERVISE-V2-01 item 5): a flat 600s default killed
# a --tier top (sol/high) run mid-work this session -- heavier tiers need
# more wall-clock. An EXPLICIT CODEX_TIMEOUT always wins over the tier
# default (never silently overridden).
if [[ -n "${CODEX_TIMEOUT:-}" ]]; then
  _CODEX_TIMEOUT="$CODEX_TIMEOUT"
else
  case "$_TIER" in
    top)      _CODEX_TIMEOUT=1800 ;;
    standard) _CODEX_TIMEOUT=900 ;;
    *)        _CODEX_TIMEOUT=600 ;;
  esac
fi
if command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_CMD="timeout"
else
  _TIMEOUT_CMD=""
fi
_run_node() {
  local _exit_code=0
  if [[ -n "$_TIMEOUT_CMD" ]]; then
    "$_TIMEOUT_CMD" "$_CODEX_TIMEOUT" node "$COMPANION" "$@" || _exit_code=$?
  else
    # M4/Codex#3 (SUPERVISE-V2-01 fix-1): stock macOS ships neither gtimeout
    # nor timeout(1) -- the wrapper used to silently run node with NO deadline
    # at all, making the tier-aware CODEX_TIMEOUT + exit-124 auto-retry
    # completely inert. Loud WARN + a portable bash fallback (background
    # sleep+kill watcher) that enforces the SAME deadline contract and
    # explicitly reports it as exit 124, same as gtimeout/timeout(1) would.
    printf '[codex-task] WARN: neither gtimeout nor timeout(1) on PATH -- enforcing the %ss deadline via a portable sleep+kill watcher instead. Install coreutils (brew install coreutils) for the standard implementation.\n' "$_CODEX_TIMEOUT" >&2
    node "$COMPANION" "$@" &
    local _node_pid=$!
    local _fired_file
    _fired_file="$(mktemp)"
    (
      sleep "$_CODEX_TIMEOUT"
      if kill -0 "$_node_pid" 2>/dev/null; then
        : > "$_fired_file"
        kill -TERM "$_node_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$_node_pid" 2>/dev/null || true
      fi
    ) &
    local _watcher_pid=$!
    wait "$_node_pid" 2>/dev/null
    _exit_code=$?
    kill "$_watcher_pid" 2>/dev/null || true
    wait "$_watcher_pid" 2>/dev/null || true
    if [[ -s "$_fired_file" ]]; then
      _exit_code=124
    fi
    rm -f "$_fired_file"
  fi
  if [[ "$_exit_code" -eq 124 ]]; then
    printf 'CODEX TIMED OUT after %ss -- proceeding without Codex\n' "$_CODEX_TIMEOUT" >&2
    # Machine-readable event (D-g) so a pulse loop can surface it without
    # parsing prose -- tier defaults to "default" when --tier was not passed.
    printf 'CODEX_TIMEOUT_EVENT tier=%s limit=%s\n' "${_TIER:-default}" "$_CODEX_TIMEOUT" >&2
    exit 124
  fi
  return "$_exit_code"
}

# C1 -- 5.6 -> 5.5 fallback. A gpt-5.6-family dispatch can fail with a hard 400
# if the local Codex CLI is a stable release that predates 5.6 support (message
# observed: "requires a newer version of Codex") or if the resolved slug isn't
# recognized by the account tier (message observed: "is not supported when
# using Codex with a ChatGPT account", status 400). Either way this is a CLI/
# entitlement problem, not a prompt problem -- retry once on gpt-5.5/high so a
# stale CLI degrades gracefully instead of hard-failing every Codex call.
# lean: buffers full output before replaying instead of streaming live -- loses
# incremental [codex] progress lines during the (rare) fallback path. Upgrade
# to a tee-based streaming retry if interactive live-progress becomes a
# complaint.
_FALLBACK_MODEL="gpt-5.5"
_FALLBACK_EFFORT="high"

_extract_model_arg() {
  local _prev=""
  for _a in "$@"; do
    if [[ "$_prev" == "--model" || "$_prev" == "-m" ]]; then
      printf '%s' "$_a"
      return 0
    fi
    _prev="$_a"
  done
}
DISPATCH_MODEL="$(_extract_model_arg "$@")"

# Codex#4 (SUPERVISE-V2-01 fix-1): tier one-level-lower retry on a real
# timeout (exit 124). Before this fix a timeout left `_run_with_fallback`
# retrying only 5.6 HTTP-400 failures -- a genuine timeout was simply
# abandoned, the tier-aware CODEX_TIMEOUT default existed but nothing acted
# on the exit-124 event. Single retry only: top->standard, standard->volume;
# volume (already the cheapest/fastest tier) has nowhere lower to go.
_tier_down() {
  case "$1" in
    top)      echo "standard" ;;
    standard) echo "volume" ;;
    *)        echo "" ;;
  esac
}

_tier_timeout_for() {
  case "$1" in
    top)      echo 1800 ;;
    standard) echo 900 ;;
    *)        echo 600 ;;
  esac
}

# Sets TIER_MODEL_OUT / WIRE_EFFORT_OUT for the given tier name. Same
# resolution table as the --tier extraction block above.
_tier_model_effort() {
  local _t="$1" _mc _eff
  _mc="${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}"
  case "$_t" in
    top)
      if command -v jq >/dev/null 2>&1 && [[ -f "$_mc" ]] \
         && jq -e '.models[]? | select(.slug=="gpt-5.6-sol")' "$_mc" >/dev/null 2>&1; then
        TIER_MODEL_OUT="gpt-5.6-sol"; _eff="high"
      else
        TIER_MODEL_OUT="gpt-5.6-terra"; _eff="ultra"
      fi
      ;;
    standard) TIER_MODEL_OUT="gpt-5.6-terra"; _eff="medium" ;;
    volume)   TIER_MODEL_OUT="gpt-5.6-luna";  _eff="low" ;;
    *)        TIER_MODEL_OUT="gpt-5.6-terra"; _eff="medium" ;;
  esac
  WIRE_EFFORT_OUT="$_eff"
  [[ "$WIRE_EFFORT_OUT" == "ultra" ]] && WIRE_EFFORT_OUT="xhigh"
}

_run_with_fallback() {
  local rc=0 out
  out="$(_run_node "$@" 2>&1)" && rc=0 || rc=$?

  if [[ $rc -eq 124 && -n "$_TIER" ]]; then
    local _next_tier
    _next_tier="$(_tier_down "$_TIER")"
    if [[ -n "$_next_tier" ]]; then
      echo "[codex-task] CODEX_RETRY_EVENT from_tier=$_TIER to_tier=$_next_tier reason=timeout" >&2
      _tier_model_effort "$_next_tier"
      local retry_args=() _prev=""
      for _a in "$@"; do
        if [[ "$_prev" == "--model" || "$_prev" == "-m" ]]; then
          retry_args+=("$TIER_MODEL_OUT")
        elif [[ "$_prev" == "--effort" ]]; then
          retry_args+=("$WIRE_EFFORT_OUT")
        else
          retry_args+=("$_a")
        fi
        _prev="$_a"
      done
      _TIER="$_next_tier"
      _CODEX_TIMEOUT="$(_tier_timeout_for "$_next_tier")"
      DISPATCH_MODEL="$TIER_MODEL_OUT"
      out="$(_run_node "${retry_args[@]}" 2>&1)" && rc=0 || rc=$?
      echo "[codex-task] CODEX_RETRY_EVENT tier=$_next_tier result=$([[ $rc -eq 0 ]] && echo ok || echo rc=$rc)" >&2
    fi
  fi

  if [[ $rc -ne 0 && "$DISPATCH_MODEL" == gpt-5.6* ]] \
     && printf '%s' "$out" | grep -qE '"status":[[:space:]]*400|is not supported when using Codex|requires a newer version of Codex'; then
    echo "[codex-task] FALLBACK: model '$DISPATCH_MODEL' rejected by Codex CLI -- retrying once with ${_FALLBACK_MODEL} (effort ${_FALLBACK_EFFORT})" >&2
    local fb_args=() prev=""
    for _a in "$@"; do
      if [[ "$prev" == "--model" || "$prev" == "-m" ]]; then
        fb_args+=("$_FALLBACK_MODEL")
      elif [[ "$prev" == "--effort" ]]; then
        fb_args+=("$_FALLBACK_EFFORT")
      else
        fb_args+=("$_a")
      fi
      prev="$_a"
    done
    out="$(_run_node "${fb_args[@]}" 2>&1)" && rc=0 || rc=$?
  fi
  printf '%s\n' "$out"
  return "$rc"
}

# CODEX-NEVER-LOSE-01 -- auto-guard background dispatches. `task`/`review` with
# --background detach into a Codex job with nothing to notify this session on
# completion; if the session dies first, the result is lost. Arm codex-guard.sh
# (detached, non-blocking) so every background dispatch is watched to a
# terminal state and any uncommitted result gets rescued. --wait/foreground
# runs already return the full result inline and don't need this.
_has_background=0
for _a in "$@"; do [[ "$_a" == "--background" ]] && _has_background=1; done

if [[ ( "$SUB" == "task" || "$SUB" == "review" ) && "$_has_background" -eq 1 ]]; then
  # cwd: whatever was forwarded via --cwd/-C, else $PWD -- matches
  # codex-companion's own resolveCommandCwd() default (process.cwd()).
  _GUARD_CWD="$PWD"
  _prev=""
  for _a in "$@"; do
    if [[ "$_prev" == "--cwd" || "$_prev" == "-C" ]]; then
      _GUARD_CWD="$_a"
    fi
    _prev="$_a"
  done

  # wave2 round3 finding 5: this script runs under `set -e`, and a bare
  # `_BG_OUT="$(_run_with_fallback "$@")"` is a plain simple-command assignment --
  # NOT exempt from errexit -- so a genuine nonzero launcher failure aborted the whole
  # script AT this line, before `_BG_RC` was ever captured and before the no-jobId
  # branch below could ever call `_record_spawn_failure`. Folding the assignment into
  # an explicit `&&`/`||` list (the SAME idiom `_run_with_fallback` uses internally for
  # its own inner command substitution) makes the compound command exempt from -e,
  # since only the LAST command of an and-or list can trigger it and that is always
  # one of the two `_BG_RC=` assignments below, which always succeeds.
  _BG_OUT="$(_run_with_fallback "$@")" && _BG_RC=0 || _BG_RC=$?
  printf '%s\n' "$_BG_OUT"

  # jobId format: <task|review>-<base36-timestamp>-<random6> (lib/state.mjs
  # generateJobId) -- appears verbatim in both the rendered launch line and
  # --json payload, so one regex covers both output modes.
  _JOB_ID="$(printf '%s\n' "$_BG_OUT" | grep -oE '(task|review)-[a-z0-9]+-[a-z0-9]+' | head -1 || true)"
  if [[ -n "$_JOB_ID" ]]; then
    _GUARD_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-guard.sh"
    if [[ -x "$_GUARD_SCRIPT" ]]; then
      nohup "$_GUARD_SCRIPT" "$_JOB_ID" "$_GUARD_CWD" >/dev/null 2>&1 < /dev/null &
      disown 2>/dev/null || true
      echo "[codex-task] armed codex-guard.sh for $_JOB_ID (cwd=$_GUARD_CWD)" >&2
    else
      echo "[codex-task] WARN: codex-guard.sh not found next to codex-task.sh -- background job $_JOB_ID is unguarded" >&2
    fi
  else
    # T-f item 3 (spawn failure visibility): no jobId means codex-companion
    # never wrote a job record at all -- today this WARNs and the failure
    # vanishes. Synthesize a terminal job record so it's visible in
    # `codex-task.sh status --all` instead.
    echo "[codex-task] WARN: could not parse jobId from background dispatch output -- guard not armed" >&2
    _record_spawn_failure "$_GUARD_CWD" "$_BG_OUT"
  fi
  exit "$_BG_RC"
fi

if [[ "${CODEX_VERBOSE:-0}" == "1" ]]; then
  _run_with_fallback "$@"
  exit $?
fi

# Strip noisy [codex] meta lines, keep the findings body / errors / un-prefixed content.
_strip_meta() {
  grep --line-buffered -vE '^\[codex\] (Running command|Command completed|Calling |Tool .* (completed|failed)|Assistant message captured)'
}

# For adversarial-review, also drop everything before the last findings marker so the
# caller sees only the actionable tail (set CODEX_FULL=1 to keep the whole log).
set -o pipefail
if [[ "$SUB" == "adversarial-review" && "${CODEX_FULL:-0}" != "1" ]]; then
  _run_with_fallback "$@" | _strip_meta | awk '
    BEGIN { buf=""; all=""; found=0 }
    /^# Codex|^\*\*Findings\*\*|^## Findings/ { buf=""; found=1 }
    { buf = buf $0 "\n"; all = all $0 "\n" }
    END { printf "%s", (found ? buf : all) }
  '
else
  _run_with_fallback "$@" | _strip_meta
fi
exit "${PIPESTATUS[0]}"
