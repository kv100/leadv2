#!/usr/bin/env bash
# leadv2-fanout-lane-launcher.sh — detached per-lane launcher for the
# FANOUT-CLASS-FUNNEL-01 single-worker path (Light/Standard tasks).
#
# P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01: leadv2-fanout.sh used to run
# leadv2-dispatch-code.sh (architect prepass + worker spawn, up to
# ARCHITECT_PREPASS_TIMEOUT_SEC x ARCHITECT_PREPASS_ATTEMPTS = 840s)
# Kimi adds a 60s caller-side verdict window after spawn (overrideable).
# SYNCHRONOUSLY in its own foreground, strictly sequentially per lane. A
# caller (e.g. the harness Bash tool's 600s ceiling) that reaps fanout's
# process GROUP takes every already-spawned lane down with it, and any lane
# the sequential loop never reached is silently dropped. This script is
# spawned by fanout's _fanout_launch_lane_detached, via _leadv2_new_session_exec,
# into its OWN OS session — so it survives fanout's exit and a group-directed
# signal aimed at fanout never reaches it. It owns the whole synchronous
# call from here on: run dispatch-code.sh, finalize the active.yaml row with
# the real worker pid, and — via its EXIT trap — guarantee a terminal record
# for this lane if it dies before a worker exists.
#
# Usage:
#   leadv2-fanout-lane-launcher.sh --task-id <tid> --class <cls>
#     --mission-file <path> --project-root <path> --sig-dir <path>
#     --dispatch-bin <path>
#     [--writes <csv>] [--acceptance-cmd <cmd>] [--rollback-onestep]
#     [--lead-model <m>] [--lead-effort <e>] [--risk-tags <csv>]
#     [--class-reason <s>] [--provider <p>] [--route-reason <s>]
#     [--group-key <k>]
#
# Mission text is passed via --mission-file, never argv — the funnel
# mission can be multi-KB and a "Task <tid>: <mission>" positional on a
# command line is an E2BIG / quoting hazard once it is itself an argv
# element of this script's own invocation (fanout spawns this script with
# a dozen other flags already on the line).
#
# Exit codes: 0 worker spawned. 2 refused (terminal row written). 3 parked
# (fell back to full-cycle... not applicable here, dispatch-code.sh's arm=
# opus case releases the claim; the founder-picked task is not re-launched
# by this script — see the rc==3 case below). 1 dead / launch failure.

set -uo pipefail  # NOT -e: every branch must still reach the EXIT trap below

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf -- '[fanout-lane] %s\n' "$*" >&2; }
log_error() { log "ERROR: $*"; }

TASK_ID="" CLS="" MISSION_FILE="" PROJECT_ROOT="" SIG_DIR="" DISPATCH_BIN=""
LANE_WRITES="" LANE_ACCEPTANCE="" LANE_ROLLBACK="0"
LEAD_MODEL="sonnet" LEAD_EFFORT="medium" RISK_TAGS="" CLASS_REASON=""
PROVIDER="claude" ROUTE_REASON="" GROUP_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)          TASK_ID="$2";       shift 2 ;;
    --class)            CLS="$2";           shift 2 ;;
    --mission-file)     MISSION_FILE="$2";  shift 2 ;;
    --project-root)     PROJECT_ROOT="$2";  shift 2 ;;
    --sig-dir)          SIG_DIR="$2";       shift 2 ;;
    --dispatch-bin)     DISPATCH_BIN="$2";  shift 2 ;;
    --writes)           LANE_WRITES="$2";   shift 2 ;;
    --acceptance-cmd)   LANE_ACCEPTANCE="$2"; shift 2 ;;
    --rollback-onestep) LANE_ROLLBACK="1";  shift ;;
    --lead-model)       LEAD_MODEL="$2";    shift 2 ;;
    --lead-effort)      LEAD_EFFORT="$2";   shift 2 ;;
    --risk-tags)        RISK_TAGS="$2";     shift 2 ;;
    --class-reason)     CLASS_REASON="$2";  shift 2 ;;
    --provider)         PROVIDER="$2";      shift 2 ;;
    --route-reason)     ROUTE_REASON="$2";  shift 2 ;;
    --group-key)        GROUP_KEY="$2";     shift 2 ;;
    *) log_error "unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$TASK_ID" || -z "$MISSION_FILE" || -z "$PROJECT_ROOT" || -z "$SIG_DIR" || -z "$DISPATCH_BIN" ]]; then
  log_error "missing required arg (--task-id/--mission-file/--project-root/--sig-dir/--dispatch-bin)"
  exit 1
