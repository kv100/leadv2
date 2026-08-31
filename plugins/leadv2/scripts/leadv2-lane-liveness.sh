#!/usr/bin/env bash
# One authoritative lane verdict.  The lane's output log is the primary
# signal; active.yaml supplies only the optional process identity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$PWD}"
LANE_ID=""
JOB_ID=""
ALL=0
JSON=0
NO_CODEX=0

# Single source of truth for lane sub-agent role suffixes (STATUSLINE-COUNT-TRUTH-02
# §1a) -- never a second hardcoded suffix list here.
if [[ -f "$SCRIPT_DIR/leadv2-lane-child-suffixes.sh" ]]; then
  # shellcheck source=leadv2-lane-child-suffixes.sh
  source "$SCRIPT_DIR/leadv2-lane-child-suffixes.sh"
fi
LEADV2_LANE_CHILD_SUFFIXES="${LEADV2_LANE_CHILD_SUFFIXES:-architect}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --lane) LANE_ID="${2:-}"; shift 2 ;;
    --job) JOB_ID="${2:-}"; shift 2 ;;
    --all) ALL=1; shift ;;
    --json) JSON=1; shift ;;
    --no-codex) NO_CODEX=1; shift ;;
    *) printf '[lane-liveness] unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -n "$LANE_ID" && ( -n "$JOB_ID" || "$ALL" -eq 1 ) ]] || [[ -n "$JOB_ID" && "$ALL" -eq 1 ]]; then
  printf '[lane-liveness] choose exactly one of --lane, --job, or --all\n' >&2
  exit 2
fi

# State paths may be outside a worktree.  Keep the local path as a fallback
# for standalone fixtures and old plugin installs.
ACTIVE_YAML="$PROJECT_ROOT/docs/leadv2/active.yaml"
TOMBSTONES="$PROJECT_ROOT/docs/leadv2/tombstones.yaml"
if [[ -f "$SCRIPT_DIR/leadv2-state-path.sh" ]]; then
  ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT_DIR/leadv2-state-path.sh" active.yaml 2>/dev/null || printf '%s' "$ACTIVE_YAML")"
  TOMBSTONES="$(PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT_DIR/leadv2-state-path.sh" tombstones.yaml 2>/dev/null || printf '%s' "$TOMBSTONES")"
fi

CODEX_TASK="${CODEX_TASK_SH:-${SCRIPT_DIR}/codex-task.sh}"
CODEX_RAW=''
if [[ "$NO_CODEX" -ne 1 && -f "$CODEX_TASK" ]]; then
  # --no-codex skips both `codex-task.sh status` shell-outs -- the statusline
  # hot path (leadv2-lane-status-line-tail.sh) never needs the provider
  # mapping, only log-based liveness (STATUSLINE-COUNT-TRUTH-02 R1).
  if [[ -n "$JOB_ID" ]]; then
    CODEX_RAW="$(bash "$CODEX_TASK" status "$JOB_ID" --json --cwd "$PROJECT_ROOT" 2>/dev/null || true)"
  else
    CODEX_RAW="$(bash "$CODEX_TASK" status --all --json --cwd "$PROJECT_ROOT" 2>/dev/null || true)"
  fi
fi

# --all resolves every lane in one Python pass.
python3 - "$PROJECT_ROOT" "$ACTIVE_YAML" "$TOMBSTONES" "$LANE_ID" "$JOB_ID" "$ALL" "$JSON" "$CODEX_RAW" "${LEADV2_LANE_SILENT_MAX_S:-900}" "${LEADV2_LANE_LIVENESS_V2:-1}" "${LEADV2_LANE_STARTING_MAX_S:-300}" "${LEADV2_LANE_ABANDON_MAX_S:-3600}" "$LEADV2_LANE_CHILD_SUFFIXES" "${LEADV2_LANE_SENTINEL_DEAD:-1}" "${LEADV2_LANE_SENTINEL_SETTLE_S:-60}" "${LEADV2_LANE_RUNS_ROOT:-}" "${LEADV2_LANE_SENTINEL_CLAUDE:-1}" "${LEADV2_LANE_PID_IDENTITY:-1}" "${LEADV2_LANE_PREPASS_LIVE:-0}" "${LEADV2_LANE_FINISHED_WINDOW_S:-1800}" <<'PY'
import glob, json, os, re, subprocess, sys, time

(root, active_path, tombstones_path, wanted_lane, wanted_job, all_mode, json_mode,
 codex_raw, silent_max_raw, v2_raw, starting_max_raw, abandon_max_raw,
 child_suffixes_raw, sentinel_dead_raw, sentinel_settle_raw, runs_root_raw,
 sentinel_claude_raw, pid_identity_raw, prepass_live_raw, finished_window_raw) = sys.argv[1:]
all_mode = all_mode == "1"
json_mode = json_mode == "1"
# LEADV2_LANE_LIVENESS_V2=0 is the one-flag rollback to the exact prior
# implementation (self-reported provider queued/running trusted as alive
# with no log-age check). Default-on: =1 or unset runs the corrected logic.
v2_mode = v2_raw != "0"

def _int_env(raw, default):
    try:
        return max(0, int(raw))
    except ValueError:
        return default

silent_max = _int_env(silent_max_raw, 900)
starting_max = _int_env(starting_max_raw, 300)
abandon_max = _int_env(abandon_max_raw, 3600)

# LANE-LIVENESS-THREE-STATES-02: no live pid + a commit in the lane's OWN
# worktree within this window is a completed round, not a death -- both
# facts are externally checkable, independent of the worker's own claims.
# 1800s (30min) sits between SILENT_MAX (900s) and ABANDON_MAX (3600s): long
# enough to absorb the gap between a worker's last commit and the next probe
# (live incident V5-M0-SKELETON-01: three founder escalations spanned
# ~40min after the worker had already committed and exited), short enough
# that a lane whose only commit is from a much earlier, unrelated round is
# not misread as freshly finished.
finished_window = _int_env(finished_window_raw, 1800)

