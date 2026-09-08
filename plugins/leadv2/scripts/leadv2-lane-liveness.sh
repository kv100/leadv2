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

# PLUGINS-DOCS-LANE-SHARE-01: PROJECT_ROOT is trusted verbatim by every caller
# (--project-root / LEADV2_PROJECT_ROOT / bare $PWD) with no guarantee it is
# actually a repo toplevel -- a caller that derives it by counting `../` hops
# from a script under plugins/leadv2/scripts/ (two hops: scripts -> leadv2 ->
# plugins) undershoots the real toplevel by one directory and hands us
# "<repo>/plugins". leadv2-state-path.sh already re-derives its own LINK_ROOT
# through `git rev-parse --show-toplevel` for exactly this reason (any
# subdirectory of a repo resolves to the SAME toplevel), which is why the
# state-path.sh branch below silently self-heals. The raw fallback two lines
# down does not -- it string-concats PROJECT_ROOT as given, so a mis-rooted
# caller lands the lane-liveness share dir at "<repo>/plugins/docs/leadv2/
# .lane-liveness-share" instead of "<repo>/docs/leadv2/.lane-liveness-share".
# Measured 2026-09-08 (lane d2823c51e670): both paths existed side by side.
# Re-root the same way state-path.sh does, fail-open to the value we were
# given when git resolution is unavailable (test sandboxes, non-repo fixtures).
if [[ -n "$PROJECT_ROOT" ]]; then
  _ll_git_root="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$_ll_git_root" ]] && PROJECT_ROOT="$_ll_git_root"
  unset _ll_git_root
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
# LANE-LIVENESS-CODEX-TIMEOUT-01 (measured 2026-08-31): `codex-task.sh status`
# shells out to the Codex CLI, which can block indefinitely -- observed >240s
# with zero output. This call sits at the FRONT of every dispatch
# (dispatch-code.sh ledger sweep -> lane-liveness --all -> here), so an
# unbounded hang here makes dispatch unavailable in EVERY adopted repo, and it
# presents as a dispatcher deadlock rather than as a Codex stall. The
# pre-existing `2>/dev/null || true` fails open on a non-zero EXIT but cannot
# fail open on a HANG. Bound the call; a timeout yields an empty payload, which
# is exactly the already-supported "no codex data" path.
# LEADV2_CODEX_STATUS_TIMEOUT_S tunes it; 0 restores the old unbounded
# behaviour (one-step rollback).
_lane_codex_status() {
  local t="${LEADV2_CODEX_STATUS_TIMEOUT_S:-20}"
  local runner=""
  if [[ "$t" != "0" ]]; then
    if command -v timeout >/dev/null 2>&1; then runner="timeout $t"
    elif command -v gtimeout >/dev/null 2>&1; then runner="gtimeout $t"
    fi
  fi
  # No timeout(1) on this PATH -> run unbounded rather than lose the data.
  ${runner} bash "$CODEX_TASK" "$@" 2>/dev/null || true
}
# ── CONTROL-PLANE-SATURATES-01: single-flight + short-TTL verdict share ────
# lane-liveness is a PURE probe (verdicts on stdout; the python writes no
# state) with ~60 invokers across the plugin — dispatch-code's ledger sweep,
# backlog-pump, idle-lead-guard, status-surface, lane-watch, and
# worktree-cleanup --sweep-dead calling it PER WORKTREE. None of them
# serialize, so N concurrent sessions each mint N concurrent ~1170-line
# python3 passes over `ps`. Measured 2026-09-06T10:3xZ: 8 lane-liveness
# pythons at 25-35% CPU each inside load 167 on 10 cores — the machine
# saturation that tripped time-sensitive suites red and got lane
# B0-READER-HALF-01 falsely marked terminal=dead on delivered work.
#
# The dedup lives HERE, in the probe itself, so every caller is covered
# without touching any spawner (several are other lanes' write sets):
#   * subject = (--lane X | --job Y | --all) × json × codex-mode ×
#     project root × state paths × the LEADV2_LANE_* verdict knobs — one
#     slot per subject, next to the resolved active.yaml (cross-worktree
#     control plane, like the stale-sweeper's single-flight lock);
#   * a completed verdict fresher than SHARE_TTL_S (default 10s) with no
#     live in-flight owner is replayed byte-identically — no python3 at all;
#   * a live in-flight owner (mkdir-atomic in-flight.d, owner.pid +
#     ps-lstart birth identity) is waited on (up to WAIT_S, default 30s —
#     the codex shell-out is itself bounded at 20s) and its verdict shared;
#   * reclaim only on POSITIVE death: kill -0 has three answers, and EPERM
#     (e.g. pid 1) means ALIVE; a live pid whose birth cannot be observed
#     degrades to alive — never reclaim a slot on a guess;
#   * any doubt (wait timeout, reclaim race lost) runs the probe directly —
#     a duplicate verdict is always cheaper than a blocked one.
# LEADV2_LANE_LIVENESS_SHARE=0 disables the gate (one-step rollback).
# LEADV2_TEST_CONTEXT=1 (exported by every suite runner) also disables it,
# so existing liveness suites stay byte-deterministic and never share state.
# LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE, when set, gets one line per REAL
# probe execution — the dedup measurement seam (unset in production: free).
_ll_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}
_ll_pid_alive() {
  # kill -0 has THREE answers, not two: rc=0 alive; ESRCH dead; EPERM alive
  # (a process we may not signal — e.g. pid 1 — is running, not gone).
  local pid="$1" err
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  err="$(kill -0 "$pid" 2>&1)" && return 0
  case "$err" in
    *"not permitted"*|*"Not permitted"*|*"operation not permitted"*) return 0 ;;
    *) return 1 ;;
  esac
}
_ll_norm_lstart() {
  # squeeze AND trim: ps lstart output can carry leading/trailing spaces, and
  # a birth written by one normalizer must compare equal when observed by
  # another (suite fixtures, the sweeper's gate) — observed live 2026-09-06
  # as "every live holder read as provably stale".
  local s
  s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
_ll_inflight_owner_alive() { # <lockdir>
  # owner.pid + owner.birth (ps lstart identity, pid-reuse-proof). A live pid
  # with no/unobservable birth degrades to ALIVE — never reclaim on a guess.
  # Only a recorded birth CONTRADICTED by a live ps observation (pid
  # recycled) makes the holder provably stale.
  local dir="$1" owner birth observed
  owner="$(cat "$dir/owner.pid" 2>/dev/null || true)"
  _ll_pid_alive "$owner" || return 1
  birth="$(cat "$dir/owner.birth" 2>/dev/null || true)"
  [[ -n "$birth" ]] || return 0
  observed="$(_ll_norm_lstart "$(ps -o lstart= -p "$owner" 2>/dev/null || true)")"
  [[ -n "$observed" ]] || return 0
  [[ "$observed" == "$birth" ]]
}
_ll_release_flight() { # <lockdir>
  local dir="$1"
  if [[ -d "$dir" ]] && [[ "$(cat "$dir/owner.pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -f "$dir/owner.pid" "$dir/owner.birth" 2>/dev/null || true
    rmdir "$dir" 2>/dev/null || true
  fi
}
# The probe itself: codex status fetch + the python pass, verbatim, wrapped
# so the share gate below can decide WHO runs it and who replays its output.
_ll_run_probe() {
CODEX_RAW=''
if [[ "$NO_CODEX" -ne 1 && -f "$CODEX_TASK" ]]; then
  # --no-codex skips both `codex-task.sh status` shell-outs -- the statusline
  # hot path (leadv2-lane-status-line-tail.sh) never needs the provider
  # mapping, only log-based liveness (STATUSLINE-COUNT-TRUTH-02 R1).
  if [[ -n "$JOB_ID" ]]; then
    CODEX_RAW="$(_lane_codex_status status "$JOB_ID" --json --cwd "$PROJECT_ROOT")"
  else
    CODEX_RAW="$(_lane_codex_status status --all --json --cwd "$PROJECT_ROOT")"
  fi
fi

# --all resolves every lane in one Python pass.
python3 - "$PROJECT_ROOT" "$ACTIVE_YAML" "$TOMBSTONES" "$LANE_ID" "$JOB_ID" "$ALL" "$JSON" "$CODEX_RAW" "${LEADV2_LANE_SILENT_MAX_S:-900}" "${LEADV2_LANE_LIVENESS_V2:-1}" "${LEADV2_LANE_STARTING_MAX_S:-300}" "${LEADV2_LANE_ABANDON_MAX_S:-3600}" "$LEADV2_LANE_CHILD_SUFFIXES" "${LEADV2_LANE_SENTINEL_DEAD:-1}" "${LEADV2_LANE_SENTINEL_SETTLE_S:-60}" "${LEADV2_LANE_RUNS_ROOT:-}" "${LEADV2_LANE_SENTINEL_CLAUDE:-1}" "${LEADV2_LANE_PID_IDENTITY:-1}" "${LEADV2_LANE_PREPASS_LIVE:-0}" "${LEADV2_LANE_FINISHED_WINDOW_S:-1800}" <<'PY'
import errno, glob, json, os, re, subprocess, sys, time

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

def stream_end_shape(path):
    """WORKER-ENDS-TURN-ON-WAIT-01 (measured 2026-09-05): a worker that ENDED ITS
    TURN and a worker that DIED are indistinguishable in everything we record --
    both leave no process and a stale stream, and liveness reads the stream's
    MTIME only, never a byte of its content. But the discriminator is already on
    disk: `claude -p --output-format stream-json` writes a final {"type":"result"}
    record when the turn completes, and a process that vanished mid-turn cannot
    have written one.

    Census over 400 real lane streams in this repo: 308 end on `result`, 84 end on
    system/user/assistant/tool_progress. Joined against the terminal ledger, 218
    lanes are recorded `dead*` although their worker finished its turn cleanly, and
    21 are recorded non-dead although their stream stops mid-record.

    This reports a FACT and changes no verdict -- exactly the split the row asks
    for: first make the two states distinguishable, then decide what to do about
    them. Returns "result" | "truncated" | "empty" | "unreadable".
    """
    try:
        size = os.path.getsize(path)
    except OSError:
        return "unreadable"
    if size <= 0:
        return "empty"
    try:
        with open(path, "rb") as fh:
            # The last record is what matters; a fixed tail keeps this O(1) per lane
            # on multi-megabyte streams (this runs for EVERY lane on every repaint).
            fh.seek(max(0, size - 8192))
            tail = fh.read().decode("utf-8", "ignore")
    except OSError:
        return "unreadable"
    for line in reversed([x for x in tail.splitlines() if x.strip().startswith("{")]):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        return "result" if rec.get("type") == "result" else "truncated"
    return "truncated"


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
    # D2-M2-EPERM-IS-READ-AS-DEAD-01 (brief #9, C3): kept in sync with
    # pid_state's errno split below even though this function is currently
    # unreferenced inside this heredoc -- EPERM means the pid EXISTS
    # (owned by someone else), never "dead".
    try:
        os.kill(int(value), 0)
        return True
    except PermissionError:
        return True
    except (TypeError, ValueError, ProcessLookupError):
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

def _proc_kind(pid):
    # D2-M2-EPERM-IS-READ-AS-DEAD-01 / brief #14 (C1): kill(0)==0 only proves
    # SOME process owns this pid, not that it is THIS lane's worker — a
    # recorded pid can have been recycled onto the interactive lead session
    # itself (`claude --dangerously-skip-permissions`, no `-p`/`--print`).
    # Same discriminator as leadv2-active-registry.sh::_proc_kind
    # (PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01), duplicated rather than
    # imported: two independently-invoked bash+embedded-python scripts, no
    # shared .py module exists yet for this one check. Keep both in sync.
    try:
        out = subprocess.run(["ps", "-p", str(pid), "-o", "args="],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return "unknown"
    if not out:
        return "dead"
    if ("claude" in out or "codex" in out) and (" -p" in out or "--print" in out):
        return "worker"
    if "claude" in out or "--dangerously-skip-permissions" in out:
        return "interactive"
    return "other"

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
    except ProcessLookupError:
        # ESRCH: the pid genuinely does not exist. The only true "dead".
        return ("dead", "unverified")
    except PermissionError:
        # D2-M2-EPERM-IS-READ-AS-DEAD-01 (brief #9): EPERM means the pid
        # EXISTS and is owned by someone else -- kill(0) has three answers,
        # not two, and this is not the dead one. A leadv2 watcher/worker that
        # reparented to ppid=1 (measured live: 22 leadv2-stale-sweeper.sh
        # instances at ppid=1) is exactly this shape, and reading it as dead
        # was the false zero that cost B0-READER-HALF-01 a `terminal=dead`
        # verdict on delivered work. Degrade the same way an unobservable
        # birth degrades below: alive, unverified -- never dead, never
        # promoted to alive_verified either (we cannot confirm identity or
        # kind for a pid we cannot fully inspect as our own).
        return ("alive_unverified", "unverified")
    except (TypeError, ValueError):
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
    if observed != recorded:
        return ("dead", "mismatch")
    # Birth matches -- same pid, same process, not recycled. D2-M2 (brief
    # #14/C1): birth equality alone does not prove KIND. Any disagreement on
    # kind demotes, never promotes (design §3 E2) -- a wedged `ps` (kind
    # "unknown") degrades to alive_unverified like every other unobservable
    # case above, it does not get read as a mismatch.
    kind = _proc_kind(pid)
    if kind == "worker":
        return ("alive_verified", "verified")
    if kind == "unknown":
        return ("alive_unverified", "unverified")
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

# D2-UNBLIND-AND-THIRD-STATE-M0M1-01 (M1): the registry's READABILITY is
# itself evidence. load_yaml folds "active.yaml absent" and "active.yaml
# unparseable" into the same {} as "present and empty", so a corrupt or
# missing registry was indistinguishable from "no row for this lane" -- and
# an artifactless lane then took a terminal dead:no_* verdict manufactured
# by an unreadable source. Parse active.yaml here (once, exact load_yaml
# semantics) and record the failure; resolve() demotes the no-evidence dead
# labels to unknown:yaml_unreadable, which every consumer's existing `*)`
# arm already treats as "indeterminate, write nothing" -- never a death.
active = {}
active_unreadable = not os.path.isfile(active_path)
if not active_unreadable:
    try:
        import yaml
        with open(active_path, encoding="utf-8") as fh:
            _active_value = yaml.safe_load(fh)
        if _active_value is not None:
            active = _active_value
    except Exception:
        active_unreadable = True
sessions = {str(s.get("task_id")): s for s in (active.get("sessions") or [])
            if isinstance(s, dict) and s.get("task_id")}
# D2-E4-RESOLVES-THE-WRONG-DIR-01 (round 2): a lane can carry SEVERAL registry
# rows (one per dispatch attempt / re-arm). `sessions` keeps only the LAST,
# whose log_path is often the pulse.md default -- the live D3 lane measured
# 2026-09-04 had its dispatch-<sig8> pointer on row 1 of 3 and a pulse.md
# pointer on the last, so E4 resolved nothing and said dead:no_log_artifact
# about a lane whose deliverable existed. Keep every row of the lane for
# deliverable_dirs(): each pointer is still from THIS lane's own row, exact
# attribution, never a glob across docs/handoff/.
sessions_all = {}
for _s in (active.get("sessions") or []):
    if isinstance(_s, dict) and _s.get("task_id"):
        sessions_all.setdefault(str(_s.get("task_id")), []).append(_s)

# D2-M5 (D2-SINGLE-LIVENESS-VERDICT #14/#15, E0 contradiction guard): a
# genuine WORKER pid (never lead_durable/watcher -- those are excluded from
# process-liveness evidence everywhere else in this file, and a lead
# session's own pid legitimately spans every lane it is dispatching) that
# is recorded as the owner of MORE THAN ONE lane is a structural fact about
# the registry, not evidence about any one lane -- E0 must see it before
# resolve() ever reaches E2 for either lane.
worker_pid_to_tids = {}
for _tid, _s in sessions.items():
    _wp = None
    try:
        _w = int(_s.get("worker_pid"))
        if _w > 0 and _s.get("worker_pid_role") != "watcher":
            _wp = _w
    except (TypeError, ValueError):
        _wp = None
    if _wp is not None:
        worker_pid_to_tids.setdefault(_wp, set()).add(_tid)

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

# --- BOARD-BLIND-TO-DETACHED-WORKERS-01 --------------------------------------
# dispatch-code.sh's glm/glm-flash/kimi/freepool/codex arms spawn DETACHED
# workers: no local PID this ladder could kill -0, only a handle, recorded at
# spawn time in docs/handoff/<tid>/arm-registered (`arm=<arm> handle=<handle>`,
# one appended line per CONFIRMED spawn -- the last line is the current
# attempt). The registry row for such a lane keeps pid_role=lead_durable (the
# dispatcher's own pid), which the ladder deliberately refuses to read as
# worker evidence (LANE-REGISTRY-SELF-DEADLOCK-01) -- correct for the lead,
# but nothing replaced the missing worker leg, so a running detached worker
# resolved dead:no_log_artifact / dead:silent_no_process and the board printed
# ДОСКА ПУСТА while the lane later PASSed its review (observed 2026-08-29
# 00:19Z/00:33Z/00:49Z, dispatch-ef95d34a codex + dispatch-ab0ec014 glm; the
# glm run dir's journal.jsonl was still being written at probe time).
# This probe is that leg: ask the WORKER's own liveness channel.
#   glm*/kimi/freepool: <runs>/<arm>-runs/<handle>/pgid, group-alive via
#       kill(-pgid, 0) -- the same primitive the sentinel check above and the
#       coders' own single-flight locks use.
#   codex: the jobs registry already loaded (codex-task.sh status --all), keyed
#       by job id == the arm-registered handle -- queued/running means live.
# Positive-only: an absent arm-registered, a missing run dir, an unparsable
# pgid, or an unknown/terminal job are all NOT live -- this can never turn a
# genuinely finished lane alive, so dead rows stay releasable (the opposite
# direction of the fix).
def detached_worker_live(tid, row):
    arm = handle = ""
    try:
        with open(os.path.join(root, "docs", "handoff", tid, "arm-registered"),
                  encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line.startswith("arm="):
                    continue
                arm = handle = ""
                for field in line.split():
                    if field.startswith("arm="):
                        arm = field[4:]
                    elif field.startswith("handle="):
                        handle = field[7:]
    except OSError:
        return None
    if not arm or not handle or "/" in handle or ".." in handle:
        return None  # same path-traversal guard resolve_run_dir applies
    if arm in ("glm", "glm-flash", "kimi", "freepool"):
        base = os.environ.get(
            {"glm": "GLM_RUNS_DIR", "kimi": "KIMI_RUNS_DIR",
             "freepool": "FREEPOOL_RUNS_DIR"}.get(arm, ""))
        if not base:
            runs_arm = "glm" if arm.startswith("glm") else arm
            base = os.path.join(
                runs_root_raw if runs_root_raw else os.path.expanduser("~/.claude/cache"),
                f"{runs_arm}-runs",
            )
        run_dir = os.path.join(base, handle)
        pgid = None
        try:
            with open(os.path.join(run_dir, "pgid"), encoding="utf-8") as fh:
                pgid = int(fh.read().strip())
        except (OSError, ValueError):
            return None
        if pgid <= 0:
            return None
        row["detached_arm"], row["detached_handle"], row["detached_pgid"] = arm, handle, pgid
        if not pgid_group_alive(pgid):
            return None
        newest = None
        for name in ("journal.jsonl", "progress.log"):
            m = file_mtime(os.path.join(run_dir, name))
            if m is not None and (newest is None or m > newest):
                newest = m
        if newest is not None:
            row["detached_age_s"] = max(0, int(time.time()) - newest)
        return f"detached_{arm}_pgid_live"
    if arm == "codex":
        job = jobs.get(handle)
        if job is None:
            return None
        row["detached_arm"], row["detached_handle"] = arm, handle
        status = str(job.get("status") or "").lower()
        if status in ("queued", "running"):
            return f"detached_codex_job_{status}"
        return None
    return None

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

def deliverable_dirs(tid, lane_sessions):
    # D2-E4-RESOLVES-THE-WRONG-DIR-01: E4 used to search only
    # docs/handoff/<tid>/, but a lane addressed by its FOUNDER task id never
    # keeps its deliverable there -- the single-worker funnel writes
    # docs/handoff/dispatch-<sig8>/developer.full.md and records that
    # directory's stream path in the lane's OWN registry row
    # (leadv2_active_set_log_path, leadv2-dispatch-code.sh). Resolve the
    # row's pointer into the candidate set so a founder id reaches the same
    # deliverable as its dispatch-<sig8> id. Never glob docs/handoff/: the
    # pointers come from THIS lane's own rows (keyed by this task_id,
    # written by the dispatcher at spawn), which is exact attribution; a
    # glob would credit another lane's report to this one -- a false
    # finished_unlanded, the mirror mistake. lane_sessions is EVERY row the
    # registry holds for this task_id (round 2): `sessions` keeps only the
    # LAST row per lane, and a re-armed lane's last row often carries the
    # pulse.md default -- measured live on 2026-09-04: the pointer lived on
    # row 1 of 3, E4 saw only the pulse.md row, resolved nothing, and said
    # dead:no_log_artifact about a lane whose deliverable existed. Every
    # row's pointer is still this lane's own. The parent must be a DIRECT
    # child of the handoff root: the pulse.md default (docs/leadv2/tasks/...)
    # and a degenerate pointer name no lane handoff dir and add no
    # candidate.
    # Returns (dirs, unreadable). `unreadable` is set when a candidate dir
    # EXISTS but cannot be READ (EACCES etc.) -- a check that could not
    # look, which resolve() must surface as unknown:, never let fall to a
    # dead verdict about a directory it was unable to inspect.
    dirs = [os.path.join(root, "docs", "handoff", tid)]
    handoff_root = os.path.normpath(os.path.join(root, "docs", "handoff"))
    for sess in (lane_sessions or []):
        lp = (sess or {}).get("log_path")
        if not lp:
            continue
        cand = os.path.normpath(lp if os.path.isabs(lp) else os.path.join(root, lp))
        parent = os.path.dirname(cand)
        if parent != handoff_root and os.path.dirname(parent) == handoff_root \
                and parent not in dirs:
            dirs.append(parent)
    unreadable = None
    for d in dirs:
        if not os.path.isdir(d):
            continue
        try:
            os.listdir(d)
        except OSError as e:
            if e.errno == errno.ENOENT:
                continue  # raced away between isdir and listdir: just absent
            unreadable = os.path.basename(d)
            break
    return dirs, unreadable

def deliverable_age_s(lane_dirs):
    # D2-UNBLIND-AND-THIRD-STATE-M0M1-01 (M1, rung E4): externally checkable
    # fact -- the lane's OWN deliverable report, the artifact a finished
    # worker writes when its work never lands as a commit. Guards mirror
    # commit_age_s's refusal to fabricate: no dir / no report / empty
    # (placeholder) report -> None, never a fabricated age. lane_dirs is the
    # lane's OWN closed candidate set from deliverable_dirs() (D2-E4-...-01:
    # tid-named dir + registry-resolved dispatch dir); the newest NON-EMPTY
    # *.full.md or *.summary.md across ALL of them wins, so a stale
    # prior-round report sitting next to a fresh one cannot mask the fresh
    # evidence, and a report in the dispatch dir is found from a founder id.
    # Content is never inspected -- a DELIVERABLE_BLOCKED report is still a
    # finished round that did work and said why it stopped.
    if not lane_dirs:
        return None
    newest = None
    for lane_dir in lane_dirs:
        if not lane_dir or not os.path.isdir(lane_dir):
            continue
        for pattern in ("*.full.md", "*.summary.md"):
            for path in glob.glob(os.path.join(lane_dir, pattern)):
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                if st.st_size <= 0:
                    continue
                if newest is None or st.st_mtime > newest:
                    newest = st.st_mtime
    if newest is None:
        return None
    return max(0, int(time.time()) - int(newest))

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
        # D2-M5 (D2-SINGLE-LIVENESS-VERDICT #14/#15): E0 contradiction guard,
        # evaluated before any other rung. Ordering: lands only after D1 M1,
        # which makes duplicate active.yaml rows for one task_id impossible
        # to CREATE going forward -- a survivor here is a genuine structural
        # fact about the registry (nothing can rescue it), not a normal
        # multi-attempt history. Decisive: never alive, never dead, and no
        # lower rung may promote past it.
        _e0_reason = None
        if len(sessions_all.get(tid) or []) > 1:
            _e0_reason = "multiple_rows"
        else:
            _e0_wt = str(session.get("worktree") or "")
            if _e0_wt:
                try:
                    _e0_wt_real = os.path.realpath(_e0_wt)
                    _e0_root_real = os.path.realpath(root)
                except Exception:
                    _e0_wt_real, _e0_root_real = _e0_wt, root
                if _e0_wt_real == _e0_root_real:
                    _e0_reason = "worktree_is_project_root"
            if _e0_reason is None:
                _e0_wpid = None
                try:
                    _e0_w = int(session.get("worker_pid"))
                    if _e0_w > 0 and session.get("worker_pid_role") != "watcher":
                        _e0_wpid = _e0_w
                except (TypeError, ValueError):
                    _e0_wpid = None
                if _e0_wpid is not None and len(worker_pid_to_tids.get(_e0_wpid, ())) > 1:
                    _e0_reason = "pid_owns_multiple_lanes"
        if _e0_reason is not None:
            row.update(verdict="unknown:contradictory_rows", source="e0_contradiction_guard",
                       reason=_e0_reason)
            return row

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
            # FORK-STORM-KILLS-HOOKS-01: a watcher-kind pid is NOT a worker.
            # The dispatcher re-pins async-arm rows to its lane-pulse watcher
            # (leadv2-dispatch-code.sh, PULSE-BOARD-EMPTY round 4); when that
            # watcher outlives the dispatch it made every later dispatch for
            # the lane read `live` off a process that only WATCHES the journal
            # -- the closed loop behind three lane_is_live incidents
            # (2026-09-01). A watcher pid is still reported (annotation), but
            # it never counts as process-liveness evidence: every rung below
            # that consults pid_source excludes "watcher" exactly like
            # "lead_durable", and `watcher_only` marks the row so callers
            # (placement probe) can distinguish a stale-watcher lane.
            if session.get("worker_pid_role") == "watcher":
                row["pid_source"] = "watcher"
                row["watcher_only"] = 1
            else:
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
    # FORK-STORM-KILLS-HOOKS-01: "watcher" joins "lead_durable" here too — a
    # live watcher pid must not block the finished-window verdict, same
    # reasoning as the C2 floor below.
    if session is not None and row.get("pid_source") not in ("lead_durable", "watcher"):
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
            row["stream_end"] = stream_end_shape(child_stream)
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
        # FORK-STORM-KILLS-HOOKS-01: the positive `starting:` rung is pid-free
        # (age off started_at alone), so a row re-pinned to a stale watcher —
        # whose started_at every retry's idempotent re-registration refreshes —
        # would re-earn it forever and feed the skip/refuse loop. A
        # watcher-only row gets NO starting grace: it falls straight through
        # to the dead determination below (the C2 floor already excludes
        # watcher pids).
        if registered and not row.get("watcher_only"):
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
        # FORK-STORM-KILLS-HOOKS-01: a watcher pid joins the exclusion — a
        # stale watcher keeping the row "alive" must never hold the lane at
        # silent:no_artifact_process_alive (acceptance 9: a lane whose only
        # live process is a watcher is NOT live).
        if row["pid"] is not None and row["pid_alive"] and row.get("pid_source") not in ("lead_durable", "watcher"):
            row.update(verdict=f"silent:{row['age_s'] if row['age_s'] is not None else 'unknown'}",
                       source="handoff", reason="no_artifact_process_alive")
            return row
        # BOARD-BLIND-TO-DETACHED-WORKERS-01: a registered lane with no stream
        # of its own would take the dead labels below -- but a DETACHED worker
        # writes into its run dir / worktree, not into this handoff dir, and
        # its lead_durable pid is (correctly) not worker evidence. Ask the
        # worker's own channel before declaring death; a finished worker
        # probes negative and keeps the exact verdict it had before this fix.
        det = detached_worker_live(tid, row)
        if det is not None:
            row["age_s"] = row.get("detached_age_s", row["age_s"])
            row.update(verdict="alive", reason=det, source="arm-registered")
            return row
        # D2-UNBLIND-AND-THIRD-STATE-M0M1-01 (M1, rung E4): a finished worker
        # whose work never landed as a commit still leaves a deliverable
        # report under its own handoff dir. 2026-09-03 incident: five workers
        # wrote docs/handoff/dispatch-<sig>/developer.full.md, no commit
        # landed, git log showed nothing, and this ladder read "no stream, no
        # pid" as dead:no_log_artifact -- four re-dispatches each destroyed
        # the previous round's only evidence. A non-empty *.full.md /
        # *.summary.md within LEADV2_LANE_FINISHED_WINDOW_S -- deliberately
        # the SAME window as the finished: rung near the top of resolve()
        # (no second tunable: two windows would let finished: and
        # finished_unlanded: disagree about one lane at one instant) -- is
        # finished work that has not landed, not death. Sits AFTER the C2
        # floor and the detached-worker probe above, so it only fires once
        # process evidence says not-alive; a worker still writing its report
        # (live pid) never reaches it. Verdict is a sibling of finished:
        # (consumers match finished*), nothing is renamed, and
        # dead:no_handoff_dir / dead:no_log_artifact become unreachable while
        # the deliverable exists -- the incident fix, with zero consumer
        # edits: unknown to every existing arm means "write nothing".
        # D2-E4-RESOLVES-THE-WRONG-DIR-01: the report lives under the lane's
        # REAL handoff dir, resolved by deliverable_dirs() -- the tid-named
        # dir (all a dispatch-<sig8>-shaped id ever had) plus the dispatch
        # dir the registry row points at (what a founder-shaped id actually
        # needs: the lead names lanes by founder id, and the deliverable is
        # never written to docs/handoff/<founder-id>/). If even that closed
        # candidate set cannot be LOOKED at -- a candidate dir that exists
        # but cannot be read -- that is unknown:, never dead: an
        # unresolvable location is a check that could not look, and dead
        # here would be manufactured exactly where the evidence is invisible.
        _deliverable_dirs, _dir_unreadable = deliverable_dirs(
            tid, sessions_all.get(tid) or ([session] if session else []))
        if _dir_unreadable is not None:
            row.update(verdict="unknown:deliverable_dir_unreadable",
                       source="deliverable", reason="deliverable_dir_unreadable")
            return row
        _deliverable_age = deliverable_age_s(_deliverable_dirs)
        if _deliverable_age is not None and _deliverable_age <= finished_window:
            row["age_s"] = _deliverable_age
            row.update(verdict=f"finished_unlanded:{_deliverable_age}s",
                       source="deliverable", reason="no_pid_recent_deliverable")
            return row
        # D2-UNBLIND-AND-THIRD-STATE-M0M1-01 (M1): an unreadable registry
        # must never manufacture the terminal dead labels below.
        # unknown:yaml_unreadable lands in every consumer's existing `*)`
        # arm ("indeterminate, write nothing"), same as bare `unknown`
        # today -- strictly safer than a death verdict sourced from a file
        # this run could not read.
        if active_unreadable:
            row.update(verdict="unknown:yaml_unreadable", source="handoff",
                       reason="registry_unreadable")
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
    row["stream_end"] = stream_end_shape(log_path)
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
    # BOARD-BLIND-TO-DETACHED-WORKERS-01: the ladder below reads a lead_durable
    # pid (the dispatcher's own -- dead the moment dispatch-code.sh exits) as
    # "no process", and a quiet stream as silence; together they issued a dead
    # verdict for detached workers that were demonstrably running. A POSITIVE
    # detached-worker probe outranks both: the worker's own channel is the
    # evidence these stream/pid legs cannot see. Gated on not is_fresh -- a
    # fresh stream already resolves alive below; and negative probes fall
    # through untouched, so a genuinely finished worker keeps its dead verdict.
    if not is_fresh:
        det = detached_worker_live(tid, row)
        if det is not None:
            row.update(verdict="alive",
                       reason=f"log_silent_{row['age_s']}s+{det}",
                       source="arm-registered")
            return row
    # Provider queued/running (v2_mode) is now ANNOTATION ONLY — it never
    # short-circuits the verdict; log mtime + process evidence below decide.
    # Preserve stopped-process detection in the same verdict source.
    # LANE-REGISTRY-SELF-DEADLOCK-01: gated on a non-lead pid — a wedged LEAD
    # session must never mark a lane dead (design §2.1 state 12).
    # FORK-STORM-KILLS-HOOKS-01: a watcher pid is equally non-evidence here.
    if row["pid"] is not None and row["pid_alive"] and row.get("pid_source") not in ("lead_durable", "watcher"):
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
}

# ── share gate execution (CONTROL-PLANE-SATURATES-01) ───────────────────────
if [[ "${LEADV2_LANE_LIVENESS_SHARE:-1}" != "1" || "${LEADV2_TEST_CONTEXT:-0}" == "1" ]]; then
  # rollback knob or a suite runner: behave exactly like the pre-gate script
  [[ -z "${LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE:-}" ]] || \
    printf 'probe pid=%s %s (share-off)\n' "$$" "$(date +%s)" >>"$LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE" 2>/dev/null || true
  _ll_run_probe
  exit $?
fi
_ll_ttl="${LEADV2_LANE_LIVENESS_SHARE_TTL_S:-10}"
_ll_wait="${LEADV2_LANE_LIVENESS_SHARE_WAIT_S:-30}"
[[ "$_ll_ttl" =~ ^[0-9]+$ ]] || _ll_ttl=10
[[ "$_ll_wait" =~ ^[0-9]+$ ]] || _ll_wait=30
_ll_share_root="$(dirname "$ACTIVE_YAML")/.lane-liveness-share"
_ll_slot_key="$(printf '%s\n' \
  "lane=${LANE_ID}" "job=${JOB_ID}" "all=${ALL}" "json=${JSON}" "nocodex=${NO_CODEX}" \
  "root=${PROJECT_ROOT}" "active=${ACTIVE_YAML}" "tomb=${TOMBSTONES}" \
  "suffixes=${LEADV2_LANE_CHILD_SUFFIXES:-}" \
  "silent=${LEADV2_LANE_SILENT_MAX_S:-900}" "v2=${LEADV2_LANE_LIVENESS_V2:-1}" \
  "starting=${LEADV2_LANE_STARTING_MAX_S:-300}" "abandon=${LEADV2_LANE_ABANDON_MAX_S:-3600}" \
  "sentdead=${LEADV2_LANE_SENTINEL_DEAD:-1}" "settle=${LEADV2_LANE_SENTINEL_SETTLE_S:-60}" \
  "runsroot=${LEADV2_LANE_RUNS_ROOT:-}" "sentclaude=${LEADV2_LANE_SENTINEL_CLAUDE:-1}" \
  "pidident=${LEADV2_LANE_PID_IDENTITY:-1}" "prepass=${LEADV2_LANE_PREPASS_LIVE:-0}" \
  "finwin=${LEADV2_LANE_FINISHED_WINDOW_S:-1800}" "codextmo=${LEADV2_CODEX_STATUS_TIMEOUT_S:-20}" \
  | _ll_sha256)"
_ll_slot="${_ll_share_root}/${_ll_slot_key}"
mkdir -p "$_ll_share_root" "$_ll_slot" 2>/dev/null || true

_ll_fresh() { # <slot> — a COMPLETED verdict younger than the TTL
  local ts
  ts="$(cat "$1/ts" 2>/dev/null || true)"
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1
  (( $(date +%s) - ts <= _ll_ttl ))
}
_ll_emit_cached() { # <slot> — replay byte-identically, same exit code
  local rc
  [[ -f "$1/result" ]] || return 1
  rc="$(cat "$1/rc" 2>/dev/null || true)"
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=0
  cat "$1/result"
  exit "$rc"
}
_ll_write_verdict() { # <slot> <rc> <tmp> — result first, rc next, ts LAST (waiters poll ts)
  local slot="$1" rc="$2" tmp="$3"
  mv "$tmp" "${slot}/result" 2>/dev/null || true
  printf '%s\n' "$rc" >"${slot}/rc" 2>/dev/null || true
  date +%s >"${slot}/ts" 2>/dev/null || true
}
_ll_own_flight() { # <lockdir> — take ownership of an acquired in-flight.d
  # NOTE: the traps reference the GLOBAL _ll_flight, never "$1" — a trap
  # fires after the function has returned, when "$1" is the top-level
  # script's positional parameter (empty), not this argument.
  printf '%s\n' "$$" >"$1/owner.pid" 2>/dev/null || true
  _ll_norm_lstart "$(ps -o lstart= -p "$$" 2>/dev/null || true)" >"$1/owner.birth" 2>/dev/null || true
  trap '_ll_release_flight "$_ll_flight"' EXIT
  trap '_ll_release_flight "$_ll_flight"; exit 143' TERM
  trap '_ll_release_flight "$_ll_flight"; exit 130' INT
  trap '_ll_release_flight "$_ll_flight"; exit 129' HUP
}
_ll_run_owned() { # <slot> <lockdir> — we hold the flight: probe, publish, emit
  local slot="$1" flight="$2" rc
  # double-check inside the lock: a fresh verdict may have landed while we raced
  if _ll_fresh "$slot"; then
    _ll_release_flight "$flight"; trap - EXIT TERM INT HUP
    _ll_emit_cached "$slot" || { _ll_run_probe; exit $?; }
  fi
  [[ -z "${LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE:-}" ]] || \
    printf 'probe pid=%s %s\n' "$$" "$(date +%s)" >>"$LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE" 2>/dev/null || true
  set +e
  _ll_run_probe >"${slot}/result.tmp.$$"
  rc=$?
  set -e
  _ll_write_verdict "$slot" "$rc" "${slot}/result.tmp.$$"
  cat "${slot}/result" 2>/dev/null
  _ll_release_flight "$flight"; trap - EXIT TERM INT HUP
  exit "$rc"
}

_ll_flight="${_ll_slot}/in-flight.d"
_ll_reclaims=0
while :; do
  # fresh completed verdict, nobody in flight → replay, no python3 spawned
  if [[ ! -d "$_ll_flight" ]] && _ll_fresh "$_ll_slot"; then
    _ll_emit_cached "$_ll_slot" || true
    break
  fi
  if mkdir "$_ll_flight" 2>/dev/null; then
    _ll_own_flight "$_ll_flight"
    _ll_run_owned "$_ll_slot" "$_ll_flight"
  fi
  if ! _ll_inflight_owner_alive "$_ll_flight"; then
    # provably dead holder — positive death only; give up after 2 reclaims
    (( _ll_reclaims += 1 ))
    (( _ll_reclaims >= 2 )) && break
    printf '[lane-liveness] share slot had a provably dead in-flight holder (pid=%s) — reclaiming\n' \
      "$(cat "$_ll_flight/owner.pid" 2>/dev/null || printf '?')" >&2
    rm -f "$_ll_flight/owner.pid" "$_ll_flight/owner.birth" 2>/dev/null || true
    rmdir "$_ll_flight" 2>/dev/null || true
    continue
  fi
  # live holder for THIS subject: wait for its verdict (that is the share),
  # its exit, or its death — whichever comes first
  _ll_deadline=$(( $(date +%s) + _ll_wait ))
  while (( $(date +%s) < _ll_deadline )); do
    if _ll_fresh "$_ll_slot"; then
      _ll_emit_cached "$_ll_slot" || true
      break 2
    fi
    [[ -d "$_ll_flight" ]] || break
    _ll_inflight_owner_alive "$_ll_flight" || break
    sleep 0.3
  done
  break
done
# wait timed out / reclaim race lost / cached emit refused: never block a
# verdict — run the probe directly, unshared
[[ -z "${LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE:-}" ]] || \
  printf 'probe pid=%s %s (unshared)\n' "$$" "$(date +%s)" >>"$LEADV2_LANE_LIVENESS_PROBE_COUNT_FILE" 2>/dev/null || true
_ll_run_probe
exit $?
