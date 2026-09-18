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

# _fanout_register_session moved to leadv2-active-registry.sh as
# leadv2_fanout_register_session (D1-SINGLE-WRITER-FOR-LANE-STATE). This
# file's copy had drifted from fanout's: it predated the log_path_override
# (15th) and writeset (16th/17th) args, so the 15-arg call below was
# silently dropping $dc_log_path, and ran heavy_max default 2 vs fanout's 3.
# One body in the registry = one behavior; call sites unchanged via alias.

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

# No --kind here: "fanout-class-funnel" is a launch-mechanism label, not a work
# kind, and dispatch-code's strict argv validation (14fa47bf, 2026-09-15) refuses
# any kind outside product|plugin|tooling|... -- every funnel launch died at
# argv parse with rc=1 before reaching the worker spawn (LANE-WRITES-C1-
# LAUNCHER-CWD-SUBJECT-TRACE-01). An absent kind is dispatch-code's documented
# conservative default ("an absent/unknown kind is PRODUCT, never fast-path",
# leadv2-dispatch-code.sh PRODUCT-READINESS-GATES-01 header) and is what the
# launch registry coerced the unmapped label to anyway (normalize_kind -> code).
declare -a dc_args=("$MISSION" --task-id "$TASK_ID")
dc_args+=(--task-class "$CLS")
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
    # DISPATCH-AMBIGUOUS-ROW-RELEASE-01: dispatch-code.sh flags the rc=5/unknown
    # spawn-state shapes (spawn_worker positively verified a live worker but the
    # confirm/ledger write failed) with a stdout marker and deliberately leaves
    # the lane's active.yaml row for the stale-sweeper. Bare-unregistering our
    # own row here used to delete exactly that row, so the task was re-claimed
    # and re-dispatched onto a possibly-live worker (two live workers on one
    # lane). On the marker: release the claim only, park (never `dead` -- the
    # worker may be live), and leave BOTH the row and the lane worktree alone
    # (the worker may still be writing it). The parked terminal is also what
    # sets _TERMINAL_WRITTEN so our own EXIT trap cannot release the row
    # either. No marker -> the genuine "dispatch-code.sh never even ran"
    # crash case keeps today's unconditional cleanup below, unchanged.
    if printf '%s\n' "$dc_out" | grep -q '^dispatch_ambiguous_live_worker=1$'; then
      log "single-worker funnel: task=${TASK_ID} dispatch-code.sh rc=${dc_rc} flagged dispatch_ambiguous_live_worker=1 (a worker may be live but unrecorded) -- releasing claim only; the active.yaml row stays for the stale-sweeper, worktree left untouched, task returns to pending"
      leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
      _fanout_write_lane_terminal parked "dispatch_code_ambiguous_live_worker" "$(printf '%s' "$dc_out" | tail -20)"
      exit 1
    fi
    log_error "single-worker funnel: task=${TASK_ID} dispatch-code.sh failed (rc=${dc_rc}) -- releasing claim; NOT falling back to full-cycle from a detached launcher (out of reach) -- recording dead so the founder-picked task returns to pending, not silently dropped"
    leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    leadv2_active_unregister "$TASK_ID" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal dead "dispatch_code_failed_rc_${dc_rc}" "$(printf '%s' "$dc_out" | tail -20)"
    _reap_lane_worktree_if_unused
    exit 1
    ;;
esac