# SENTINEL-COMPLETION-01 (LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01):
# a runner-written .finalized sentinel + dead process group is proof, not a
# report — it outranks log freshness because the fresh mtime IS the completion
# flush.  These tunables are threaded via argv (like every other tunable here),
# not read from os.environ.  GLM_RUNS_DIR / KIMI_RUNS_DIR are consumed, not
# defined, by this script — they belong to the runners and are read via
# os.environ.get in resolve_run_dir().
sentinel_dead = sentinel_dead_raw != "0"
sentinel_settle_s = _int_env(sentinel_settle_raw, 60)
# CLAUDE-SUBSESSION-HAS-NO-COMPLETION-SENTINEL-01: independent kill switch for
# the claude arm only — strictly subordinate to the sentinel_dead master (AND).
sentinel_claude = sentinel_claude_raw != "0"
# LANE-REGISTRY-SELF-DEADLOCK-01: two new tunables, same argv-threaded shape
# as every other one above (never os.environ inside the heredoc).
#   LEADV2_LANE_PID_IDENTITY=0 — one-flag rollback to bare kill -0 (no
#     lstart birth corroboration).
#   LEADV2_LANE_PREPASS_LIVE=1 — restore the pre-R-6 behaviour where a fresh
#     architect-prepass child stream counts as a live signal. Default OFF:
#     the prepass runs SYNCHRONOUSLY inside the dispatcher itself (before any
#     spawn), so by the time any other process probes that stream, a fresh
#     mtime there is residue of a dispatch attempt, never proof of a running
#     worker — the exact self-refreshing-probe deadlock of EGRESS-STATUS-
#     COLLECTOR-01 (task e5be9e72).
pid_identity_on = pid_identity_raw != "0"
prepass_live = prepass_live_raw == "1"

CHILD_SUFFIXES = [s.strip() for s in child_suffixes_raw.split(",") if s.strip()]
_FOLD_RE = re.compile(r'^(dispatch-[0-9a-f]{8})-(.+)$')

def fold_match(tid):
    # S0 (STATUSLINE-COUNT-TRUTH-02): a lane id shaped dispatch-<sig8>-<suffix>
    # where <suffix> is a registered child role (leadv2-lane-child-suffixes.sh)
    # is a sub-agent prepass running INSIDE its parent lane -- never its own
    # lane, never its own cap slot. Returns the parent tid, or None.
    m = _FOLD_RE.match(tid)
    if not m:
        return None
    parent, suffix = m.group(1), m.group(2)
    return parent if suffix in CHILD_SUFFIXES else None

def file_mtime(path):
    # D3/R-1 fix: pure os.stat, no subprocess. The prior `stat -f %m` shell-out
    # existed only to dodge GNU stat/date syntax -- os.stat() sidesteps that
    # entirely and removes one subprocess PER LANE, which matters once --all
    # discovery stops undercounting (R0) and resolves every lane on every repaint.
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return None