fi

export PROJECT_ROOT="$PROJECT_ROOT"
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

# LEAD-CONTROL-PLANE-01 + CORE-OFFLINE-WORKTREE-GAP-01 (H5,
# MERGED-BATCH-FIXROUND-01): the resolution INVARIANT is that the chosen
# copy routes active.yaml through scripts/leadv2-state-path.sh (control-plane
# state root) — a copy that predates that still hardcodes
# docs/leadv2/active.yaml and must be SKIPPED, wherever it sits in the chain.
# Sibling-first is an AVAILABILITY ordering, not the invariant: SCRIPT_DIR is
# the only root always correct for the script actually executing (a lane
# worktree has no vendored .claude/scripts/, a fixture $HOME has no shared
# tree), but sibling-first only wins when the sibling also carries the
# property.
_lv2_registry_ok() {
  [[ -s "$1" ]] && grep -q 'leadv2-state-path.sh' "$1"
}
_REGISTRY_SH="${SCRIPT_DIR}/leadv2-active-registry.sh"
_lv2_registry_ok "$_REGISTRY_SH" || _REGISTRY_SH="${PROJECT_ROOT}/.claude/scripts/leadv2-active-registry.sh"
_lv2_registry_ok "$_REGISTRY_SH" || _REGISTRY_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/leadv2-active-registry.sh"
_lv2_registry_ok "$_REGISTRY_SH" || _REGISTRY_SH="${HOME}/.claude/leadv2-shared/scripts/leadv2-active-registry.sh"
if ! _lv2_registry_ok "$_REGISTRY_SH"; then
  log_error "leadv2-active-registry.sh not found, or every copy found (sibling/vendored/canonical/shared) predates the control-plane state-path resolution — refusing to launch"
  exit 1
fi
# shellcheck source=/dev/null
source "$_REGISTRY_SH"
# shellcheck source=leadv2-tasks-lib.sh
source "${SCRIPT_DIR}/leadv2-tasks-lib.sh"

mkdir -p "$SIG_DIR"
PID_FILE="${SIG_DIR}/launcher.pid"

_TERMINAL_WRITTEN=0
_WORKER_SPAWNED=0

# _fanout_write_lane_terminal <landed|parked|refused|dead> <cause> [<evidence>]
# Local copy of leadv2-fanout.sh's helper of the same name (same ledger
# contract: key on "fanout-<tid>" when there is no dispatch-code.sh sig8
# yet). Duplicated rather than sourced from fanout.sh -- fanout.sh is a
# top-level script (arg-parsing + a launch loop run at source time), not a
# library; extracting shared helpers into a third file is out of this
# task's scope (leadv2-fanout.sh only).
_fanout_write_lane_terminal() {
  local terminal="$1" cause="$2" evidence="${3:-}"
  [[ "$_TERMINAL_WRITTEN" == "1" ]] && return 0
  local ledger_bin="${LEADV2_FANOUT_DISPATCH_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-dispatch-ledger.sh}"
  if [[ -x "$ledger_bin" ]]; then
    bash "$ledger_bin" write-terminal "fanout-${TASK_ID}" "$TASK_ID" "$terminal" "$cause" "$evidence" "" \
      >/dev/null 2>&1 || log_error "write-terminal failed for task=${TASK_ID} terminal=${terminal} cause=${cause}"
  else
    log_error "dispatch ledger missing/not executable at ${ledger_bin} -- cannot record terminal for task=${TASK_ID} cause=${cause}"
  fi
  _TERMINAL_WRITTEN=1
}

# _fanout_register_session — VERBATIM copy of leadv2-fanout.sh's function of
# the same name (same lockfile via _leadv2_yaml_file/_leadv2_yaml_lockfile,
# sourced from the same leadv2-active-registry.sh above), so registrations
# from this launcher and from fanout itself serialize correctly against the
# SAME active.yaml under the SAME flock. See leadv2-fanout.sh's own copy for
# the full history of the admission-race fixes embedded below; keep the two
# copies in sync if either changes.
_fanout_register_session() {
  local tid="$1" cls="$2" pid_val="$3" window_title="$4" daemon_mode="$5"
  local pid_pending="${6:-false}"
  local where="${7:-terminal}"
  local risk_tags="${8:-}"
  local lead_model="${9:-}"
  local lead_effort="${10:-}"
  local class_reason="${11:-}"
  local provider="${12:-claude}"
  local route_reason="${13:-}"
  local group_key="${14:-}"
  local log_path_override="${15:-}"
  local branch ts_now yaml_file lockfile session_id pulse_log_path
  branch="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf -- 'unknown')"
  ts_now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  session_id="f-$(date -u +%Y%m%dT%H%M%SZ)-${pid_val}-$$"
  pulse_log_path="${log_path_override:-docs/leadv2/tasks/${tid}/pulse.md}"

  local _reg_rc=0
  python3 - "$lockfile" "$yaml_file" "$session_id" "$tid" "$PROJECT_ROOT" \
    "$branch" "$ts_now" "$cls" "$pid_val" "$window_title" "$daemon_mode" \
    "$pulse_log_path" "$pid_pending" "$where" \
    "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" \
    "$provider" "$route_reason" "$group_key" <<'PYEOF' || _reg_rc=$?
import sys, os, fcntl, tempfile, yaml

(lockfile, yaml_path, session_id, task_id, worktree, branch, started_at,
 cls, pid_str, window_title, daemon_mode_str, pulse_log, pid_pending_str,
 where, risk_tags, lead_model, lead_effort, class_reason,
 provider, route_reason, group_key) = sys.argv[1:22]

pid_val = None if pid_str in ("null", "", "None") else int(pid_str)
daemon_mode = daemon_mode_str.lower() in ("1", "true", "yes")
pid_pending = pid_pending_str.lower() in ("1", "true", "yes")

def pid_alive(p):
    try:
        os.kill(int(p), 0); return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

PROD_RISK_TAGS = {"publish", "deploy", "migration", "prod", "prod-deploy"}

def _norm_tags_reg(raw):
    if isinstance(raw, (list, tuple, set)):
        parts = [str(x).strip().lower() for x in raw if str(x).strip()]
    elif isinstance(raw, str):
        s = raw.strip()
        if not s or s.lower() in ("-", "none", "null"):
            return None
        parts = [p.strip().lower() for p in s.split(",") if p.strip()]
    else:
        return None
    return set(parts) if parts else None

def _group_key_unknown_reg(gk):
    if gk is None:
        return True
    s = str(gk).strip().lower()
    return s in ("", "-", "none", "null")

def _hard_collision(cand_gk, cand_tags, other_gk, other_tags):
    cand_tags_set = _norm_tags_reg(cand_tags)
    other_tags_set = _norm_tags_reg(other_tags)
    if cand_tags_set is None or other_tags_set is None:
        return True
    if _group_key_unknown_reg(cand_gk) or _group_key_unknown_reg(other_gk):
        return True
    return bool(cand_tags_set & PROD_RISK_TAGS) and bool(other_tags_set & PROD_RISK_TAGS)

os.makedirs(os.path.dirname(lockfile), exist_ok=True)
fd = open(lockfile, "a+")
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    os.makedirs(os.path.dirname(yaml_path), exist_ok=True)
    if os.path.exists(yaml_path):
        with open(yaml_path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    else:
        data = {"meta": {"schema_version": 2, "hard_limit": 2,
                          "heavy_max": 2, "heavy_strategic_solo": False,
                          "light_max": 3, "standard_max": 2, "rendered_at": ""},
                "sessions": []}
    data.setdefault("meta", {})
    sessions = data.setdefault("sessions", [])

    existing = next((s for s in sessions if s.get("task_id") == task_id), None)
    if existing and pid_alive(existing.get("pid")):
        print(f"[fanout] {task_id} already has a live registered session — not overwriting", file=sys.stderr)
        sys.exit(0)
    if existing:
        sessions.remove(existing)

    meta_live = data.get("meta") or {}
    heavy_max_live = int(meta_live.get("heavy_max", 2))
    hard_limit_live = int(meta_live.get("hard_limit", 2))
    live_sessions = [s for s in sessions if not s.get("stale")]
    live_heavy = sum(1 for s in live_sessions if str(s.get("class", "")).lower() in ("heavy", "strategic"))
    if cls.lower() in ("heavy", "strategic") and live_heavy >= heavy_max_live:
        print(f"[fanout] LOST_RACE: {task_id} would exceed heavy_max under lock ({live_heavy}/{heavy_max_live}) -- refusing to register", file=sys.stderr)
        sys.exit(3)
    if len(live_sessions) >= hard_limit_live:
        print(f"[fanout] LOST_RACE: {task_id} would exceed hard_limit under lock ({len(live_sessions)}/{hard_limit_live}) -- refusing to register", file=sys.stderr)
        sys.exit(3)

    if cls.lower() in ("heavy", "strategic"):
        for s in live_sessions:
            if str(s.get("class", "")).lower() not in ("heavy", "strategic"):
                continue
            if _hard_collision(group_key, risk_tags, s.get("group_key"), s.get("risk_tags")):
                print(f"[fanout] LOST_RACE: {task_id} HARD-collides under lock with live session task_id={s.get('task_id')} (prod/unknown footprint) -- refusing to register", file=sys.stderr)
                sys.exit(3)

    group_key_norm = None if group_key in ("", "null", "None", "-") else group_key

    sessions.append({
        "session_id": session_id, "task_id": task_id, "worktree": worktree,
        "branch": branch, "started_at": started_at, "phase": "spawning",
        "class": cls, "pulse_log": pulse_log, "pid": pid_val,
        "pid_birth": None, "parent_session_id": None,
        "daemon_mode": daemon_mode, "last_pulse_at": started_at,
        "stale": False, "window_title": window_title, "pid_pending": pid_pending,
        "where": where,
        "note": f"window_title={window_title}",
        "risk_tags": risk_tags,
        "group_key": group_key_norm,
        "lead_model": lead_model,
        "lead_effort": lead_effort,
        "class_reason": class_reason,
        "provider": provider,
        "route_reason": route_reason,
        "protocol_version": 2,
        "backend": where,
        "phase_started_at": started_at,
        "updated_at": started_at,
        "tmux_window": window_title if where == "tmux" else None,
        "tmux_pane": None,
        "log_path": pulse_log,
        "provider_receipts": [{
            "provider": provider,
            "task_id": task_id,
            "model": lead_model,
            "effort": lead_effort,
            "run_id": session_id,
            "status": "launched",
            "exit_code": None,
            "attempt": 0,
            "recorded_at": started_at,
        }],
    })

    d = os.path.dirname(yaml_path)
    tfd, tpath = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(tfd, "w", encoding="utf-8") as tf:
            yaml.dump(data, tf, default_flow_style=False, sort_keys=False)
        os.replace(tpath, yaml_path)
    except Exception:
        os.unlink(tpath)
        raise
finally:
    fcntl.flock(fd, fcntl.LOCK_UN)
    fd.close()
PYEOF
  if [[ "$_reg_rc" -eq 3 ]]; then
    log "WARN: ${tid} lost the register-time admission race under lock (F6/FIX3) — refusing to register; caller must terminate the spawned child"
  elif [[ "$_reg_rc" -ne 0 ]]; then
    log "WARN: could not register ${tid} in active.yaml — session is running unregistered"
  fi
  return "$_reg_rc"
}

# EXIT trap (design §2 step 7 / mission req #3): if this launcher is exiting
# without having spawned a worker AND without a terminal already recorded,
# that would otherwise leave the lane silently dangling exactly like the
# original bug -- write the terminal, release the claim + reservation. Also
# take our own process GROUP down with us (R7) so a killed launcher never
# leaves its architect-prepass child burning tokens for nobody.
_cleanup_on_death() {
  if [[ "$_WORKER_SPAWNED" != "1" && "$_TERMINAL_WRITTEN" != "1" ]]; then
    log_error "exiting without a spawned worker and without a recorded terminal -- writing dead cause=launcher_died_before_spawn"
    _fanout_write_lane_terminal dead "launcher_died_before_spawn" "${SIG_DIR}/launcher.log"
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_FILE" 2>/dev/null || true
}
trap _cleanup_on_death EXIT
# R7: an external kill (fanout's ack-timeout branch in
# _fanout_launch_lane_detached, or any other signal) means an in-flight
# dispatch-code.sh/architect-prepass child may still be running underneath
# us -- take the whole process GROUP down so that child is never orphaned
# burning tokens for nobody (mission evidence: lane 3's opus prepass
# survived, reparented to launchd, after being killed this way). Scoped to
# TERM/INT only, NOT folded into the plain EXIT trap above: by the time this
# script reaches a normal exit (0/1/2/3), dispatch-code.sh's own synchronous
# call has already returned and any legitimately-spawned worker must
# survive -- group-killing unconditionally on every exit would kill that
# worker too (it inherits our group, same root cause as the bug this script
# exists to fix) and self-signaling our own group from inside a plain EXIT
# trap risks colliding with bash's own trap re-entrancy.
trap '_cleanup_on_death; kill -TERM -- "-$$" 2>/dev/null; exit 143' TERM
trap '_cleanup_on_death; kill -TERM -- "-$$" 2>/dev/null; exit 130' INT

# ── Handoff ack: stamp our own pid so fanout's short wait can confirm we're
# alive, and re-register the row with pid=$$/pid_pending=true so liveness is
# real during the (possibly minutes-long) prepass window instead of the
# null-pid placeholder fanout wrote before spawning us. ──────────────────────
_pid_tmp="${PID_FILE}.tmp.$$"
printf '%s\n' "$$" > "$_pid_tmp" && mv -f "$_pid_tmp" "$PID_FILE"

_reg_rc=0
_fanout_register_session "$TASK_ID" "$CLS" "$$" "dispatch-code: ${TASK_ID} (launcher)" "true" "true" "dispatch-code" \
  "$RISK_TAGS" "$LEAD_MODEL" "$LEAD_EFFORT" "$CLASS_REASON" "$PROVIDER" "$ROUTE_REASON" "$GROUP_KEY" || _reg_rc=$?
if [[ "$_reg_rc" -eq 3 ]]; then
  log "WARN: ${TASK_ID} admission refused re-registering the launcher's own pid (F6/FIX3) -- continuing anyway (R4: today's synchronous path already WARNs and proceeds here, this is not a new regression)"
elif [[ "$_reg_rc" -ne 0 ]]; then
  log "WARN: ${TASK_ID} could not re-register launcher pid in active.yaml -- continuing, liveness may lag"
fi

MISSION="$(cat "$MISSION_FILE" 2>/dev/null || true)"
if [[ -z "$MISSION" ]]; then
  log_error "mission file ${MISSION_FILE} missing/empty -- refusing to dispatch"
  _fanout_write_lane_terminal dead "mission_file_missing_or_empty" "$MISSION_FILE"
  leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
  leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
  exit 1
fi

# ── Run dispatch-code.sh SYNCHRONOUSLY -- this is the (up to 840s) call that
# used to block fanout's own foreground. Kimi adds a 60s caller-side verdict
# window after spawn (overrideable). We are in our own session now, so
# there is no caller deadline to race. ───────────────────────────────────────
# P0-WORK-CANNOT-LAND-UNSCOPABLE-DIFF-01 (M2 -- LANE-WORKTREE-ISOLATION-01 for product
# lanes): the three lead-session launch paths in fanout.sh already `ensure` a worktree
# before dispatch (see launch_headless/launch_windowed/launch_tmux); THIS path (the
# detached per-lane launcher) never did, so every product lane's edits landed in the
# shared tree with no scoping. `ensure` is fail-open by construction (falls back to
# PROJECT_ROOT on any git failure), so a worktree failure here degrades to today's
# shared-tree behavior rather than killing the lane. LEADV2_PROJECT_ROOT is already
# exported above -- pinned to the ORIGINAL shared root so control-plane files
# (active.yaml, docs/handoff, bus.jsonl) still resolve there regardless of which
# worktree the child's code edits land in.
_lane_dir="$("${SCRIPT_DIR}/leadv2-lane-worktree.sh" ensure "$TASK_ID" "$CLS")"
[[ -n "$_lane_dir" && -d "$_lane_dir" ]] || _lane_dir="$PROJECT_ROOT"
# LANDING-BLOCKER-R2 (C1): make the worker's actual cwd an explicit, propagated value
# instead of relying on dispatch-code.sh inheriting our `cd` below -- glm/codex pass
# --cwd explicitly and were reading PROJECT_ROOT (shared root), not this worktree.
export LEADV2_LANE_WORK_ROOT="$_lane_dir"

declare -a dc_args=("$MISSION" --kind "fanout-class-funnel" --task-id "$TASK_ID")
[[ -n "$LANE_WRITES" ]] && dc_args+=(--writes "$LANE_WRITES")
[[ -n "$LANE_ACCEPTANCE" ]] && dc_args+=(--acceptance-cmd "$LANE_ACCEPTANCE")
[[ "$LANE_ROLLBACK" == "1" ]] && dc_args+=(--rollback-onestep)

dc_out="$(cd "$_lane_dir" && bash "$DISPATCH_BIN" "${dc_args[@]}" 2>&1)"; dc_rc=$?

# ── Case block moved VERBATIM from leadv2-fanout.sh's launch_via_dispatch_code
# (the synchronous tail, rc==0/2/3/*) -- same log lines, same field
# extraction, same active.yaml finalize call, same claim-release semantics.
# The ONLY behavior change from the original: rc==3 (opus arm) and the
# default (dispatch-code.sh failure) branches used to fall back to
# _fanout_launch_full_cycle from inside fanout itself; that function lives in
# fanout.sh and is out of reach from a detached, separately-spawned script.
# Falling back is therefore NOT attempted here -- the claim and reservation
# are released and a `refused`/`dead` terminal is written instead, so the
# task returns to `pending` and is picked up by the next fanout/backlog-pump
# run rather than being silently dropped. See developer.full.md for why this
# is judged an acceptable, non-silent narrowing of scope.
# M10 (LANDING-BLOCKER-R2): a worktree is created per lane per dispatch (M2) and
# leadv2-lane-worktree.sh has no prune of its own -- reap it here on the three terminal
# outcomes below that produced no landable work, via the existing Phase-8 reaper
# (leadv2-lane-worktree.sh:35, leadv2-worktree-cleanup.sh --name <id>). Never on `landed`
# (the work must survive for merge). Requires BOTH a clean tree AND zero commits ahead of
# upstream -- a dirty or ahead worktree is left alone and is the operator's to reap; never
# `git clean`/`reset` here. `|| true` throughout: reaping is best-effort and must never
# fail this launcher's own exit path.
_reap_lane_worktree_if_unused() {
  [[ -n "$_lane_dir" && "$_lane_dir" != "$PROJECT_ROOT" ]] || return 0
  [[ -z "$(git -C "$_lane_dir" status --porcelain 2>/dev/null)" ]] || return 0
  local _upstream _ahead
  _upstream="$(git -C "$_lane_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || printf 'main')"
  _ahead="$(git -C "$_lane_dir" rev-list --count "${_upstream}.." 2>/dev/null || printf '0')"
  [[ "$_ahead" == "0" ]] || return 0
  bash "${SCRIPT_DIR}/leadv2-worktree-cleanup.sh" --name "$TASK_ID" >/dev/null 2>&1 || true
}