def pid_alive(value):
    try:
        os.kill(int(value), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

# --- LANE-REGISTRY-SELF-DEADLOCK-01 pid identity -------------------------------
_LSTART_RE = re.compile(
    r"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+"
    r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+"
    r"\d{1,2}\s+\d{1,2}:\d{2}:\d{2}\s+\d{4}$"
)

def _norm_birth(s):
    # Same whitespace contract as the registry writer's `tr -s ' '` + trim
    # (_lv2_pid_birth): collapse interior runs and strip both ends.
    return " ".join(str(s or "").split())

def ps_lstart(value):
    # Same shape/timeout as ps_stat() — a missing or wedged `ps` degrades to
    # "", never to a fabricated birth string.
    try:
        return subprocess.run(["ps", "-o", "lstart=", "-p", str(value)],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""

def pid_state(value, birth, identity_on, lane_dead_at=None):
    """(state, identity) — state in ("dead", "alive_verified", "alive_unverified"),
    identity in ("verified", "unverified", "mismatch").

    Degrade-to-unverified rules (design §3.1/§3.3): an absent, malformed, or
    unobservable birth string NEVER kills a lane — only a well-formed recorded
    birth that a live `ps` observation contradicts is a mismatch (recycled pid,
    failure direction false-alive-safe everywhere else).

    T8b: lane_dead_at is the SAME row's active.yaml `dead_at` field, stamped
    only by lib/leadv2-lane-state.sh's lane_reconcile/lane_deregister (the
    authoritative lane-state module, run from the dispatcher's hot loop and
    the sweeper) -- never derived here. When set it is a definitive, already-
    corroborated dead verdict, so it short-circuits the bare os.kill probe
    below rather than duplicating the module's own birth-time check."""
    if lane_dead_at:
        return ("dead", "verified")
    try:
        pid = int(value)
    except (TypeError, ValueError):
        return ("dead", "unverified")
    if pid <= 0:
        # never os.kill(0, 0) — that signals the whole process group
        return ("dead", "unverified")
    try:
        os.kill(pid, 0)
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        # PermissionError stays "dead" to match pid_alive()'s exact prior
        # semantics (a pid we cannot signal is not OUR worker).
        return ("dead", "unverified")
    if not identity_on:
        return ("alive_unverified", "unverified")
    recorded = _norm_birth(birth)
    if not recorded or not _LSTART_RE.match(recorded):
        return ("alive_unverified", "unverified")
    observed = _norm_birth(ps_lstart(pid))
    if not observed:
        # pid gone is already caught by kill(0); an empty `ps` here means
        # unobservable — unverified, never mismatch (no double-count).
        return ("alive_unverified", "unverified")
    if observed == recorded:
        return ("alive_verified", "verified")
    return ("dead", "mismatch")
# --- end LANE-REGISTRY-SELF-DEADLOCK-01 pid identity ---------------------------

def ps_stat(value):
    try:
        return subprocess.run(["ps", "-o", "stat=", "-p", str(value)], capture_output=True,
                              text=True, timeout=2).stdout.strip()
    except Exception:
        return ""

def parse_iso(ts):
    # Accepts the "...Z" UTC suffix leadv2-active-registry.sh/leadv2-fanout.sh both write
    # (_now_iso() / date -u +%Y-%m-%dT%H:%M:%SZ). Any other/malformed shape -> None, never
    # a fabricated epoch (a bad parse must never MASQUERADE as a real age).
    if not ts:
        return None
    try:
        import datetime
        s = ts[:-1] + "+00:00" if ts.endswith("Z") else ts
        return int(datetime.datetime.fromisoformat(s).timestamp())
    except Exception:
        return None

def age_from_started_at(session):
    # SD-LEDGER-SWEEP-HARDEN-01: an artifactless lane (no log file ever written, or the
    # file it pointed at vanished) used to leave row["age_s"] as None forever, which the
    # dispatch-ledger sweep's own emitter then null-coerced to 0 -- an artifactless lane
    # was therefore ALWAYS "younger" than any grace period, permanently blocking its own
    # sweep no matter how long it had actually been dead. Derive age from the active.yaml
    # row's own started_at instead, so an artifactless lane still ages out normally.
    if not session:
        return None
    epoch = parse_iso(session.get("started_at"))
    if epoch is None:
        # LOW-1 (fixround-tails): missing/unparseable started_at is INDETERMINATE, not a
        # real age of 0 -- warn so the degradation is visible instead of silently masquerading
        # as "just spawned" to every downstream age check.
        print(
            f"[lane-liveness] WARN: task_id={session.get('task_id')} has no parseable "
            f"started_at ({session.get('started_at')!r}) -- age_s is indeterminate, not 0",
            file=sys.stderr,
        )
        return None
    return max(0, int(time.time()) - epoch)

def load_yaml(path, default):
    try:
        import yaml
        with open(path, encoding="utf-8") as fh:
            value = yaml.safe_load(fh)
        return default if value is None else value
    except Exception:
        return default

active = load_yaml(active_path, {})
sessions = {str(s.get("task_id")): s for s in (active.get("sessions") or [])
            if isinstance(s, dict) and s.get("task_id")}
tombstones = load_yaml(tombstones_path, [])
tombstoned = {str(item.get("task_id")) for item in tombstones if isinstance(item, dict) and item.get("task_id")}

def provider_jobs(raw):
    # STATUSLINE-COUNT-TRUTH-02 fix: this must always return a dict (callers
    # do `jobs.get(...)`/`jobs.values()`) -- the two early-return paths used
    # to hand back the `[]` list accumulator instead, which was latent while
    # --no-codex always supplied a valid CODEX_RAW payload but crashes
    # AttributeError the moment raw is empty/invalid, which --no-codex (R1)
    # now makes the statusline's OWN hot-path call shape every single repaint.
    found = []
    try:
        payload = json.loads(raw)
    except Exception:
        return {}
    if not isinstance(payload, dict):
        return {}
    if isinstance(payload.get("job"), dict):
        found.append(payload["job"])
    found.extend(j for j in (payload.get("running") or []) if isinstance(j, dict))
    found.extend(j for j in (payload.get("recent") or []) if isinstance(j, dict))
    if isinstance(payload.get("latestFinished"), dict):
        found.append(payload["latestFinished"])
    out = {}
    for job in found:
        if job.get("id"):
            out[str(job["id"])] = job
    return out

jobs = provider_jobs(codex_raw)

def lane_job_id(tid):
    path = os.path.join(root, "docs", "handoff", tid, "codex-plan.json")
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
        return str(value.get("job_id") or "")
    except Exception:
        return ""

WORKER_STREAM_NAMES = ("developer.stream.jsonl", "architect.stream.jsonl", "session.log", "fanout.log")

# --- SENTINEL-COMPLETION-01 helpers -------------------------------------------
# Run-dir resolution contract (design §3.6):
#   resolve_run_dir(tid) -> (arm, run_dir) | (None, None)
#     for arm in ("glm", "kimi", "claude"):        # newest pointer mtime wins
#         idfile = <root>/docs/handoff/<tid>/.<arm>-session-runner.run-id
#         run_id = first non-empty stripped line of idfile        # else continue
#         reject run_id containing "/" or ".." or empty           # path-traversal guard
#         base = ${GLM_RUNS_DIR|KIMI_RUNS_DIR|LEADV2_CLAUDE_RUNS_DIR} if set
#                else ${LEADV2_LANE_RUNS_ROOT:-$HOME/.claude/cache}/<arm>-runs
#         if isdir(base/run_id): collect (pointer_mtime, finalized, arm, dir)
#     return newest-mtime candidate (exact ties prefer non-finalized),
#     else (None, None)
def resolve_run_dir(tid):
    # H3 (CLAUDE-SUBSESSION-HAS-NO-COMPLETION-SENTINEL-01): resolve across ALL
    # arms and return the pointer with the NEWEST mtime, not the first match.
    # A task that ran glm earlier and claude now would otherwise resolve the
    # stale glm run dir and its old .finalized -> false dead.
    candidates = []
    for arm in ("glm", "kimi", "claude"):
        idfile = os.path.join(root, "docs", "handoff", tid, f".{arm}-session-runner.run-id")
        run_id = ""
        try:
            with open(idfile, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        run_id = line
                        break
        except OSError:
            continue
        # Path-traversal guard (design R9): a crafted run-id must never escape base.
        if not run_id or "/" in run_id or ".." in run_id:
            continue
        if arm == "claude":
            base = os.environ.get("LEADV2_CLAUDE_RUNS_DIR")
        else:
            base = os.environ.get("GLM_RUNS_DIR" if arm == "glm" else "KIMI_RUNS_DIR")
        if not base:
            base = os.path.join(
                runs_root_raw if runs_root_raw else os.path.expanduser("~/.claude/cache"),
                f"{arm}-runs",
            )
        run_dir = os.path.join(base, run_id)
        if not os.path.isdir(run_dir):
            continue
        # Sub-second mtime (file_mtime truncates to int seconds): a claude
        # attempt that dies instantly and a glm spawn in the SAME second would
        # otherwise tie, and a tie resolved toward the finalized arm is a
        # false-dead window (codex review 2026-08-17, claim 2).
        try:
            pointer_mtime = os.stat(idfile).st_mtime
        except OSError:
            pointer_mtime = 0
        finalized = os.path.isfile(os.path.join(run_dir, ".finalized"))
        candidates.append((pointer_mtime, finalized, arm, run_dir))
    if not candidates:
        return (None, None)
    # Newest pointer wins. Exact-tie break is SAFETY-BIASED: prefer the
    # non-finalized candidate (sort key 0 < 1, ascending, last wins) so a tie
    # can never resolve toward an already-finalized arm while its sibling arm
    # may still be running.
    candidates.sort(key=lambda c: (c[0], 0 if c[1] else 1))
    return (candidates[-1][2], candidates[-1][3])

def pgid_group_alive(pgid):
    # Establish process-group death the same way glm-coder.sh does: kill(-pgid, 0).
    #   ProcessLookupError → group gone (dead).
    #   PermissionError     → group exists but is not ours → treat as ALIVE (never fire).
    #   Any other exception → cannot determine → treat as ALIVE (fail-safe).
    try:
        os.kill(-pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return True

def sentinel_check(tid, row):
    """Return True if the sentinel-completion dead verdict was set on row.

    Conditions (design §3.2, all must hold):
      1. Kill switch on, run dir exists and contains .finalized.
      2. glm/kimi: pgid file parses as positive int AND os.kill(-pgid, 0)
         raises ProcessLookupError. claude (CLAUDE-SUBSESSION-HAS-NO-COMPLETION-
         SENTINEL-01): pid file parses AND os.kill(pid, 0) raises
         ProcessLookupError; every other errno or a missing file → alive.
      3. active.yaml pid, IF explicitly recorded, must be dead.
      4. .finalized mtime must be at least sentinel_settle_s old.
    """
    if not sentinel_dead:
        return False
    arm, run_dir = resolve_run_dir(tid)
    if arm is None:
        return False
    sentinel_path = os.path.join(run_dir, ".finalized")
    if not os.path.isfile(sentinel_path):
        return False
    # Settle window (design R1): closes the runner-retry race.
    sentinel_mtime = file_mtime(sentinel_path)
    if sentinel_mtime is None:
        return False
    sentinel_age = max(0, int(time.time()) - sentinel_mtime)
    if sentinel_age < sentinel_settle_s:
        return False
    # Process-identity check — positive proof the worker is gone. Branch on arm
    # (H1, CLAUDE-SUBSESSION-HAS-NO-COMPLETION-SENTINEL-01): glm/kimi launch
    # through setsid_wrapper (pid == pgid), so kill(-pgid, 0) is meaningful.
    # The claude arm's worker runs in the CALLER'S process group — kill(-pid, 0)
    # would raise ProcessLookupError on a LIVE worker — so claude uses a plain
    # pid file with os.kill(pid, 0), and every ambiguous errno resolves to
    # alive (never fire). Pid reuse can only produce a false ALIVE: safe.
    if arm == "claude":
        if not sentinel_claude:
            return False  # independent claude kill switch (subordinate to master)
        cpid = None
        try:
            with open(os.path.join(run_dir, "pid"), encoding="utf-8") as fh:
                cpid = int(fh.read().strip())
        except (OSError, ValueError):
            cpid = None
        if cpid is None or cpid <= 0:
            return False  # missing/unparsable pid file — cannot establish death
        try:
            os.kill(cpid, 0)
            worker_gone = False
        except ProcessLookupError:
            worker_gone = True
        except OSError:
            worker_gone = False  # EPERM or any other errno → alive, do not fire
        if not worker_gone:
            return False  # worker still alive — do not fire
    else:
        pgid = None
        try:
            with open(os.path.join(run_dir, "pgid"), encoding="utf-8") as fh:
                pgid = int(fh.read().strip())
        except (OSError, ValueError):
            pgid = None
        if pgid is None or pgid <= 0:
            return False  # cannot positively establish death — fall through
        alive = pgid_group_alive(pgid)
        if alive:
            row["pgid"] = pgid
            row["pgid_alive"] = True
            return False  # group still alive — do not fire
        row["pgid"] = pgid
        row["pgid_alive"] = False
    # active.yaml pid (condition 3): only blocks if it was explicitly recorded.
    # LANE-REGISTRY-SELF-DEADLOCK-01: a lead_durable pid is the dispatching
    # session's OWN pid — alive by definition, never worker evidence — so it
    # must not block the sentinel from firing on a lead-registered row.
    pid_recorded = row.get("pid") is not None and str(row.get("pid")).strip() != ""
    if pid_recorded and row.get("pid_alive") and row.get("pid_source") != "lead_durable":
        return False  # recorded-and-alive pid → do not fire
    # Verdict
    row["pid_recorded"] = pid_recorded
    row["arm"] = arm
    row["sentinel_arm"] = arm
    row["run_dir"] = run_dir
    row["sentinel_path"] = sentinel_path
    row["sentinel_age_s"] = sentinel_age
    # Corroborating .outcome (display-only, never gates the verdict)
    try:
        with open(os.path.join(run_dir, ".outcome"), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("outcome="):
                    row["lane_outcome"] = line.split("=", 1)[1]
                    break
    except OSError:
        pass
    row.update(verdict="dead:sentinel_finalized", reason="sentinel_finalized")
    return True
# --- end SENTINEL-COMPLETION-01 helpers ---------------------------------------

def commit_age_s(worktree):
    # LANE-LIVENESS-THREE-STATES-02: externally checkable fact #2 -- the
    # lane's OWN worktree HEAD commit time, never the worker's self-reported
    # success. Missing/foreign/non-git/unborn-HEAD worktree -> None (cannot
    # establish finished), never a fabricated age.
    if not worktree or not os.path.isdir(worktree):
        return None
    try:
        r = subprocess.run(["git", "-C", worktree, "log", "-1", "--format=%ct"],
                           capture_output=True, text=True, timeout=3)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    try:
        ctime = int(r.stdout.strip())
    except ValueError:
        return None
    return max(0, int(time.time()) - ctime)

def resolve(tid):
    lane_dir = os.path.join(root, "docs", "handoff", tid)
    row = {"lane": tid, "verdict": None, "age_s": None, "source": None,
           "log_path": None, "raw_log_path": None, "pid": None, "pid_alive": None, "reason": None,
           "attempt": None, "child_of": None,
           "pid_source": None, "pid_identity": None}

    # S0 (STATUSLINE-COUNT-TRUTH-02): a dispatch-<sig8>-<suffix> id, where
    # <suffix> is a registered child role, is a sub-agent prepass running
    # INSIDE its parent lane -- no worktree, no task lock, no cap slot of its
    # own. It is never its own lane and never counted; see
    # leadv2-lane-child-suffixes.sh for the single source of truth on <suffix>.
    fold_parent = fold_match(tid)
    if fold_parent is not None:
        row.update(verdict="child", child_of=fold_parent, source="child_suffix_fold", reason="child_suffix_fold")
        return row

    session = sessions.get(tid)
    if session is not None:
        # LANE-REGISTRY-SELF-DEADLOCK-01: choose the pid the liveness ladder
        # trusts. worker_pid (stamped post-spawn by set_worker_pid, with its
        # own birth) wins; otherwise the row's `pid`, labelled by pid_role —
        # "lead_durable" rows carry the DISPATCHING session's own pid, which
        # is alive by definition while the lead lives and must never be read
        # as worker-liveness evidence. A row with no pid_role at all (legacy
        # / fanout-written) keeps today's exact bare kill -0 behaviour.
        # All reads are .get() with try/int guards — one malformed field must
        # never abort the --all pass for every other lane (design §3.1).
        _role = session.get("pid_role")
        if _role not in ("lead_durable", "worker"):
            _role = None
        _wpid = None
        try:
            _w = int(session.get("worker_pid"))
            if _w > 0:
                _wpid = _w
        except (TypeError, ValueError):
            _wpid = None
        if _wpid is not None:
            row["pid"] = _wpid
            row["pid_source"] = "worker"
            _state, _identity = pid_state(_wpid, session.get("worker_pid_birth"), pid_identity_on, session.get("dead_at"))
        else:
            row["pid"] = session.get("pid")
            row["pid_source"] = "lead_durable" if _role == "lead_durable" else "legacy"
            _state, _identity = pid_state(row["pid"], session.get("pid_birth"), pid_identity_on, session.get("dead_at"))
        row["pid_alive"] = _state != "dead"
        row["pid_identity"] = _identity
        # SD-LEDGER-SWEEP-HARDEN-01: leadv2_active_set_attempt() stamps this once
        # dispatch-code.sh's own $$ (the ledger's own attempt token) is known -- see
        # leadv2-fanout.sh's single-worker funnel finalization call site. Absent on
        # rows written before this hardening, or by any caller that never spawned
        # through that path; the dispatch-ledger sweep treats an absent attempt as
        # "cannot safely attribute a dead terminal" and skips rather than sweeps.
        row["attempt"] = session.get("attempt")

    # LANE-LIVENESS-THREE-STATES-02: finished is a third state, decided BEFORE
    # any log/stream freshness check below -- a fresh stream mtime after the
    # worker exited is the completion flush, not proof of continued work
    # (same precedence rule as SENTINEL-COMPLETION-01 further down, for lanes
    # with no runner-written sentinel at all). Excludes lead_durable rows:
    # that pid is the LEAD's own, never worker evidence, so "gone" there is
    # meaningless.
    if session is not None and row.get("pid_source") != "lead_durable":
        pid_gone = row["pid"] is None or row["pid_alive"] is False
        if pid_gone:
            _commit_age = commit_age_s(session.get("worktree"))
            if _commit_age is not None and _commit_age <= finished_window:
                row["age_s"] = _commit_age
                row.update(verdict=f"finished:{_commit_age}s", source="git_commit",
                           reason="no_pid_recent_commit")
                return row

    # B9/B14 fix (SUPERVISOR-AUDIT-01 fix-round-2): consult the active row's
    # OWN recorded log_path first. leadv2-fanout.sh's single-worker funnel
    # (launch_via_dispatch_code) writes to docs/handoff/dispatch-<sig8>/
    # developer.stream.jsonl, never to docs/handoff/<task_id>/ — the funnel's
    # active.yaml row carries that path in its log_path field precisely so
    # liveness can find it. Ignoring it made every fresh funnel dispatch
    # resolve dead:no_handoff_dir, and the two-poll prune path in
    # leadv2-supervise.sh could then delete a live worker. Only a
    # session-recorded log_path that resolves to a REAL, EXISTING file is
    # treated as authoritative here — a session with no log_path, or one
    # pointing at a file that does not (yet) exist, falls through to the
    # unchanged directory scan below, so pre-funnel lanes (whose log_path is
    # the phase-cycle pulse.md default) keep their exact prior resolution.
    # wave2 round4 finding 3: `row["log_path"]` below is only ever set once an artifact is
    # PROVEN to exist -- a crashed funnel dispatch whose stream file vanished (or never got
    # written before the crash) leaves it null on every return path, and the dispatch-
    # ledger sweep's sig8 extraction (which greps the `dispatch-<sig8>` segment out of this
    # path) had nothing to grep, so exactly the crash lanes that most need sweeping were
    # silently skipped forever. `raw_log_path` records active.yaml's own recorded path
    # UNCONDITIONALLY, regardless of whether the file it points at still exists, so a
    # caller that only needs the PATH SHAPE (not proof of a live artifact) still has
    # something to resolve a sig8 from.
    session_log_path = None
    if session is not None:
        raw_log_path = session.get("log_path")
        if raw_log_path:
            row["raw_log_path"] = raw_log_path
            candidate = raw_log_path if os.path.isabs(raw_log_path) else os.path.join(root, raw_log_path)
            if os.path.isfile(candidate):
                session_log_path = candidate

    # NOTE: no early "lane_dir doesn't exist -> dead:no_handoff_dir" bailout
    # here (STATUSLINE-COUNT-TRUTH-02 fix) -- that used to short-circuit
    # BEFORE the S2 registration check below ever ran, so a freshly-
    # registered session with no handoff dir yet (the exact "starting" case
    # D1 exists to fix) fell straight to dead:no_handoff_dir. `os.path.isfile`
    # on a path under a nonexistent directory is a safe False, never an
    # exception, so every candidate check below degrades correctly without
    # this bailout; the label is now decided once, at the bottom of S2.

    # S1 (STATUSLINE-COUNT-TRUTH-02): closed, ordered candidate list for the
    # lane's OWN worker stream -- no directory scan, no "newest file in the
    # dir wins" fallback. That fallback WAS the D3 bug: a lead's own
    # hand-written review-critic-opus.md, touched hours after the lane died,
    # outlived the worker and read as alive. Order: (a) active.yaml's own
    # log_path [above], (b)/(c) this lane's own developer/architect stream,
    # (d) legacy session.log/fanout.log (newest of the two).
    log_path = session_log_path
    source = "active.yaml:log_path" if session_log_path else None
    if log_path is None:
        for name in ("developer.stream.jsonl", "architect.stream.jsonl"):
            candidate = os.path.join(lane_dir, name)
            if os.path.isfile(candidate):
                log_path, source = candidate, name
                break
    if log_path is None:
        candidates = [os.path.join(lane_dir, "session.log"), os.path.join(lane_dir, "fanout.log")]
        existing = [(p, os.path.basename(p)) for p in candidates if os.path.isfile(p)]
        if existing:
            # MINOR fix: when both logs exist, the NEWEST by mtime is authoritative
            # — the first-found path used to win even if it was a stale leftover,
            # producing false silence while the other log was actively updating.
            log_path, source = max(existing, key=lambda pair: os.path.getmtime(pair[0]))

    if log_path is None:
        # S2: no worker stream of the lane's OWN. Two registration signals,
        # checked in order -- neither hardcodes a suffix beyond CHILD_SUFFIXES:
        #  1) a folded child's OWN stream (e.g. dispatch-<sig8>-architect/
        #     architect.stream.jsonl) is composed evidence that THIS lane is
        #     mid-prepass (R-6: dispatch.json is aspirational -- zero exist on
        #     the live tree measured 2026-07-31, so the prepass's own stream
        #     is the real signal today). Classified on the SAME fresh/stale/
        #     dead tiers as a normal stream (SILENT_MAX/ABANDON_MAX), just
        #     labelled starting/silent/dead-abandoned since no developer
        #     stream exists yet.
        #  2) active.yaml session or a lane-local dispatch.json with NO stream
        #     of any kind yet -- a pure registration-only grace window,
        #     bounded by STARTING_MAX off age_from_started_at (D1).
        # LANE-REGISTRY-SELF-DEADLOCK-01 (Defect 2): signal 1 is OFF by
        # default now. The architect prepass runs SYNCHRONOUSLY inside
        # leadv2-dispatch-code.sh itself (before any spawn), so a fresh
        # prepass-stream mtime is residue of a dispatch ATTEMPT, never proof
        # of a running worker — and every refused re-dispatch re-runs the
        # prepass, refreshing the very mtime that caused the refusal
        # (EGRESS-STATUS-COLLECTOR-01, task e5be9e72). The whole block is
        # kept behind LEADV2_LANE_PREPASS_LIVE=1 (not deleted) so the R-6
        # rationale and its fixture stay testable.
        child_stream = None
        if prepass_live:
            for suffix in CHILD_SUFFIXES:
                candidate = os.path.join(f"{lane_dir}-{suffix}", f"{suffix}.stream.jsonl")
                if os.path.isfile(candidate) and (
                    child_stream is None or os.path.getmtime(candidate) > os.path.getmtime(child_stream)
                ):
                    child_stream = candidate
        if child_stream is not None:
            mtime = file_mtime(child_stream)
            if mtime is None:
                row["age_s"] = age_from_started_at(session)
                row.update(verdict="dead:log_stat_failed", source=child_stream, reason="prepass_stat_failed")
                return row
            age = max(0, int(time.time()) - mtime)
            row["age_s"], row["source"], row["log_path"] = age, child_stream, child_stream
            if age <= silent_max:
                row.update(verdict=f"starting:{age}", reason="prepass_stream_fresh")
            elif age <= abandon_max:
                row.update(verdict=f"silent:{age}", reason="prepass_stream_stale")
            else:
                # Verdict prefix matches the pre-existing dead:silent_ family
                # (test-lane-liveness-authoritative.sh D1) rather than a new
                # dead:abandoned_ label -- same ceiling concept, one naming
                # convention for "was silent, now past ABANDON_MAX" dead lanes.
                row.update(verdict=f"dead:silent_{age}s_abandoned", reason="prepass_stream_abandoned")
            return row

        # Tier A only ever emits a POSITIVE 'starting:' verdict, inside the
        # grace window. Past STARTING_MAX it deliberately falls through to
        # the SAME dead determination as "no evidence of any kind" below --
        # age alone must never invent a new dead label the rest of the
        # system (test-lane-liveness-authoritative.sh's D2 negative control:
        # an old, pid-less, artifact-less session must still resolve plain
        # dead:no_handoff_dir, not a bespoke starting-timeout verdict).
        dispatch_json = os.path.join(lane_dir, "dispatch.json")
        registered = session is not None or os.path.isfile(dispatch_json)
        age = None
        if registered:
            age = age_from_started_at(session)
            if age is None and os.path.isfile(dispatch_json):
                dj_mtime = file_mtime(dispatch_json)
                age = max(0, int(time.time()) - dj_mtime) if dj_mtime is not None else None
            if age is not None and age <= starting_max:
                row["age_s"] = age
                row.update(verdict=f"starting:{age}", source="registered_no_stream", reason="registered_no_stream")
                return row

        row["age_s"] = age if age is not None else age_from_started_at(session)
        # C2 floor (STATUSLINE-SHOWS-LANES-QUESTIONMARK-01): a provably live
        # PID with no artifact yet is absence-of-evidence, not death -- the
        # dead:* labels below stay for pid-less lanes only. Deliberately NOT
        # bounded by abandon_max (the D4 cut lives on the log-artifact ladder
        # and is not replicated here): the C2 fixture pins started_at 2020-01-01
        # and still requires silent:.
        # LANE-REGISTRY-SELF-DEADLOCK-01 exception: a lead_durable pid is the
        # lead session's own pid -- ignoring it here is the deadlock-breaker
        # for a lead-registered lane whose worker died before ever writing a
        # stream (design §2.1 state 7). Legacy rows keep the exact old floor.
        if row["pid"] is not None and row["pid_alive"] and row.get("pid_source") != "lead_durable":
            row.update(verdict=f"silent:{row['age_s'] if row['age_s'] is not None else 'unknown'}",
                       source="handoff", reason="no_artifact_process_alive")
            return row
        if not os.path.isdir(lane_dir):
            row.update(verdict="dead:no_handoff_dir", source="handoff", reason="no_handoff_dir")
        else:
            row.update(verdict="dead:no_log_artifact", source="handoff", reason="no_log_artifact")
        return row
    # `source` is the selected artifact path, not an inferred status label;
    # callers can therefore prove session.log/fanout.log/log_path selection
    # directly.
    row["log_path"], row["source"] = log_path, log_path
    mtime = file_mtime(log_path)
    if mtime is None:
        row["age_s"] = age_from_started_at(session)
        row.update(verdict="dead:log_stat_failed", reason="log_stat_failed")
        return row
    row["age_s"] = max(0, int(time.time()) - mtime)
    # A Codex mapping is the sole provider exception.  It never applies to a
    # Claude lane merely because a Codex job happens to be running.
    job_id = lane_job_id(tid)
    job = jobs.get(job_id) if job_id else None
    provider_status = None
    if job:
        provider_status = str(job.get("status") or "unknown").lower()
        row["source"] = "codex-task.sh"
        row["provider_status"] = provider_status
    is_fresh = row["age_s"] <= silent_max
    if not v2_mode:
        # LEADV2_LANE_LIVENESS_V2=0 rollback: exact prior implementation —
        # self-reported queued/running is trusted as alive before log age or
        # PID evidence is evaluated.
        if provider_status in ("queued", "running"):
            row.update(verdict="alive", reason=f"provider_{provider_status}")
            return row
        if provider_status in ("completed", "done", "cancelled", "failed"):
            row.update(verdict=f"dead:provider_{provider_status}", reason=f"provider_{provider_status}")
            return row
    elif not is_fresh and provider_status in ("completed", "done", "cancelled", "failed"):
        # B8 fix (SUPERVISOR-AUDIT-01 fix-round-3): terminal provider status is
        # only corroborating evidence the job is provably finished ONCE the
        # log itself has gone silent. A FRESH log (age <= silent_max) is
        # authoritative on its own and must never be overridden by a terminal
        # self-report — the reviewer's exact probe was a fresh session.log, no
        # PID, and a mapped provider job reporting "cancelled": that must
        # resolve alive (or silent, never dead) because something is still
        # actively writing regardless of what the provider job says finished.
        row.update(verdict=f"dead:provider_{provider_status}", reason=f"provider_{provider_status}")
        return row
    # SENTINEL-COMPLETION-01 (LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01):
    # a runner-written .finalized sentinel combined with a dead process group
    # is proof (not a report) that the lane is finished — it outranks log
    # freshness because the fresh mtime IS the completion flush.  Placed after
    # B8 (so B8's not-fresh + terminal-status path wins on ties) and before the
    # wedged-process / fresh / stale ladder below (which is untouched).
    # Fires regardless of is_fresh — that is the whole point.
    if sentinel_check(tid, row):
        return row
    # Provider queued/running (v2_mode) is now ANNOTATION ONLY — it never
    # short-circuits the verdict; log mtime + process evidence below decide.
    # Preserve stopped-process detection in the same verdict source.
    # LANE-REGISTRY-SELF-DEADLOCK-01: gated on a non-lead pid — a wedged LEAD
    # session must never mark a lane dead (design §2.1 state 12).
    if row["pid"] is not None and row["pid_alive"] and row.get("pid_source") != "lead_durable":
        stat = ps_stat(row["pid"])
        if "T" in stat:
            row.update(verdict=f"dead:wedged_STAT={stat}", reason=f"wedged_STAT={stat}")
            return row
    suffix = f"+provider_{provider_status}" if provider_status else ""
    if is_fresh:
        row.update(verdict="alive", reason=f"log_fresh{suffix}")
    elif row["age_s"] > abandon_max and provider_status in ("queued", "running"):
        # PULSE-READABLE-01 (SD-PULSE-LIVENESS-BY-JOB-REGISTRY-01): a stale
        # stream mtime is not proof of death when the CURRENT attempt's job
        # registry — `provider_status`, read fresh above from `jobs`, itself
        # built from a live `codex-task.sh status --all` call keyed by
        # lane_job_id(tid) i.e. THIS lane's own codex-plan.json job_id, never
        # a stale mapping — says the job is still queued/running. The stream
        # file that aged past abandon_max can belong to a PREVIOUS attempt on
        # this lane (a relaunch writes a NEW stream, but codex-plan.json's
        # job_id already points at the new job before that stream exists or
        # catches up). The 2026-08-21T08:09:49Z beat reported
        # dispatch-21f644a1 as dead:silent_200431s_abandoned while its codex
        # job had been running since 08:05:43Z -- the 200431s came from a
        # stream last written by a prior attempt two days earlier. Never
        # label a lane dead while its own current-attempt registry says
        # otherwise; downgrade to silent so it stays visible in the pulse,
        # not evicted as abandoned. (v2_mode's "annotation only" comment
        # above still holds for the is_fresh/alive path -- this is the ONE
        # place a provider self-report is allowed to veto a dead verdict,
        # and only a dead verdict this specific staleness reason would have
        # produced with no other evidence.)
        row.update(verdict=f"silent:{row['age_s']}", reason=f"abandoned_but_provider_{provider_status}")
    elif row["age_s"] > abandon_max:
        # D4 fix: staleness has an upper bound. Past ABANDON_MAX a silent lane
        # is DEAD regardless of PID state -- it no longer belongs in the
        # numerator, and it stops sitting in the digest as "still worth
        # watching" (this is the exact mechanism behind the measured
        # `silent:221853` / lanes 18/5 disease). Verdict prefix matches the
        # pre-existing dead:silent_ family (test-lane-liveness-authoritative.sh
        # D1/boundary assertions), not a new dead:abandoned_ label.
        row.update(verdict=f"dead:silent_{row['age_s']}s_abandoned", reason=f"abandoned{suffix}")
    elif row["pid"] is None:
        row.update(verdict=f"silent:{row['age_s']}", reason=f"no_pid_recorded{suffix}")
    elif row["pid_alive"] and row.get("pid_source") != "lead_durable":
        row.update(verdict=f"silent:{row['age_s']}", reason=f"log_silent_process_alive{suffix}")
    else:
        # LANE-REGISTRY-SELF-DEADLOCK-01: this arm is reached three ways —
        # (a) pid dead (pre-existing), (b) pid alive but pid_identity=mismatch
        # (pid_state folds a recycled pid into pid_alive=False; design §2.1
        # state 4), (c) pid alive but pid_source=lead_durable, i.e. the lead
        # session's own pid, which is not worker evidence (state 5 — the
        # deadlock-breaker).
        row.update(verdict=f"dead:silent_{row['age_s']}s_no_process", reason=f"log_silent_no_process{suffix}")
    return row

def compatible_jobs():
    out = []
    for job in jobs.values():
        status = str(job.get("status") or "unknown").lower()
        verdict = {"queued": "running", "running": "running", "completed": "done", "done": "done",
                   "cancelled": "cancelled", "failed": "failed"}.get(status, "unknown")
        out.append({"id": job.get("id", "?"), "status": status, "phase": str(job.get("phase") or status),
                    "verdict": verdict, "started_at": job.get("startedAt") or job.get("createdAt"),
                    "updated_at": job.get("updatedAt"), "reason": job.get("reason") or job.get("errorMessage") or job.get("error") or job.get("message"),
                    "source": "codex-task.sh status"})
    return out

if wanted_job:
    # Back-compatible provider response for callers that ask by job id.
    payload = {"provider": "codex", "precedence": "authoritative_provider_status",
               "jobs": compatible_jobs(), "availability": "authoritative" if jobs else "unavailable"}
    print(json.dumps(payload) if json_mode else (payload["jobs"][0]["verdict"] if payload["jobs"] else "unknown"))
elif wanted_lane:
    row = resolve(wanted_lane)
    print(json.dumps(row, separators=(",", ":")) if json_mode else row["verdict"])
else:
    # R0 fix: discovery previously only globbed session.log/fanout.log, which
    # NOTHING in the live tree still writes (leadv2-dispatch-code.sh,
    # leadv2-fanout.sh, leadv2-fanout-lane-launcher.sh all write
    # developer.stream.jsonl) -- measured 2026-07-31: 0 of 173 dispatch-*
    # dirs had session.log/fanout.log. A glob hit on a folded child id
    # (dispatch-<sig8>-<suffix>) surfaces its PARENT instead of the child
    # itself -- the child never gets its own row (S0).
    ids = set(sessions)
    for pattern in WORKER_STREAM_NAMES:
        for p in glob.glob(os.path.join(root, "docs", "handoff", "*", pattern)):
            hit_tid = os.path.basename(os.path.dirname(p))
            parent = fold_match(hit_tid)
            ids.add(parent if parent is not None else hit_tid)
    ids = sorted(
        tid for tid in ids
        if tid not in tombstoned
        and not os.path.exists(os.path.join(root, "docs", "handoff", tid, ".close"))
        and fold_match(tid) is None
    )
    lanes = [resolve(tid) for tid in ids]
    # R2/1b: count_live is the ONE definition of the numerator -- alive or
    # mid-prepass (starting:*). silent:* and every dead:* are excluded; child
    # rows never reach `lanes` at all (folded out of `ids` above).
    count_live = sum(
        1 for r in lanes
        if r.get("verdict") == "alive" or (isinstance(r.get("verdict"), str) and r["verdict"].startswith("starting:"))
    )
    payload = {"lanes": lanes, "jobs": compatible_jobs(), "availability": "authoritative" if jobs else "unavailable",
               "count_live": count_live}
    if json_mode:
        print(json.dumps(payload))
    else:
        for row in lanes:
            print(f"{row['lane']} {row['verdict']}")
PY