case "$dc_rc" in
  0)
    handle="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .*handle=\(.*\)$/\1/p' | tail -1)"
    log "single-worker funnel launch: task=${TASK_ID} class=${CLS} model=${LEAD_MODEL} handle=${handle:-<none>} -- $(printf '%s\n' "$dc_out" | tail -1)"

    pid_val="null"
    extracted_pid="$(printf '%s' "$handle" | sed -n 's/^PID=\([0-9][0-9]*\).*/\1/p')"
    [[ -n "$extracted_pid" ]] && pid_val="$extracted_pid"

    dc_sig8="$(printf '%s\n' "$dc_out" | sed -n 's/.*task=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)"
    dc_log_path=""
    [[ -n "$dc_sig8" ]] && dc_log_path="docs/handoff/dispatch-${dc_sig8}/developer.stream.jsonl"

    # _fanout_register_session's own "existing row still alive -> don't
    # overwrite" guard exists to protect a DIFFERENT concurrent session's
    # live row from being clobbered -- but the row it would see here is OUR
    # OWN interim stamp (pid=$$, this launcher, alive by definition while
    # we're the one calling this). Left alone, that guard silently no-ops
    # the finalize (rc=0, row never gets the real worker pid). Unregister
    # our own row first so the finalize call below always sees `existing =
    # None` and proceeds -- safe because leadv2_tasks_claim guarantees this
    # launcher is the sole owner of TASK_ID's registration.
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _reg_rc=0
    _fanout_register_session "$TASK_ID" "$CLS" "$pid_val" "dispatch-code: ${TASK_ID}" "true" "false" "dispatch-code" \
      "$RISK_TAGS" "$LEAD_MODEL" "$LEAD_EFFORT" "$CLASS_REASON" "$PROVIDER" "$ROUTE_REASON" "$GROUP_KEY" "$dc_log_path" || _reg_rc=$?
    if [[ "$_reg_rc" -eq 3 ]]; then
      log "WARN: ${TASK_ID} admission refused under lock while finalizing the single-worker funnel's registry row (F6/FIX3) -- dispatch-code.sh already spawned this worker; it cannot be killed generically from here (arm-specific handle=${handle:-<none>}), lane cap is now over-subscribed by one until it finishes"
    fi
    dc_attempt="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .*attempt=\([^[:space:]]*\).*/\1/p' | tail -1)"
    if [[ -n "$dc_attempt" ]]; then
      leadv2_active_set_attempt "$TASK_ID" "$dc_attempt" >/dev/null 2>&1 || true
    fi
    _WORKER_SPAWNED=1
    exit 0
    ;;
  2)
    log "single-worker funnel: task=${TASK_ID} refused by dispatch-code.sh as a duplicate task-signature -- releasing claim, not launched this run (see dispatch ledger)"
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal refused "duplicate_task_signature" ""
    _reap_lane_worktree_if_unused
    exit 2
    ;;
  3)
    log "single-worker funnel: task=${TASK_ID} resolved to arm=opus (requires lead judgment, dispatch-code.sh never auto-dispatches it) -- releasing claim; NOT falling back to full-cycle from a detached launcher (out of reach) -- recording parked so the founder-picked task returns to pending, not silently dropped"
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal parked "requires_opus_lead_judgment" ""
    _reap_lane_worktree_if_unused
    exit 3
    ;;
  6)
    # BURN-GOVERNOR-01 (architect prepass §1.3 D3): dispatch-code.sh's own burn gate
    # already refused this lane before any worker/worktree/ledger row existed -- this
    # is a deliberate park, NOT a failure, so it must NEVER be recorded `dead` (that
    # feeds the dead-lane alarm and retry-dead machinery for a lane that never ran).
    log "single-worker funnel: task=${TASK_ID} refused by dispatch-code.sh's burn gate (24h local token burn over hard cap) -- releasing claim, task parked to burn-deferred.jsonl, returns to pending (see leadv2-dispatch-code.sh burn-deferred --list)"
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal parked "burn_hard_24h" ""
    _reap_lane_worktree_if_unused
    exit 3
    ;;
  *)
    log_error "single-worker funnel: task=${TASK_ID} dispatch-code.sh failed (rc=${dc_rc}) -- releasing claim; NOT falling back to full-cycle from a detached launcher (out of reach) -- recording dead so the founder-picked task returns to pending, not silently dropped"
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal dead "dispatch_code_failed_rc_${dc_rc}" "$(printf '%s' "$dc_out" | tail -20)"
    _reap_lane_worktree_if_unused
    exit 1
    ;;
esac
