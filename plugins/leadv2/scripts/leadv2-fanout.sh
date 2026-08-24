#!/usr/bin/env bash
# leadv2-fanout.sh — dispatch N independent /leadv2 sessions, each in its own
# tmux window, terminal window (macOS osascript), or headless background
# process, each in its own git worktree (worktree isolation is handled by
# Phase 0 of the spawned /leadv2 session itself — this script only SELECTS
# tasks and LAUNCHES sessions; it never creates worktrees).
#
# Backend selection (LEAD-ANCHOR-01 tmux launch backend, 2026-07-14):
#   --tmux      force tmux backend: one shared tmux session named "leadv2",
#               one WINDOW per task (named after the task id). Reuses the
#               existing "leadv2" session if present instead of creating a
#               second one. Survives Terminal.app window close/quit — this is
#               why it exists: an accidental Terminal.app window close used to
#               kill a live /leadv2 session outright.
#   --windows   force the old Terminal.app/iTerm2 osascript backend.
#   --headless  background nohup/setsid process, no terminal at all.
#   (none)      DEFAULT on macOS: tmux if `tmux` is on PATH, else --windows
#               with a warning on stderr. Non-macOS default: --windows (errors
#               asking for --headless, unchanged prior behavior).
#
# Usage:
#   leadv2-fanout.sh [--n N] [--filter STR] [--tasks ID1,ID2,ID3]
#                     [--provider auto|claude|codex]
#                     [--dry-run] [--tmux|--windows|--headless]
#
# Task LEAD-FANOUT-01. See docs/handoff/LEAD-ANCHOR-01/mission-fanout.md.
#
# Env overrides (test hook):
#   LEADV2_PROJECT_ROOT / CLAUDE_PROJECT_DIR / PROJECT_ROOT — repo root
#   LEADV2_FANOUT_CLAUDE_BIN — override the `claude` binary (tests stub this)
#   LEADV2_FANOUT_TMUX_SESSION — override the tmux session name (default
#     "leadv2"). Tests use this to avoid ever touching a real "leadv2"
#     session; never override this for a real launch.
#
# Exit codes: 0 = ran (dry-run or real). 1 = hard failure (broken active.yaml,
# unsupported platform, bad args). Fail-CLOSED: any doubt about session
# accounting refuses to launch rather than risk two leads in one worktree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}}"

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
  printf -- '[fanout] ERROR: leadv2-active-registry.sh not found, or every copy found (sibling/vendored/canonical/shared) predates the control-plane state-path resolution — refusing to launch\n' >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$_REGISTRY_SH"

log() { printf -- '[fanout] %s\n' "$*" >&2; }
log_error() { log "ERROR: $*"; }

# DRIFT-GUARD PREFLIGHT (PLUGIN-CACHE-THIRD-COPY-REVERTS-FIXES-01): refuse to
# fan out onto scripts that may be silently stale in this copy. Fanout is the
# highest-blast-radius launcher of the 5 copies (it dispatches N independent
# sessions using this repo's vendored .claude/scripts/) — exactly the surface
# that silently ran on 4 reverted fixes for an hour undetected. Set
# LEADV2_SKIP_DRIFT_GUARD=1 to bypass (tests / intentional single-copy work).
#
# C1 fix (review-1.md, fix1): a hard `exit 1` here blocked ALL fanout dispatch
# the moment known, off-limits-protected SUPERVISE-V2-01 WIP drift existed in
# the LOWEST-blast-radius copy (leadv2-repo-vendored, i.e.
# ~/Projects/leadv2/.claude/scripts/ — a copy fanout itself does not read
# scripts from). We now inspect --json output: if EVERY drifted entry belongs
# to that one copy, WARN and proceed; any drift in a copy fanout actually
# reads from (cache/shared/vendored[repo]) still hard-blocks.
_DRIFT_GUARD="${SCRIPT_DIR}/leadv2-drift-guard.sh"
if [[ "${LEADV2_SKIP_DRIFT_GUARD:-0}" != "1" ]] && [[ -f "${_DRIFT_GUARD}" ]]; then
  _drift_json=""
  _drift_rc=0
  _drift_json="$(bash "${_DRIFT_GUARD}" --quiet --json)" || _drift_rc=$?
  if [[ "${_drift_rc}" -ne 0 ]]; then
    _only_vendored_drift=0
    _CLASSIFY="${SCRIPT_DIR}/leadv2-drift-only-vendored-check.py"
    if [[ -f "${_CLASSIFY}" ]] && command -v python3 >/dev/null 2>&1; then
      _only_vendored_drift="$(python3 "${_CLASSIFY}" "${_drift_json}")"
    fi
    if [[ "${_only_vendored_drift}" == "1" ]]; then
      log "WARN: drift detected but confined to the leadv2-repo-vendored copy (known SUPERVISE-V2-01 WIP, off-limits-protected, lowest blast radius — fanout does not read scripts from this copy) — proceeding with dispatch. Run 'bash ${_DRIFT_GUARD}' for details."
    else
      # Direction-aware remedy (DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01 residual
      # gap 1): the old text said unconditionally "sync from canonical", which
      # on a day canonical is the STALE side would overwrite today's work with
      # week-old code. The remedy is now: read the per-entry direction tags
      # first, promote VENDORED_NEWER copies INTO canonical before any sync,
      # and only then reconcile (plugin-sync is dry-run by default; --write
      # applies, --allow-backward is a last-resort override, not the remedy).
      log_error "drift detected across the 5 leadv2 script copies — refusing to fan out on possibly-stale scripts. Run 'bash ${_DRIFT_GUARD}' and read each entry's direction tag (CANONICAL_NEWER / VENDORED_NEWER / UNKNOWN): for every VENDORED_NEWER entry, promote that copy INTO canonical FIRST (cp <copy> ~/Projects/leadv2/plugins/leadv2/scripts/<name> + commit in ~/Projects/leadv2), then reconcile with 'bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-plugin-sync.sh' (dry-run by default; add --write to apply; --allow-backward exists but is NOT the remedy). Last-resort bypass only: LEADV2_SKIP_DRIFT_GUARD=1."
      exit 1
    fi
  fi
fi

TASKS_YAML="${PROJECT_ROOT}/docs/tasks.yaml"
ACTIVE_YAML="$(_leadv2_yaml_file)"

# FANOUT-CLASS-FUNNEL-01 (task T-k, 2026-07-29): the founder-picked path
# (this script) always launched a full Phase-0..8 child session regardless of
# leadv2-fanout-classify.sh's class -- that class only ever picked
# provider/model. leadv2-dispatch-code.sh's single-worker funnel (architect
# prepass + e2e gate + cross-provider review) already exists for the auto-
# refill path (leadv2-backlog-pump.sh) but was unreachable from here. Light
# and Standard now route through dispatch-code.sh; Heavy/Strategic keep
# today's full-cycle launch unchanged. (fanout-classify.sh emits only
# Light|Standard|Heavy|Strategic -- "Trivial" from the founder's wording maps
# onto Light here, there is no separate Trivial class to check.)
# One-flag rollback: LEADV2_FANOUT_CLASS_FUNNEL=0 restores today's behavior
# byte-identical -- the new branch is fully guarded, nothing else changes.
#
# BLOCKING fix (review-verdict.md fanout.sh:106-108): the lib used to be
# sourced HERE, unconditionally, before this flag was ever consulted -- a
# missing/broken leadv2-tasks-lib.sh killed rollback mode (=0) too, even
# though =0 never calls anything from it. Lazy-load it (once) only from
# inside the funnel-enabled call path (_fanout_ensure_tasks_lib, called at
# the top of launch_via_dispatch_code) so =0 is truly byte-identical to the
# pre-funnel script regardless of this file's health.
FANOUT_CLASS_FUNNEL="${LEADV2_FANOUT_CLASS_FUNNEL:-1}"

# P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01: the funnel path above ran
# leadv2-dispatch-code.sh SYNCHRONOUSLY in this script's own foreground,
# strictly sequentially across LAUNCH_IDS -- up to ARCHITECT_PREPASS_TIMEOUT_SEC
# x ARCHITECT_PREPASS_ATTEMPTS (840s) per lane. Kimi adds a 60s caller-side
# verdict window after spawn (overrideable). On this machine (no `setsid`
# binary) nothing this script launches gets its own OS session, so when a
# caller (e.g. the harness Bash tool's 600s ceiling) reaps this script's
# process GROUP, every already-spawned lane -- prepass and worker alike --
# dies with it, and any lane the sequential loop never reached is silently
# dropped with no terminal record. LEADV2_FANOUT_LANE_DETACH=1 (default)
# hands each funnel lane to a detached, per-lane launcher
# (leadv2-fanout-lane-launcher.sh) in its own session and waits only for a
# short handoff ack; =0 restores today's synchronous byte-identical behavior.
LEADV2_FANOUT_LANE_DETACH="${LEADV2_FANOUT_LANE_DETACH:-1}"
LEADV2_FANOUT_LANE_ACK_TIMEOUT_SEC="${LEADV2_FANOUT_LANE_ACK_TIMEOUT_SEC:-15}"
_TASKS_LIB_LOADED=0
_fanout_ensure_tasks_lib() {
  [[ "$_TASKS_LIB_LOADED" == "1" ]] && return 0
  # shellcheck source=leadv2-tasks-lib.sh
  source "${SCRIPT_DIR}/leadv2-tasks-lib.sh"
  _TASKS_LIB_LOADED=1
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
N=3
FILTER=""
EXPLICIT_TASKS=""
DRY_RUN=false
HEADLESS=false
FORCE=false
TMUX_FLAG=false
WINDOWS_FLAG=false
LEAD_MODEL_OVERRIDE=""
PROVIDER_REQUEST="${LEADV2_SESSION_PROVIDER:-auto}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n)          N="$2";                  shift 2 ;;
    --filter)     FILTER="$2";             shift 2 ;;
    --tasks)      EXPLICIT_TASKS="$2";     shift 2 ;;
    --dry-run)    DRY_RUN=true;            shift   ;;
    --headless)   HEADLESS=true;           shift   ;;
    --tmux)       TMUX_FLAG=true;          shift   ;;
    --windows)    WINDOWS_FLAG=true;       shift   ;;
    --force)      FORCE=true;              shift   ;;
    --lead-model) LEAD_MODEL_OVERRIDE="$2"; shift 2 ;;
    --provider)   PROVIDER_REQUEST="$2";   shift 2 ;;
    -h|--help)
      printf -- 'Usage: leadv2-fanout.sh [--n N] [--filter STR] [--tasks ID1,ID2] [--provider auto|claude|codex|glm|kimi] [--dry-run] [--tmux|--windows|--headless] [--force] [--lead-model MODEL]\n'
      printf -- '  --tmux: one shared tmux session "leadv2", one window per task. Default\n'
      printf -- '          backend on macOS when tmux is on PATH.\n'
      printf -- '  --windows: force Terminal.app/iTerm2 osascript windows (old default).\n'
      printf -- '  --headless: background nohup process, no terminal/tmux at all.\n'
      printf -- '  --force: bypass active.yaml meta caps (hard_limit/standard_max/light_max/\n'
      printf -- '           heavy_strategic_solo). Never bypasses the same-task-already-active\n'
      printf -- '           check — that is the worktree-collision safety net, not a policy cap.\n'
      printf -- '  --lead-model MODEL: override the per-task classifier model for EVERY child\n'
      printf -- '           launched by this invocation (default: classifier picks sonnet for\n'
      printf -- '           Light/Standard, opus for Heavy/Strategic). Use `--lead-model opus`\n'
      printf -- '           when the founder explicitly wants an Opus child; never on by default.\n'
      printf -- '  --provider auto|claude|codex|glm|kimi: provider for COMPLETE Phase 0..8 child\n'
      printf -- '           sessions. auto routes routine work by live policy/quota; high-risk\n'
      printf -- '           classes/tags remain on Claude unless an explicit policy override exists.\n'
      exit 0
      ;;
    *) log_error "unknown arg: $1"; exit 1 ;;
  esac
done

case "$PROVIDER_REQUEST" in
  auto|claude|codex|glm|kimi) ;;
  *) log_error "--provider must be auto, claude, codex, glm, or kimi (got: $PROVIDER_REQUEST)"; exit 1 ;;
esac

if [[ -n "$LEAD_MODEL_OVERRIDE" ]]; then
  log "--lead-model override active: every launch this run uses model=${LEAD_MODEL_OVERRIDE} (classifier's per-task pick is ignored for model; effort is unaffected)"
  if [[ "$PROVIDER_REQUEST" == "auto" ]]; then
    case "$LEAD_MODEL_OVERRIDE" in
      gpt-*|codex-*) PROVIDER_REQUEST="codex" ;;
      *)            PROVIDER_REQUEST="claude" ;;
    esac
    log "--lead-model implies provider=${PROVIDER_REQUEST}; use --provider explicitly to override"
  fi
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  log_error "--n must be a non-negative integer, got '$N'"
  exit 1
fi

# F2 (fix-round-2, task 6d0c93f4a7b2 / D4): log the EFFECTIVE LEADV2_LEAD_GUARD
# value each child session will actually run under, and warn loudly when the
# ambient env this script sees disagrees with it. ~/.claude/settings.json arms
# LEADV2_LEAD_GUARD=1 as hook env for every session (including dispatched
# children) -- that always wins over whatever this shell has exported, so
# `export LEADV2_LEAD_GUARD=0` before calling fanout is silently ignored.
# LEADV2_LEAD_GUARD_FORCE is the one override that actually reaches the hook.
_log_effective_lead_guard() {
  local _settings="$HOME/.claude/settings.json"
  local _settings_val=""
  if [[ -f "$_settings" ]]; then
    _settings_val="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('env', {}).get('LEADV2_LEAD_GUARD', ''))
except Exception:
    print('')
" "$_settings" 2>/dev/null || true)"
  fi
  local _ambient="${LEADV2_LEAD_GUARD:-}"
  local _force="${LEADV2_LEAD_GUARD_FORCE:-}"
  local _effective="${_settings_val:-${_ambient:-0}}"
  if [[ -n "$_force" ]]; then
    log "LEADV2_LEAD_GUARD effective=${_force} (LEADV2_LEAD_GUARD_FORCE=${_force} overrides everything below)"
  else
    log "LEADV2_LEAD_GUARD effective=${_effective} (settings.json env=${_settings_val:-<unset>}, ambient shell=${_ambient:-<unset>})"
    if [[ -n "$_ambient" && -n "$_settings_val" && "$_ambient" != "$_settings_val" ]]; then
      log "WARN: ambient LEADV2_LEAD_GUARD=${_ambient} disagrees with settings.json's ${_settings_val} -- settings.json wins for every dispatched child, your export is silently ignored. Use 'export LEADV2_LEAD_GUARD_FORCE=${_ambient}' to actually force it."
    fi
  fi
}
_log_effective_lead_guard

# ── Backend resolution ──────────────────────────────────────────────────────
# Precedence: --headless > --tmux > --windows > platform default. Platform
# default (no flag given) is tmux on macOS when tmux is on PATH, else
# windowed with a stderr warning (fail-soft, never fail-closed on backend
# choice — worktree-collision safety net above is the only fail-closed gate).
if [[ "$HEADLESS" == "true" ]]; then
  BACKEND="headless"
elif [[ "$TMUX_FLAG" == "true" ]]; then
  BACKEND="tmux"
elif [[ "$WINDOWS_FLAG" == "true" ]]; then
  BACKEND="windows"
elif [[ "$(uname -s)" == "Darwin" ]] && command -v tmux >/dev/null 2>&1; then
  BACKEND="tmux"
else
  BACKEND="windows"
fi

if [[ "$BACKEND" == "tmux" ]] && ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux requested/defaulted but not found on PATH — falling back to --windows"
  BACKEND="windows"
fi

# ── Fail-CLOSED: active.yaml must exist and parse cleanly ─────────────────
if [[ ! -f "$ACTIVE_YAML" ]]; then
  log_error "active.yaml not found at $ACTIVE_YAML — refusing to fan out (fail-closed)"
  exit 1
fi
if ! python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$ACTIVE_YAML" >/dev/null 2>&1; then
  log_error "active.yaml at $ACTIVE_YAML is not valid YAML — refusing to fan out (fail-closed). Fix or restore it before retrying."
  exit 1
fi
if [[ ! -f "$TASKS_YAML" ]]; then
  log_error "tasks.yaml not found at $TASKS_YAML — refusing to fan out"
  exit 1
fi

# ── Selection + limit simulation (single python3 pass) ─────────────────────
# Caps are read from active.yaml meta ONLY, at runtime, every invocation —
# no overrides file, no script-side constant. Fix for LEAD-FANOUT-01 defect 1
# (2026-07-14): an earlier version also consulted
# .claude/leadv2-overrides/active-limits.yaml with overrides-wins precedence
# (mirroring leadv2-active-registry.sh::leadv2_active_check_limits). That file
# still had stale hard_limit:3/standard_max:2 committed, so it silently beat
# the founder's live meta:20/20/20 edit — a self-inflicted, unrequested
# feature (the mission never asked for overrides support). Removed outright;
# active.yaml meta is now the single source of truth for fanout's caps.
# self-spawn.sh::_task_class convention (context.class or class, default
# Standard) is mirrored for class. class is currently always Standard on the
# live tasks.yaml (no context/class column in the generated schema) —
# heavy_strategic_solo logic still runs so it activates the moment a Heavy
# task lands in tasks.yaml.
# lean: no depends_on / conflicts_with cross-check here — Phase 0 of the
# spawned session already enforces collision-check + lock; upgrade when
# fanout needs to pre-filter conflicting file footprints before launch.
# --force bypasses the CONFIGURED ceiling (hard_limit/standard_max/light_max/
# heavy_strategic_solo, all read live from active.yaml meta) — it does NOT
# bypass the same-task-already-active exclusion, which is the actual
# worktree-collision safety net this task exists to protect.
set +e
PLAN_TSV="$(python3 - "$TASKS_YAML" "$ACTIVE_YAML" "$N" "$FILTER" "$EXPLICIT_TASKS" "$FORCE" "$SCRIPT_DIR" <<'PYEOF'
import datetime as _dt
import os, subprocess, sys, yaml

tasks_yaml, active_yaml, n_str, filt, explicit_csv, force_str, script_dir = sys.argv[1:8]
n = int(n_str)
filt = filt.lower()
explicit_ids = [t for t in explicit_csv.split(",") if t] if explicit_csv else []
force = force_str.lower() == "true"

with open(active_yaml, encoding="utf-8") as fh:
    active = yaml.safe_load(fh) or {}
meta = active.get("meta") or {}
sessions = [s for s in (active.get("sessions") or []) if not s.get("stale")]
active_task_ids = {str(s.get("task_id")) for s in sessions}

# active.yaml meta is the ONLY source for caps — read fresh every run, no
# overrides file, no hardcoded ceiling. Fallback defaults below only apply
# when a key is truly absent from meta (fresh/incomplete active.yaml).
# P0 concurrency fix (leadv2 0.2 audit): default hard_limit dropped 20 -> 2 —
# each child is an independent full-context session, so a high default
# multiplies token spend. Still fully overridable: any founder edit to
# active.yaml meta.hard_limit wins (this default only applies when the key is
# absent), preserving the LEAD-FANOUT-01 single-source-of-truth decision above.
hard_limit           = int(meta.get("hard_limit", 2))
# HEAVY-MAX-2-WITH-COLLISION-GUARD-01: heavy_max is now the SOLE control for
# concurrent Heavy/strategic lanes (was a blanket heavy_strategic_solo=True
# rule). Legacy heavy_strategic_solo is honored ONLY as the fallback default
# when heavy_max is absent from meta (very old active.yaml, back-compat) --
# or as an explicit kill-switch when a founder sets it True even with
# heavy_max present (forces serialize, heavy_max effectively 1).
heavy_max            = int(meta.get("heavy_max", 3))
if "heavy_max" in meta:
    heavy_strategic_solo = bool(meta.get("heavy_strategic_solo", False))
else:
    heavy_strategic_solo = bool(meta.get("heavy_strategic_solo", True))
light_max            = int(meta.get("light_max", 3))
standard_max         = int(meta.get("standard_max", 2))

total_active    = len(sessions)
light_count     = sum(1 for s in sessions if str(s.get("class", "")).lower() == "light")
standard_count  = sum(1 for s in sessions if str(s.get("class", "")).lower() in ("standard", "standard-light"))
heavy_sessions  = [s for s in sessions if str(s.get("class", "")).lower() in ("heavy", "strategic")]
heavy_count     = len(heavy_sessions)
heavy_active    = any(str(s.get("class", "")).lower() in ("heavy", "strategic") for s in sessions)

# Prod-risk tag set: a Heavy carrying any of these can never co-run with
# another Heavy carrying any of these -- both sides must be non-prod AND
# occupy disjoint subsystems (group_key) to co-run. Fail-closed (F3) on a
# missing/malformed/empty signal: unknown is treated as prod-risk, never as
# "no intersection => safe to co-run".
PROD_RISK_TAGS = {"publish", "deploy", "migration", "prod", "prod-deploy"}

def _norm_tags(raw):
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

def _group_key_unknown(gk):
    if gk is None:
        return True
    s = str(gk).strip().lower()
    return s in ("", "-", "none", "null")

# FIX1/FIX2 (Codex Phase-5 review, HEAVY-MAX-2-WITH-COLLISION-GUARD-01): the
# prior _heavy_collision() folded "unknown" into the prod predicate with AND
# (`_is_prod_or_unknown(cand) and _is_prod_or_unknown(other)`), so an
# unknown-risk/unknown-group candidate could co-run with a KNOWN-non-prod
# Heavy as long as the other side wasn't also unknown/prod. That is the
# opposite of fail-closed. Collide (serialize) if ANY of these hold, each an
# INDEPENDENT clause -- never AND'd across sides:
#   - unknown_risk(cand)  OR unknown_risk(other)   -> HARD
#   - unknown_group(cand) OR unknown_group(other)  -> HARD
#   - both_prod(cand, other)                       -> HARD
#   - same_known_group(cand, other)                -> SOFT *only* when both
#     sides are known-non-prod (neither unknown, neither carrying a prod-risk
#     tag) -- any other same-known-group pairing (e.g. one side prod, one
#     not) fails closed to HARD rather than being left unclassified.
# Business rule preserved: KNOWN-non-prod + KNOWN-non-prod with DIFFERENT
# known groups -> no collision, co-run allowed.
# Returns "hard", "soft", or None (no collision).
def _heavy_collision_kind(cand_gk, cand_tags, other_gk, other_tags):
    cand_tags_set = _norm_tags(cand_tags)
    other_tags_set = _norm_tags(other_tags)
    cand_unknown_risk = cand_tags_set is None
    other_unknown_risk = other_tags_set is None
    cand_unknown_group = _group_key_unknown(cand_gk)
    other_unknown_group = _group_key_unknown(other_gk)

    cand_prod = bool(cand_tags_set & PROD_RISK_TAGS) if cand_tags_set else False
    other_prod = bool(other_tags_set & PROD_RISK_TAGS) if other_tags_set else False
    both_prod = cand_prod and other_prod

    if cand_unknown_risk or other_unknown_risk or cand_unknown_group or other_unknown_group or both_prod:
        return "hard"

    same_known_group = str(cand_gk).strip().lower() == str(other_gk).strip().lower()
    if same_known_group:
        # Neither side is unknown or prod here (both branches above already
        # returned) -- this is exactly the bypassable SOFT case.
        return "soft"
    return None

try:
    with open(tasks_yaml, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
except Exception as e:
    print(f"[fanout] ERROR: tasks.yaml failed to parse: {e}", file=sys.stderr)
    sys.exit(1)
tasks = doc.get("tasks") if isinstance(doc, dict) else doc
tasks = tasks or []

CLASSIFY_SCRIPT = os.path.join(script_dir, "leadv2-fanout-classify.sh")

# SUPERVISOR-RETRO-01 item 1: replace the old missing-class -> "Standard"
# silent fallback with the pre-launch classifier. An explicit class already
# present on the task row is passed through as --existing-class and still
# wins (classifier preserves Heavy/Strategic, or a non-Standard class with
# no risk signal); "Standard" absence is exactly the gap being closed.
_classify_cache = {}


def classify_task(t):
    tid = str(t.get("id"))
    if tid in _classify_cache:
        return _classify_cache[tid]
    intent = str(t.get("intent") or t.get("title") or "")
    tags = t.get("tags") or t.get("labels") or []
    tags_csv = ",".join(str(x) for x in tags) if isinstance(tags, list) else str(tags)
    existing = str((t.get("context") or {}).get("class") or t.get("class") or "")

    # C2 fix (SUPERVISE-V2-01 fix-1): existence guard, loud WARN, and a SAFE
    # fallback -- never a silent Heavy/opus escalation. A missing/non-
    # executable classifier used to fall into the except branch below on
    # EVERY task (its only trigger was FileNotFoundError from a script that
    # didn't exist in this repo), force-upgrading every launch to Heavy/opus
    # and burning the scarce Claude-Max bucket, with the cause buried in an
    # unread report-line `reason` string. Preserve the existing tasks.yaml
    # class (or Standard) instead, and print the WARN to stderr where a human
    # actually sees it.
    if not (os.path.isfile(CLASSIFY_SCRIPT) and os.access(CLASSIFY_SCRIPT, os.X_OK)):
        print(f"[fanout] WARN: leadv2-fanout-classify.sh missing/not executable at {CLASSIFY_SCRIPT} -- "
              f"task={tid} falls back to existing class ({existing or 'Standard'}), NOT auto-escalated to Heavy. "
              "Run leadv2-plugin-sync.sh to fix.", file=sys.stderr)
        fallback_class = existing if existing else "Standard"
        fallback_model = "opus" if fallback_class.lower() in ("heavy", "strategic") else "sonnet"
        fallback_effort = "high" if fallback_class.lower() in ("heavy", "strategic") else "medium"
        result = (fallback_class, "", "classify script unavailable -- safe fallback, no risk escalation", fallback_model, fallback_effort)
        _classify_cache[tid] = result
        return result

    try:
        proc = subprocess.run(
            [CLASSIFY_SCRIPT, "--intent", intent, "--tags", tags_csv, "--existing-class", existing],
            capture_output=True, text=True, timeout=5, check=True,
        )
        out = {}
        for line in proc.stdout.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                out[k] = v
        result = (
            out.get("launch_class", "Standard") or "Standard",
            out.get("risk_tags", ""),
            out.get("reason", ""),
            out.get("lead_model", "sonnet") or "sonnet",
            out.get("lead_effort", "medium") or "medium",
        )
    except Exception as e:
        # Classifier crash (script exists but errored at runtime) is NOT a
        # "no signal" case -- escalate to Heavy/opus rather than silently
        # falling back to Standard (the exact bug this task fixes), but LOUD
        # this time: print the WARN so it isn't buried in an unread report
        # line. A human reviews the fanout report before anything runs.
        print(f"[fanout] WARN: leadv2-fanout-classify.sh crashed for task={tid} ({e}) -- "
              "escalating to Heavy/opus (conservative default on classifier crash).", file=sys.stderr)
        result = ("Heavy", "classifier_error", f"classifier failed: {e}", "opus", "high")
    _classify_cache[tid] = result
    return result

# Fix for LEAD-FANOUT-01 defect 2 (2026-07-14): tasks.yaml has NO literal
# `title` column (verified: 0/211 rows on the live generated schema). Every
# row DOES carry `intent` (a human-written one-liner, e.g.
# "BACKLOG-TRUTH-01: no live backlog -- ..."), which is the closest thing to
# a title this schema has. Use it, truncated for display; if a task has
# neither `title` nor `intent`, say so explicitly per-row instead of
# silently printing the bare hash.
NO_TITLE_COLUMN = not any("title" in t for t in tasks)

def task_title(t):
    raw = t.get("title") or t.get("intent")
    if not raw:
        return "(no title/intent field on this task)"
    raw = " ".join(str(raw).split())  # collapse newlines/tabs/extra spaces
    return raw if len(raw) <= 80 else raw[:77] + "..."

by_id = {str(t.get("id")): t for t in tasks}

# S4-DEAD-LANE-REQUEUE-01: a dead lane can leave a work_items row at
# status=pending (docs/tasks.yaml's local-only dispatcher overlay -- see
# scripts/task-sync-yaml.sh) with claimed_by already null and no supported
# write path back to queued. _is_dispatchable() is the SHARED predicate for
# both candidate-scan sites in this file (D-1: the automatic scan below AND
# the explicit --task re-dispatch check further down) -- patching only one
# leaves the other's manual escape hatch closed, which is the exact defect
# this task fixes.
#
# Backward compatibility: against a docs/tasks.yaml generated before the
# requeue columns land, claim_lease_until/dispatch_attempts are simply
# absent, .get() defaults to None/0, and this predicate degrades to exactly
# today's `status == "queued"` -- no flag-day required.
REQUEUE_MAX_ATTEMPTS = int(os.environ.get("LEADV2_REQUEUE_MAX_ATTEMPTS", "2"))

def _lease_expired(t):
    v = t.get("claim_lease_until")
    if not v:
        return False  # no lease ever taken -- never treat a null lease as expired
    try:
        ts = _dt.datetime.fromisoformat(str(v).replace("Z", "+00:00"))
    except ValueError:
        return False
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=_dt.timezone.utc)
    return ts < _dt.datetime.now(_dt.timezone.utc)

def _is_dispatchable(t):
    attempts = int(t.get("dispatch_attempts", 0) or 0)
    if attempts >= REQUEUE_MAX_ATTEMPTS:
        return False  # give-up ceiling: reported via a skip row, never selected
    if str(t.get("status", "")) == "queued":
        return True
    # A pending row with a NULL lease was never claimed -- nothing died, it
    # stays out. Without this guard the predicate would sweep the entire
    # pending backlog into the candidate set on the first run (R-7).
    return str(t.get("status", "")) in ("pending", "in_progress") and _lease_expired(t)

def _requeue_giveup_reason(t):
    return t.get("requeue_giveup_reason") or f"requeue attempts exhausted {t.get('dispatch_attempts', 0)}/{REQUEUE_MAX_ATTEMPTS}"

rows = []  # (decision, task_id, label, cls, priority, reason, risk_tags, lead_model, lead_effort)

if explicit_ids:
    ordered = []
    for tid in explicit_ids:
        t = by_id.get(tid)
        if t is None:
            rows.append(("skip", tid, tid, "?", "", "not found in tasks.yaml", "", "", "", ""))
            continue
        ordered.append(t)
else:
    candidates = [
        t for t in tasks
        if _is_dispatchable(t) and str(t.get("id")) not in active_task_ids
    ]
    give_up_candidates = [
        t for t in tasks
        if not _is_dispatchable(t)
        and int(t.get("dispatch_attempts", 0) or 0) >= REQUEUE_MAX_ATTEMPTS
        and str(t.get("id")) not in active_task_ids
    ]
    for t in give_up_candidates:
        tid = str(t.get("id"))
        rows.append(("skip", tid, task_title(t), "?", t.get("priority", ""),
                     f"requeue give-up ({t.get('dispatch_attempts', 0)}/{REQUEUE_MAX_ATTEMPTS}) — {_requeue_giveup_reason(t)}",
                     "", "", "", t.get("group_key")))
    if filt:
        candidates = [
            t for t in candidates
            if filt in str(t.get("id", "")).lower()
            or filt in str(t.get("group_key", "")).lower()
            or filt in str(t.get("intent", "")).lower()
        ]
    candidates.sort(
        key=lambda t: (-int(t.get("priority", 0) or 0),
                       -int(t.get("group_priority", 0) or 0),
                       str(t.get("id", "")))
    )
    ordered = candidates[:n]

# Heavy/strategic footprints claimed THIS run (F2): a 2nd Heavy selected in
# the SAME fanout pass must collision-check against the 1st, not only
# against live sessions from the active.yaml snapshot. list[(group_key, risk_tags)].
heavy_claimed_this_run = []

for t in ordered:
    tid = str(t.get("id"))
    label = task_title(t)
    cls, risk_tags, class_reason, lead_model, lead_effort = classify_task(t)
    cls_l = cls.lower()
    pri = t.get("priority", "")
    cand_group_key = t.get("group_key")

    # Unconditional, never bypassed by --force: this IS the worktree-collision
    # safety net (two leads claiming the same task_id == two leads in the
    # same worktree, the exact failure this task exists to prevent).
    if tid in active_task_ids:
        rows.append(("skip", tid, label, cls, pri, "already in active.yaml (session running)", risk_tags, lead_model, lead_effort, cand_group_key))
        continue

    # D-1: this is the manual escape hatch a human hits to respawn a dead
    # lane by name -- it MUST use the same _is_dispatchable() as the
    # automatic scan above, or a lease-expired/pending row stays refused
    # here even after the scan above starts finding it.
    if explicit_ids and not _is_dispatchable(t):
        attempts = int(t.get("dispatch_attempts", 0) or 0)
        if attempts >= REQUEUE_MAX_ATTEMPTS:
            reason = f"requeue give-up ({attempts}/{REQUEUE_MAX_ATTEMPTS}) — {_requeue_giveup_reason(t)}"
        else:
            lease = t.get("claim_lease_until")
            if lease:
                reason = f"lease still held until {lease}"
            else:
                reason = f"not queued (status={t.get('status')})"
        rows.append(("skip", tid, label, cls, pri, reason, risk_tags, lead_model, lead_effort, cand_group_key))
        continue

    # hard_violation: NEVER --force-bypassable (F5) -- hard_limit and
    # heavy_max are ceilings, not policy defaults. soft_violation: the legacy
    # solo kill-switch, per-class caps, and the collision-serialize decision
    # remain --force-overridable, unchanged from prior behavior.
    hard_violation = None
    soft_violation = None
    if total_active >= hard_limit:
        hard_violation = f"hard_limit reached ({total_active}/{hard_limit})"
    elif cls_l in ("heavy", "strategic"):
        claimed_heavy = heavy_count + len(heavy_claimed_this_run)
        if heavy_strategic_solo:
            if claimed_heavy > 0:
                soft_violation = "heavy_strategic_solo: another Heavy/strategic session already active/claimed — heavy must run alone"
        elif claimed_heavy >= heavy_max:
            hard_violation = f"heavy_max reached ({claimed_heavy}/{heavy_max})"
        else:
            kinds = [
                _heavy_collision_kind(cand_group_key, risk_tags, s.get("group_key"), s.get("risk_tags"))
                for s in heavy_sessions
            ] + [
                _heavy_collision_kind(cand_group_key, risk_tags, prev_gk, prev_tags)
                for (prev_gk, prev_tags) in heavy_claimed_this_run
            ]
            # FIX2: a HARD collision (both_prod OR any unknown risk/group) is
            # NEVER --force-bypassable -- it goes in hard_violation. Only a
            # SOFT collision (same known-non-prod group only) stays
            # --force-overridable via soft_violation.
            if "hard" in kinds:
                hard_violation = "heavy collision (prod/unknown footprint) — serialize, not force-bypassable"
            elif "soft" in kinds:
                soft_violation = "heavy collision (same known group) — serialize"
    elif heavy_active or heavy_claimed_this_run:
        soft_violation = "heavy/strategic session active — solo rule blocks others"
    elif cls_l == "light" and light_count >= light_max:
        soft_violation = f"light cap reached ({light_count}/{light_max})"
    elif cls_l in ("standard", "standard-light") and standard_count >= standard_max:
        soft_violation = f"standard cap reached ({standard_count}/{standard_max})"

    violation = hard_violation or soft_violation
    if violation and (hard_violation or not force):
        rows.append(("skip", tid, label, cls, pri, violation, risk_tags, lead_model, lead_effort, cand_group_key))
        continue

    reason = f"selected ({class_reason})" if not violation else f"FORCE OVERRIDE — would have hit: {violation}"
    rows.append(("launch", tid, label, cls, pri, reason, risk_tags, lead_model, lead_effort, cand_group_key))
    total_active += 1
    if cls_l in ("heavy", "strategic"):
        heavy_claimed_this_run.append((cand_group_key, risk_tags))
        heavy_active = True
    elif cls_l == "light":
        light_count += 1
    else:
        standard_count += 1

print(f"__NO_TITLE_COLUMN__\t{NO_TITLE_COLUMN}")
for r in rows:
    # bash `read` with IFS=$'\t' collapses RUNS of tab (tab is IFS-whitespace-
    # class, not a plain delimiter) -- an empty field (e.g. no risk_tags)
    # would silently swallow a tab and shift every later field left by one.
    # "-" is the on-the-wire empty marker; the bash consumer below undoes it.
    print("\t".join((str(x).replace("\t", " ").replace("\n", " ") or "-") for x in r))
PYEOF
)"
PY_RC=$?
if [[ $PY_RC -ne 0 ]]; then
  log_error "selection failed (rc=$PY_RC) — refusing to fan out"
  exit 1
fi

LAUNCH_COUNT=0
SKIP_COUNT=0
FORCED_ANY=false
NO_TITLE_COLUMN=false
declare -a LAUNCH_IDS=() LAUNCH_CLASSES=() LAUNCH_LABELS=()
declare -a LAUNCH_MODELS=() LAUNCH_EFFORTS=() LAUNCH_RISK_TAGS=() LAUNCH_REASONS=()
declare -a LAUNCH_PROVIDERS=() LAUNCH_ROUTE_REASONS=() LAUNCH_GROUP_KEYS=()
declare -a REPORT_LINES=()

SESSION_ROUTER="${LEADV2_SESSION_ROUTER:-$SCRIPT_DIR/leadv2-session-route.sh}"
if [[ ! -x "$SESSION_ROUTER" ]]; then
  log_error "provider router missing/not executable at $SESSION_ROUTER — refusing to launch an unclassified provider session"
  exit 1
fi

while IFS=$'\t' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 f10; do
  [[ -z "$f1" ]] && continue
  if [[ "$f1" == "__NO_TITLE_COLUMN__" ]]; then
    [[ "$f2" == "True" ]] && NO_TITLE_COLUMN=true
    continue
  fi
  decision="$f1" tid="$f2" label="$f3" cls="$f4" pri="$f5" reason="$f6"
  risk_tags="$f7" lead_model="$f8" lead_effort="$f9" group_key="$f10"
  # undo the "-" empty-field marker (see PLAN_TSV emission comment above)
  [[ "$risk_tags" == "-" ]] && risk_tags=""
  [[ "$group_key" == "-" ]] && group_key=""
  # --lead-model CLI override wins over the classifier's per-task pick for
  # EVERY launch this run — opt-out valve for a founder-requested Opus child.
  # Effort is left as the classifier chose it (override is model-only).
  if [[ -n "$LEAD_MODEL_OVERRIDE" && "$decision" == "launch" ]]; then
    lead_model="$LEAD_MODEL_OVERRIDE"
    reason="${reason} (--lead-model override -> ${LEAD_MODEL_OVERRIDE})"
  fi
  if [[ "$decision" == "launch" ]]; then
    set +e
    route_output="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" "$SESSION_ROUTER" \
      --class "$cls" \
      --risk-tags "$risk_tags" \
      --suggested-model "${lead_model:-sonnet}" \
      --suggested-effort "${lead_effort:-medium}" \
      --provider "$PROVIDER_REQUEST")"
    route_rc=$?
    set -e
    if [[ "$route_rc" -ne 0 ]]; then
      log_error "provider routing failed for task=${tid} (rc=${route_rc}) — refusing to launch"
      exit 1
    fi
    route_provider="" route_model="" route_effort="" route_reason=""
    while IFS='=' read -r route_key route_value; do
      case "$route_key" in
        provider) route_provider="$route_value" ;;
        model)    route_model="$route_value" ;;
        effort)   route_effort="$route_value" ;;
        reason)   route_reason="$route_value" ;;
      esac
    done <<< "$route_output"
    if [[ -z "$route_provider" || -z "$route_model" || -z "$route_effort" ]]; then
      log_error "provider router returned an incomplete decision for task=${tid} — refusing to launch"
      exit 1
    fi
    # An explicit model is the founder's final model choice. Provider inference
    # above keeps aliases on the correct runtime; the router still owns all
    # high-risk/provider-availability decisions.
    if [[ -n "$LEAD_MODEL_OVERRIDE" ]]; then
      if [[ "$route_provider" == "codex" && "$LEAD_MODEL_OVERRIDE" == gpt-* ]] \
         || [[ "$route_provider" == "claude" && "$LEAD_MODEL_OVERRIDE" != gpt-* && "$LEAD_MODEL_OVERRIDE" != codex-* ]]; then
        route_model="$LEAD_MODEL_OVERRIDE"
      else
        route_reason="${route_reason}; incompatible --lead-model ignored after provider safety fallback"
      fi
    fi
    LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
    LAUNCH_IDS+=("$tid")
    LAUNCH_CLASSES+=("$cls")
    LAUNCH_LABELS+=("$label")
    LAUNCH_PROVIDERS+=("$route_provider")
    LAUNCH_MODELS+=("$route_model")
    LAUNCH_EFFORTS+=("$route_effort")
    LAUNCH_RISK_TAGS+=("$risk_tags")
    LAUNCH_REASONS+=("$reason")
    LAUNCH_ROUTE_REASONS+=("$route_reason")
    LAUNCH_GROUP_KEYS+=("$group_key")
    REPORT_LINES+=("- LAUNCH \`${label}\` (\`${tid}\`) — class=${cls}, priority=${pri}, provider=${route_provider}, model=${route_model}/${route_effort}, risk_tags=[${risk_tags}] — ${reason}; route=${route_reason}")
    [[ "$reason" == *"FORCE OVERRIDE"* ]] && FORCED_ANY=true
  else
    SKIP_COUNT=$((SKIP_COUNT + 1))
    REPORT_LINES+=("- skip \`${label}\` (\`${tid}\`, class=${cls}) — ${reason}")
  fi
done <<< "$PLAN_TSV"

log "plan: ${LAUNCH_COUNT} to launch, ${SKIP_COUNT} skipped"
for line in "${REPORT_LINES[@]:-}"; do
  [[ -n "$line" ]] && log "$line"
done

if [[ "$LAUNCH_COUNT" -eq 0 ]]; then
  log "nothing to launch — see reasons above"
fi

# ── Report artifact ─────────────────────────────────────────────────────────
TS_ISO="$(date -u +"%Y%m%dT%H%M%SZ")"
REPORT_FILE="${PROJECT_ROOT}/docs/leadv2/fanout-${TS_ISO}.md"
mkdir -p "${PROJECT_ROOT}/docs/leadv2"

{
  printf -- '# fanout %s\n\n' "$TS_ISO"
  printf -- 'mode: %s%s\n\n' \
    "$([[ "$DRY_RUN" == "true" ]] && echo "DRY-RUN — nothing launched" || echo "LIVE")" \
    "$([[ "$FORCE" == "true" ]] && echo " (--force)" || echo "")"
  if [[ "$FORCED_ANY" == "true" ]]; then
    printf -- '## ⚠️ FORCE OVERRIDE ACTIVE ⚠️\n\n'
    printf -- 'At least one launch below exceeded the CONFIGURED ceiling in\n'
    printf -- 'docs/leadv2/active.yaml meta (hard_limit / standard_max / light_max /\n'
    printf -- 'heavy_strategic_solo). --force bypassed the policy cap — it never bypasses\n'
    printf -- 'the same-task-already-active exclusion. Lines tagged "FORCE OVERRIDE" below\n'
    printf -- 'name exactly which cap was exceeded and by how much.\n\n'
  fi
  if [[ "$NO_TITLE_COLUMN" == "true" ]]; then
    printf -- '## Task labels\n\n'
    printf -- 'docs/tasks.yaml has no `title` column. The label shown before each id below\n'
    printf -- 'is the `intent` field (truncated to 80 chars) — the closest thing this schema\n'
    printf -- 'has to a human title. Rows with neither `title` nor `intent` show that\n'
    printf -- 'explicitly instead of a bare hash.\n\n'
  fi
  printf -- '## Plan\n\n'
  for line in "${REPORT_LINES[@]:-}"; do
    [[ -n "$line" ]] && printf -- '%s\n' "$line"
  done
  printf -- '\n## Merge serialization (not this script'"'"'s job)\n\n'
  printf -- 'Fanning out %d session(s) means up to %d parallel /leadv2 leads may reach\n' "$LAUNCH_COUNT" "$LAUNCH_COUNT"
  printf -- '`main` around the same time. This script does NOT assume exclusive main\n'
  printf -- 'access and does NOT do any merge/rebase coordination itself — merges are\n'
  printf -- 'serialized by a separate mechanism (docs/leadv2/merge-queue.jsonl, owned by\n'
  printf -- 'another agent). If that queue is not live yet, do not fan out into `main`\n'
  printf -- 'writes without a human watching.\n'
  printf -- '\n## Quota warning\n\n'
  printf -- '%d slot(s) requested to launch this run. Flat subscription, but each parallel\n' "$LAUNCH_COUNT"
  printf -- '/leadv2 Opus lead still burns real weekly quota — do not fan out more than you\n'
  printf -- 'are prepared to actively watch. hard_limit=%s.\n' "$(python3 -c "import yaml; print((yaml.safe_load(open('${ACTIVE_YAML}')) or {}).get('meta',{}).get('hard_limit','?'))" 2>/dev/null || echo "?")"
} > "$REPORT_FILE"

log "report written: $REPORT_FILE"

if [[ "$DRY_RUN" == "true" ]]; then
  log "--dry-run: exiting without launching anything"
  exit 0
fi

if [[ "$LAUNCH_COUNT" -eq 0 ]]; then
  exit 0
fi

# _fanout_register_session — atomic write-temp+rename under flock on the
# SAME lockfile leadv2-active-registry.sh uses, so up to N fanout launches
# (and any concurrently-running gate1 self-registrations) serialize safely.
# Writes the exact field set the supervisor/session-bus need: task_id,
# worktree, branch, pid, window_title, started_at — plus the existing schema
# fields (class/phase/daemon_mode/etc.) so old readers keep working.
# Reimplemented locally (not by editing leadv2-active-registry.sh, which is
# out of this task's file scope) because its register() op has no
# window_title parameter slot.
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
  # BLOCKING fix (review-verdict.md fanout.sh:1410-1426): the pulse_log below used
  # to be hardcoded to the phase-cycle path for EVERY backend, including the
  # dispatch-code.sh funnel -- which never writes there (it writes
  # docs/handoff/dispatch-<sig8>/...). liveness/product-close then can't find the
  # funnel's real log. Optional 15th arg lets a caller (launch_via_dispatch_code)
  # supply the artifact path it actually knows about; every existing caller omits
  # it and keeps today's hardcoded path, unchanged.
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

# FIX3 (HEAVY-MAX-2-WITH-COLLISION-GUARD-01 Codex Phase-5 review): the F6
# under-lock re-count above only re-checks the numeric heavy_max/hard_limit
# ceiling -- it never re-ran the pairwise group_key/risk_tags collision the
# selection pass did OUTSIDE this lock. Two concurrent fanout invocations
# each selecting a distinct Heavy from the same prod-risk/unknown footprint
# can both pass the (unlocked) selection-time check and then both register
# here successfully, because neither sees the other's row until after both
# locks have already been acquired and released. Re-run ONLY the HARD half
# of the collision predicate (both_prod OR any unknown risk/group -- see
# _heavy_collision_kind in the selection pass above) under THIS lock, against
# every live heavy/strategic session already in the locked snapshot. The SOFT
# case (same known-non-prod group) is --force-bypassable by design and is not
# re-enforced under lock, consistent with the selection-pass semantics.
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
        # P0 concurrency fix (leadv2 0.2 audit): bootstrap default hard_limit
        # dropped 20 -> 2, same rationale as the read-path fallback above.
        # Overridable: a founder edit to the resulting active.yaml meta wins
        # on every subsequent run (this literal only fires once, at first
        # bootstrap of a missing active.yaml).
        data = {"meta": {"schema_version": 2, "hard_limit": 2,
                          "heavy_max": 3, "heavy_strategic_solo": False,
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

    # F6 (HEAVY-MAX-2-WITH-COLLISION-GUARD-01): register-time re-count under
    # the SAME lock -- the active.yaml snapshot the selection pass read was
    # taken OUTSIDE this lock, so a concurrent fanout invocation may have
    # registered a Heavy/strategic session (or hit hard_limit) in the
    # meantime. Re-derive live counts from THIS locked read and refuse
    # admission if it would exceed either ceiling. hard_limit/heavy_max are
    # hard invariants (F5, never --force-bypassable), so no force flag is
    # threaded through here -- only the numeric ceiling is re-verified.
    meta_live = data.get("meta") or {}
    heavy_max_live = int(meta_live.get("heavy_max", 3))
    hard_limit_live = int(meta_live.get("hard_limit", 2))
    live_sessions = [s for s in sessions if not s.get("stale")]
    live_heavy = sum(1 for s in live_sessions if str(s.get("class", "")).lower() in ("heavy", "strategic"))
    if cls.lower() in ("heavy", "strategic") and live_heavy >= heavy_max_live:
        print(f"[fanout] LOST_RACE: {task_id} would exceed heavy_max under lock ({live_heavy}/{heavy_max_live}) -- refusing to register", file=sys.stderr)
        sys.exit(3)
    if len(live_sessions) >= hard_limit_live:
        print(f"[fanout] LOST_RACE: {task_id} would exceed hard_limit under lock ({len(live_sessions)}/{hard_limit_live}) -- refusing to register", file=sys.stderr)
        sys.exit(3)

    # FIX3: pairwise HARD-collision re-check under THIS lock (see
    # _hard_collision above) -- catches the exact race the numeric re-count
    # above cannot: two concurrent fanout invocations each independently
    # selecting a distinct Heavy with a prod-risk/unknown footprint, neither
    # visible to the other's (unlocked) selection-time snapshot.
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
        # SUPERVISOR-RETRO-01 item 1: persisted classifier output — the
        # pre-launch decision that picked "class" above, kept for audit.
        "risk_tags": risk_tags,
        "group_key": group_key_norm,
        "lead_model": lead_model,
        "lead_effort": lead_effort,
        "class_reason": class_reason,
        "provider": provider,
        "route_reason": route_reason,
        # SUPERVISE-V2-01 fix-1 (Codex#2): same registry-honesty field set
        # leadv2_active_register()/op=register writes (leadv2-active-registry.sh)
        # -- fanout is a SECOND writer of active.yaml (window_title has no slot
        # in the shared register() op, see comment above), so these fields must
        # be set here too rather than routed through that function.
        "protocol_version": 2,
        "backend": where,
        "phase_started_at": started_at,
        "updated_at": started_at,
        "tmux_window": window_title if where == "tmux" else None,
        # lean: pane index not tracked (one pane per window in this backend)
        # -- upgrade when launch_tmux ever splits panes within a window.
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
    # FIX4: rc==3 means admission was refused under lock (F6 ceiling race OR
    # FIX3 pairwise HARD-collision race). The caller already spawned the
    # child process before this call -- returning 3 here tells it to KILL
    # that child rather than leaving it running unregistered (the ceiling was
    # cosmetic otherwise: it capped active.yaml rows, not actual processes).
    log "WARN: ${tid} lost the register-time admission race under lock (F6/FIX3) — refusing to register; caller must terminate the spawned child"
  elif [[ "$_reg_rc" -ne 0 ]]; then
    log "WARN: could not register ${tid} in active.yaml — session is running unregistered"
  fi
  return "$_reg_rc"
}

# _fanout_kill_child <pid> <used_setsid> — FIX4: terminate a just-spawned
# child whose registration was refused under lock (rc==3 from
# _fanout_register_session), so the heavy_max/hard_limit ceiling caps actual
# running sessions, not just active.yaml rows. When the child was started via
# setsid it is its own session/process-group leader (pid == pgid), so kill
# the whole group (`-pid`) to take any grandchildren (the runner's own
# subprocess tree) with it; TERM first, KILL after a short grace window if it
# didn't die. Without setsid (macOS fallback with no setsid binary) the child
# shares this script's process group, so killing the group would be
# collateral damage -- kill only the specific pid in that case.
_fanout_kill_child() {
  local pid="$1" used_setsid="${2:-false}"
  [[ -z "$pid" || "$pid" == "null" ]] && return 0
  if [[ "$used_setsid" == "true" ]]; then
    kill -TERM -- "-${pid}" 2>/dev/null || true
  else
    kill -TERM "$pid" 2>/dev/null || true
  fi
  sleep 0.3
  if kill -0 "$pid" 2>/dev/null; then
    if [[ "$used_setsid" == "true" ]]; then
      kill -KILL -- "-${pid}" 2>/dev/null || true
    else
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}

launch_headless() {
  local tid="$1" cls="$2" lead_model="${3:-sonnet}" lead_effort="${4:-medium}"
  local risk_tags="${5:-}" class_reason="${6:-}"
  local provider="${7:-claude}" route_reason="${8:-}"
  local group_key="${9:-}"
  local task_dir="${PROJECT_ROOT}/docs/handoff/${tid}"
  mkdir -p "$task_dir"
  local logf="${task_dir}/fanout.log"

  # exec inside the subshell so $! (of the outer &) IS the setsid pid, not an
  # extra unexeced subshell layer — matches leadv2-session-spawner.sh's own
  # setsid-nohup convention as closely as bash allows with an explicit cd.
  # LEAD-ANCHOR-01: LEADV2_ASYNC_QUESTIONS=1 tells the spawned session's founder
  # is watching the SUPERVISING lead's window, not this one — route every
  # founder-facing question through leadv2-ask.sh instead of AskUserQuestion.
  # SUPERVISOR-RETRO-01 item 2: hand off to leadv2-session-runner.sh instead of
  # calling `claude -p` directly — the runner owns --model/--effort pinning
  # plus the resume-on-exit completion loop to phase8-passed.flag.
  # FANOUT-MACOS-LAUNCHER-01: macOS has no setsid — fall back to plain nohup
  # inside the same subshell; nohup + trailing `&` still detaches from the
  # controlling terminal, and $! below keeps resolving to the runner pid on
  # both branches (see comment above).
  # The provider-neutral runner is a hard dependency. Falling back to a raw
  # one-shot CLI would violate the supervisor's Phase 0..8 + sentinel contract.
  # MEDIUM-3 (fixround-tails): overridable so tests can point at a fast-exit stub instead
  # of mv/cp-swapping the CANONICAL leadv2-session-runner.sh in the source tree -- a
  # SIGINT/SIGTERM/SIGKILL during that swap window would leave the real runner replaced by
  # the stub with no restore (a RETURN trap does not fire on those signals), silently
  # no-oping every subsequent /leadv2 launch. Matches the LEADV2_FANOUT_WRITES_OVERLAP_BIN
  # idiom already used elsewhere in this file.
  local _runner="${LEADV2_SESSION_RUNNER_BIN:-${SCRIPT_DIR}/leadv2-session-runner.sh}"
  if [[ ! -x "$_runner" ]]; then
    log_error "leadv2-session-runner.sh missing/not executable at ${_runner} — refusing an unguarded one-shot launch"
    return 1
  fi
  # LANE-WORKTREE-ISOLATION-01: create (or reattach) this lane's own git
  # worktree+branch BEFORE launch, and run the child there instead of the
  # shared PROJECT_ROOT — SD-LANES-HAVE-NO-WORKTREE-01 found headless children
  # never actually isolated (Phase 0's EnterWorktree call is not reliable for
  # fanout children). LEADV2_PROJECT_ROOT is pinned to the ORIGINAL shared
  # root so control-plane files (active.yaml, docs/handoff, bus.jsonl) still
  # resolve to the one shared location regardless of which worktree the
  # child's code edits land in. ensure() never fails the launch — on any git
  # error it logs loud and falls back to PROJECT_ROOT (legacy shared tree).
  local _lane_dir
  _lane_dir="$("${SCRIPT_DIR}/leadv2-lane-worktree.sh" ensure "$tid" "$cls" 2>>"$logf")"
  [[ -n "$_lane_dir" ]] || _lane_dir="$PROJECT_ROOT"
  leadv2_active_set_worktree "$tid" "$_lane_dir" || true
  local _used_setsid=false
  if command -v setsid >/dev/null 2>&1; then
    _used_setsid=true
    ( cd "$_lane_dir" && \
      exec env LEADV2_DAEMON=1 LEADV2_ASYNC_QUESTIONS=1 LEADV2_FANOUT=1 \
        LEADV2_TASK_ID="${tid}" LEADV2_LEAD_MODEL="${lead_model}" \
        LEADV2_LEAD_EFFORT="${lead_effort}" LEADV2_SESSION_PROVIDER="${provider}" \
        LEADV2_RUNNER_FORCE_FRESH="${FORCE}" LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" \
        setsid nohup "$_runner" </dev/null >>"$logf" 2>&1 ) &
  else
    ( cd "$_lane_dir" && \
      exec env LEADV2_DAEMON=1 LEADV2_ASYNC_QUESTIONS=1 LEADV2_FANOUT=1 \
        LEADV2_TASK_ID="${tid}" LEADV2_LEAD_MODEL="${lead_model}" \
        LEADV2_LEAD_EFFORT="${lead_effort}" LEADV2_SESSION_PROVIDER="${provider}" \
        LEADV2_RUNNER_FORCE_FRESH="${FORCE}" LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" \
        nohup "$_runner" </dev/null >>"$logf" 2>&1 ) &
  fi
  local pid=$!
  log "headless launch: task=${tid} pid=${pid} provider=${provider} model=${lead_model}/${lead_effort} lane_dir=${_lane_dir} log=${logf}"

  local _reg_rc=0
  _fanout_register_session "$tid" "$cls" "$pid" "leadv2: ${tid}" "true" "false" "headless" \
    "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || _reg_rc=$?
  leadv2_active_set_worktree "$tid" "$_lane_dir" || true
  if [[ "$_reg_rc" -eq 3 ]]; then
    log "WARN: ${tid} admission refused under lock (F6/FIX3) — killing spawned child pid=${pid} (setsid=${_used_setsid})"
    _fanout_kill_child "$pid" "$_used_setsid"
  fi
}

# Escape a string for safe interpolation into an AppleScript double-quoted
# string literal: backslash first (so we don't double-escape the quotes we
# add next), then double-quote.
_osa_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# _fanout_resolve_spawned_pid <tid> — one poll attempt. Prints the newest
# live pid whose cmdline matches "/leadv2 <tid>" and is not already claimed by
# another row in active.yaml. Returns 1 (empty stdout) if no match yet. Shared
# by both launch_windowed (osascript hands back no pid) and launch_tmux
# (tmux new-window hands back no `claude` pid either, only the shell's) — do
# not duplicate this poll loop per backend.
_fanout_resolve_spawned_pid() {
  local tid="$1" yaml_file candidates registered p newest="" pid_file runner_pid
  pid_file="${PROJECT_ROOT}/docs/handoff/${tid}/.session-runner.pid"
  if [[ -f "$pid_file" ]]; then
    runner_pid="$(tr -d '[:space:]' < "$pid_file")"
    if [[ "$runner_pid" =~ ^[0-9]+$ ]] && kill -0 "$runner_pid" 2>/dev/null; then
      printf -- '%s' "$runner_pid"
      return 0
    fi
  fi
  candidates="$(pgrep -f "/leadv2 ${tid}" 2>/dev/null || true)"
  [[ -z "$candidates" ]] && return 1
  yaml_file="$(_leadv2_yaml_file)"
  registered="$(python3 -c "
import sys, yaml
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
print(' '.join(str(s.get('pid')) for s in (data.get('sessions') or []) if s.get('pid') is not None))
" "$yaml_file" 2>/dev/null || true)"
  for p in $candidates; do
    case " ${registered} " in
      *" ${p} "*) continue ;;
    esac
    newest="$p"
  done
  [[ -n "$newest" ]] || return 1
  printf -- '%s' "$newest"
}

launch_windowed() {
  local tid="$1" cls="$2" lead_model="${3:-sonnet}" lead_effort="${4:-medium}"
  local risk_tags="${5:-}" class_reason="${6:-}"
  local provider="${7:-claude}" route_reason="${8:-}"
  local group_key="${9:-}"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "windowed launch requires macOS (osascript). Use --headless on this platform."
    exit 1
  fi
  if ! command -v osascript >/dev/null 2>&1; then
    log_error "osascript not found — cannot open terminal windows. Use --headless."
    exit 1
  fi

  local title="leadv2: ${tid}"
  local cmd
  # MEDIUM-3 (fixround-tails): overridable so tests can point at a fast-exit stub instead
  # of mv/cp-swapping the CANONICAL leadv2-session-runner.sh in the source tree -- a
  # SIGINT/SIGTERM/SIGKILL during that swap window would leave the real runner replaced by
  # the stub with no restore (a RETURN trap does not fire on those signals), silently
  # no-oping every subsequent /leadv2 launch. Matches the LEADV2_FANOUT_WRITES_OVERLAP_BIN
  # idiom already used elsewhere in this file.
  local _runner="${LEADV2_SESSION_RUNNER_BIN:-${SCRIPT_DIR}/leadv2-session-runner.sh}"
  if [[ ! -x "$_runner" ]]; then
    log_error "leadv2-session-runner.sh missing/not executable at ${_runner} — refusing an unguarded one-shot launch"
    return 1
  fi
  # Windowed children use the same provider-neutral completion runner as
  # headless/tmux. The visible terminal is observability, not a weaker
  # lifecycle contract.
  # LANE-WORKTREE-ISOLATION-01: same ensure()-before-launch as launch_headless
  # — cd into the lane's own worktree, keep LEADV2_PROJECT_ROOT pinned to the
  # shared root for control-plane files.
  local _lane_dir
  _lane_dir="$("${SCRIPT_DIR}/leadv2-lane-worktree.sh" ensure "$tid" "$cls")"
  [[ -n "$_lane_dir" ]] || _lane_dir="$PROJECT_ROOT"
  leadv2_active_set_worktree "$tid" "$_lane_dir" || true
  printf -v cmd 'cd %q && export LEADV2_DAEMON=1 LEADV2_ASYNC_QUESTIONS=1 LEADV2_FANOUT=1 LEADV2_TASK_ID=%q LEADV2_LEAD_MODEL=%q LEADV2_LEAD_EFFORT=%q LEADV2_SESSION_PROVIDER=%q LEADV2_RUNNER_FORCE_FRESH=%q LEADV2_PROJECT_ROOT=%q; exec %q' \
    "$_lane_dir" "$tid" "$lead_model" "$lead_effort" "$provider" "$FORCE" "$PROJECT_ROOT" "$_runner"

  # AppleScript double-quoted strings treat backslash as an escape char, but
  # bash's %q emits backslash-escaped tokens (e.g. `/leadv2\ ${tid}`) — raw
  # interpolation broke every osascript call with a -2741 syntax error and no
  # window ever opened. Escape for AppleScript (backslash first, then quote)
  # on both interpolated strings before embedding.
  local cmd_osa title_osa
  cmd_osa="$(_osa_escape "$cmd")"
  title_osa="$(_osa_escape "$title")"

  if pgrep -x iTerm2 >/dev/null 2>&1; then
    osascript <<OSA
tell application "iTerm2"
  set newWindow to (create window with default profile)
  tell current session of newWindow
    set name to "${title_osa}"
    write text "${cmd_osa}"
  end tell
end tell
OSA
  else
    osascript <<OSA
tell application "Terminal"
  set newTab to do script "${cmd_osa}"
  set custom title of front window to "${title_osa}"
  activate
end tell
OSA
  fi
  log "windowed launch: task=${tid} provider=${provider} model=${lead_model}/${lead_effort} title='${title}'"

  # osascript hands the shell command to Terminal/iTerm2 asynchronously and
  # never hands back the spawned `claude` process pid directly. Registering
  # with pid=null let the row be indistinguishable from a dead session to any
  # pid-liveness sweep, and 3-of-4 windowed launches were silently dropped
  # from active.yaml as a result (LEAD-ANCHOR-01). Resolve the REAL pid by
  # polling pgrep for the newly-spawned "/leadv2 ${tid}" process (bounded,
  # ~10s @ 0.25s intervals — osascript + shell + claude startup is usually
  # <1s but give slow machines headroom). If it still can't be found, fall
  # back to pid_pending=true; the stale-sweeper grants pid_pending rows a
  # grace window instead of treating them as dead.
  local _resolved_pid="" _attempt
  for ((_attempt = 0; _attempt < 40; _attempt++)); do
    _resolved_pid="$(_fanout_resolve_spawned_pid "$tid" || true)"
    [[ -n "$_resolved_pid" ]] && break
    sleep 0.25
  done

  local _reg_rc=0
  if [[ -n "$_resolved_pid" ]]; then
    log "windowed launch: task=${tid} resolved pid=${_resolved_pid} model=${lead_model}/${lead_effort}"
    _fanout_register_session "$tid" "$cls" "$_resolved_pid" "$title" "false" "false" "terminal" \
      "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || _reg_rc=$?
    leadv2_active_set_worktree "$tid" "$_lane_dir" || true
    if [[ "$_reg_rc" -eq 3 ]]; then
      # FIX4: this script never spawned the resolved pid itself (osascript
      # handed it to Terminal/iTerm2), so there is no setsid process-group we
      # own -- kill only the specific resolved pid, never a group.
      log "WARN: ${tid} admission refused under lock (F6/FIX3) — killing spawned child pid=${_resolved_pid}"
      _fanout_kill_child "$_resolved_pid" "false"
    fi
  else
    log "WARN: could not resolve pid for task=${tid} within 10s — registering pid_pending=true"
    # No resolved pid to kill on refusal here -- pid_pending=true already
    # marks this row for the stale-sweeper's grace-window handling.
    _fanout_register_session "$tid" "$cls" "null" "$title" "false" "true" "terminal" \
      "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || true
    leadv2_active_set_worktree "$tid" "$_lane_dir" || true
  fi
}

# launch_tmux <tid> <cls> — one shared tmux session "leadv2", one WINDOW per
# task (never panes — panes get unreadable at 4+ tasks). Reuses the "leadv2"
# session if it already exists instead of spawning a second one. Output is
# piped to docs/handoff/<tid>/session.log so the supervisor can read it
# without attaching. Survives Terminal.app window close/quit (the exact
# failure LEAD-ANCHOR-01 exists to fix).
TMUX_SESSION_NAME="${LEADV2_FANOUT_TMUX_SESSION:-leadv2}"
declare -a TMUX_LAUNCHED_IDS=()

launch_tmux() {
  local tid="$1" cls="$2" lead_model="${3:-sonnet}" lead_effort="${4:-medium}"
  local risk_tags="${5:-}" class_reason="${6:-}"
  local provider="${7:-claude}" route_reason="${8:-}"
  local group_key="${9:-}"
  local window="$tid"
  local target="${TMUX_SESSION_NAME}:${window}"
  local task_dir="${PROJECT_ROOT}/docs/handoff/${tid}"
  mkdir -p "$task_dir"
  local logf="${task_dir}/session.log"
  : > "$logf"  # truncate/create so "non-empty after launch" is a real signal, not stale content

  # LANE-WORKTREE-ISOLATION-01: same ensure()-before-launch as launch_headless.
  local _lane_dir
  _lane_dir="$("${SCRIPT_DIR}/leadv2-lane-worktree.sh" ensure "$tid" "$cls" 2>>"$logf")"
  [[ -n "$_lane_dir" ]] || _lane_dir="$PROJECT_ROOT"
  leadv2_active_set_worktree "$tid" "$_lane_dir" || true

  # Some hosts (observed: no-tty parent shells with no pty anywhere in the
  # chain) run an intermittently unstable tmux server that can exit between
  # one window's creation and the next, independent of the new-window notty
  # fix below. Retry the whole ensure-session/window/send-keys sequence up
  # to 3 times, re-verifying with `has-session` after each attempt, before
  # falling back to pid_pending — cheap insurance, a healthy server no-ops
  # through this on attempt 1.
  local _tmux_attempt
  for ((_tmux_attempt = 1; _tmux_attempt <= 3; _tmux_attempt++)); do
    if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
      tmux new-session -d -s "$TMUX_SESSION_NAME" -n "$window" -c "$_lane_dir"
      log "tmux: created session '${TMUX_SESSION_NAME}' with window '${window}' (attempt ${_tmux_attempt})"
    else
      # Never reuse a window whose task is already registered live in
      # active.yaml — but that task never reaches LAUNCH in the selection
      # pass above (active_task_ids exclusion), so any window with this name
      # here is necessarily orphaned/stale. Recreate rather than reusing it.
      if tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -qx "$window"; then
        log "tmux: window '${window}' already exists in '${TMUX_SESSION_NAME}' (stale) — recreating"
        tmux kill-window -t "${TMUX_SESSION_NAME}:${window}" 2>/dev/null || true
      fi
      # `tmux new-window` on an already-detached session crashes the tmux
      # server ("server exited unexpectedly") when the CALLING process has
      # no controlling tty (isatty()==false) — reproduced deterministically
      # when this script itself runs from a tty-less parent (e.g. a /leadv2
      # lead's own headless tool-call shell fanning out more sessions).
      # `script -q /dev/null` gives the tmux client a synthetic pty, which
      # the tmux server needs to safely allocate the new window's pane;
      # verified fix across repeated runs. `new-session -d` above has never
      # reproduced this (only the SECOND+ window trips it), unwrapped.
      if [[ "$(uname -s)" == "Darwin" ]] && command -v script >/dev/null 2>&1 && ! tty -s 2>/dev/null; then
        script -q /dev/null tmux new-window -t "$TMUX_SESSION_NAME" -n "$window" -c "$_lane_dir" >/dev/null 2>&1 || true
      else
        tmux new-window -t "$TMUX_SESSION_NAME" -n "$window" -c "$_lane_dir" 2>/dev/null || true
      fi
      log "tmux: added window '${window}' to existing session '${TMUX_SESSION_NAME}' (attempt ${_tmux_attempt})"
    fi

    if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null \
       && tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -qx "$window"; then
      break
    fi
    log "WARN: tmux server unstable creating window '${window}' (attempt ${_tmux_attempt}/3) — retrying"
    sleep 0.3
  done

  local logf_q
  logf_q="$(printf -- '%q' "$logf")"
  tmux pipe-pane -o -t "$target" "cat >> ${logf_q}" 2>/dev/null || true

  # SUPERVISOR-RETRO-01 item 2: hand off to leadv2-session-runner.sh (same as
  # launch_headless) instead of `claude -p` directly, so tmux windows also
  # get --model/--effort pinning + resume-on-exit toward phase8-passed.flag.
  # daemon=false was previously registered here even though nothing acted as
  # a daemon; the runner makes that field honest.
  local cmd
  # MEDIUM-3 (fixround-tails): overridable so tests can point at a fast-exit stub instead
  # of mv/cp-swapping the CANONICAL leadv2-session-runner.sh in the source tree -- a
  # SIGINT/SIGTERM/SIGKILL during that swap window would leave the real runner replaced by
  # the stub with no restore (a RETURN trap does not fire on those signals), silently
  # no-oping every subsequent /leadv2 launch. Matches the LEADV2_FANOUT_WRITES_OVERLAP_BIN
  # idiom already used elsewhere in this file.
  local _runner="${LEADV2_SESSION_RUNNER_BIN:-${SCRIPT_DIR}/leadv2-session-runner.sh}"
  if [[ ! -x "$_runner" ]]; then
    log_error "leadv2-session-runner.sh missing/not executable at ${_runner} — refusing an unguarded one-shot launch"
    return 1
  fi
  printf -v cmd 'export LEADV2_DAEMON=1 LEADV2_ASYNC_QUESTIONS=1 LEADV2_FANOUT=1 LEADV2_TASK_ID=%q LEADV2_LEAD_MODEL=%q LEADV2_LEAD_EFFORT=%q LEADV2_SESSION_PROVIDER=%q LEADV2_RUNNER_FORCE_FRESH=%q LEADV2_PROJECT_ROOT=%q; exec %q' \
    "$tid" "$lead_model" "$lead_effort" "$provider" "$FORCE" "$PROJECT_ROOT" "$_runner"
  tmux send-keys -t "$target" "$cmd" C-m 2>/dev/null || true

  # tmux new-window hands back the pane's shell pid, not the exec'd `claude`
  # pid (and CLAUDE_BIN may itself be a wrapper script in tests) — resolve
  # the real pid the same way launch_windowed does, via pgrep polling.
  local _resolved_pid="" _attempt
  for ((_attempt = 0; _attempt < 40; _attempt++)); do
    _resolved_pid="$(_fanout_resolve_spawned_pid "$tid" || true)"
    [[ -n "$_resolved_pid" ]] && break
    sleep 0.25
  done

  local _reg_rc=0
  if [[ -n "$_resolved_pid" ]]; then
    log "tmux launch: task=${tid} window=${window} resolved pid=${_resolved_pid} provider=${provider} model=${lead_model}/${lead_effort}"
    _fanout_register_session "$tid" "$cls" "$_resolved_pid" "$window" "true" "false" "tmux" \
      "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || _reg_rc=$?
    leadv2_active_set_worktree "$tid" "$_lane_dir" || true
    if [[ "$_reg_rc" -eq 3 ]]; then
      # FIX4: kill the tmux window outright (cleaner than a bare pid kill for
      # this backend -- it also tears down the pane/shell, not just the
      # exec'd claude process) rather than leaving an orphaned, unregistered
      # window running against the ceiling that just refused it.
      log "WARN: ${tid} admission refused under lock (F6/FIX3) — killing tmux window ${target}"
      tmux kill-window -t "$target" 2>/dev/null || true
    fi
  else
    log "WARN: could not resolve pid for task=${tid} within 10s — registering pid_pending=true"
    # No resolved pid/confirmed window occupant to kill on refusal here --
    # pid_pending=true already marks this row for the stale-sweeper's
    # grace-window handling.
    _fanout_register_session "$tid" "$cls" "null" "$window" "true" "true" "tmux" \
      "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || true
    leadv2_active_set_worktree "$tid" "$_lane_dir" || true
  fi

  TMUX_LAUNCHED_IDS+=("$tid")
}

# _fanout_launch_full_cycle <tid> <cls> ... — the pre-FANOUT-CLASS-FUNNEL-01
# launch path (today's byte-identical behavior), factored out so both the
# funnel=0 rollback and the Heavy/Strategic path and the funnel's own
# opus/failure fallbacks all call the exact same code, never a re-typed copy.
_fanout_launch_full_cycle() {
  local tid="$1" cls="$2" lead_model="$3" lead_effort="$4" risk_tags="$5"
  local class_reason="$6" provider="$7" route_reason="$8" group_key="$9"
  case "$BACKEND" in
    headless) launch_headless "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key" ;;
    tmux)     launch_tmux "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key" ;;
    windows)  launch_windowed "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key" ;;
  esac
  # T-e (SUPERVISOR-AUDIT-01 tail): WRITES-CONFLICT-NOTIFY used to only fire on
  # launch_via_dispatch_code's single-worker funnel path -- a founder-picked task that
  # fell through to the full 9-phase cycle (Heavy/Strategic class, opus arm, or any
  # funnel decline/fallback) never got its `writes` stamped onto active.yaml and never
  # ran the overlap check, so a Heavy lane could silently collide with another live
  # lane's declared writes with no SUPERVISE-URGENT signal at all. Runs AFTER the
  # backend call (not before): each of launch_headless/launch_tmux/launch_windowed
  # registers the lane's real active.yaml row synchronously before returning, and
  # set_writes is a no-op create -- stamping onto a row that does not exist yet would
  # silently fail every time. Same flag, same notify-only semantics, same fail-open
  # (`|| true`) as launch_via_dispatch_code's own block above -- never blocks or delays
  # a launch that has already happened by the time this runs.
  # ALSO gated on FANOUT_CLASS_FUNNEL=="1" (not just the notify flag): _fanout_launch_
  # full_cycle is reached even under LEADV2_FANOUT_CLASS_FUNNEL=0 (today's total
  # rollback -- see this file's own header comment on _fanout_ensure_tasks_lib), and
  # that rollback's entire point is byte-identical behavior REGARDLESS of leadv2-
  # tasks-lib.sh's health. Under `set -euo pipefail`, sourcing a broken tasks-lib would
  # abort this whole script -- exactly the failure the =0 rollback exists to survive.
  if [[ "$FANOUT_CLASS_FUNNEL" == "1" && "${LEADV2_WRITES_CONFLICT_NOTIFY:-1}" != "0" ]]; then
    _fanout_ensure_tasks_lib
    local _fc_writes
    IFS=$'\t' read -r _fc_writes _ _ <<< "$(_fanout_task_lane_contract "$tid")"
    [[ "$_fc_writes" == "-" ]] && _fc_writes=""
    if [[ -n "$_fc_writes" ]]; then
      leadv2_active_set_writes "$tid" "$_fc_writes" >/dev/null 2>&1 || true
      local _fc_writes_overlap_bin="${LEADV2_FANOUT_WRITES_OVERLAP_BIN:-${SCRIPT_DIR}/leadv2-writes-overlap.sh}"
      if [[ -x "$_fc_writes_overlap_bin" ]]; then
        bash "$_fc_writes_overlap_bin" --task-id "$tid" --writes "$_fc_writes" \
          --project-root "$PROJECT_ROOT" --notify >/dev/null 2>&1 || true
      fi
    fi
  fi
}

# _fanout_mission_for_task <tid> -> mission text (title + note + origin), or
# empty if the row can't be found. Mirrors leadv2-backlog-pump.sh's own
# _mission_for_task() exactly (same tasks-lib call, same field precedence) so
# a task dispatched through this funnel gets the identical mission shape the
# auto-refill path already produces and has run in prod.
_fanout_mission_for_task() {
  local tid="$1" row
  row="$(leadv2_tasks_by_id "$tid" 2>/dev/null)" || { printf ''; return; }
  python3 -c "
import yaml, sys
items = yaml.safe_load(sys.argv[1]) or []
it = items[0] if items else {}
title = it.get('title', '')
note = it.get('note', '')
origin = it.get('origin', '')
parts = [p for p in (title, note) if p]
if origin:
    parts.append(f'(origin: {origin})')
print(' — '.join(parts) if parts else title)
" "$row" 2>/dev/null
}

# _fanout_task_lane_contract <tid> -> tab-separated "writes<TAB>acceptance_cmd<TAB>
# rollback_onestep(0|1)" (stdout). B4 fix (review-verdict-2.md finding B4,
# fix-round-2): the funnel used to forward only mission/kind/task-id to
# dispatch-code.sh, silently dropping a founder-authored task row's
# `writes`/`acceptance_cmd`/`rollback_onestep` -- fields dispatch-code.sh's
# --writes/--acceptance-cmd/--rollback-onestep flags already accept and act
# on (lane-shape gate, architect prepass file-count check, product-close
# rollback recording), just never populated from this caller. All three
# fields are OPTIONAL on a tasks.yaml row (the live 296-row queued population
# has none of them -- see NB2) -- an absent field yields an empty/"0" cell
# and launch_via_dispatch_code below omits that flag entirely, matching
# dispatch-code.sh's own direct-CLI-use defaults byte-for-byte.
_fanout_task_lane_contract() {
  local tid="$1" row
  # "-" is the on-the-wire empty marker (same convention as PLAN_TSV above):
  # `IFS=$'\t' read` treats tab as IFS-whitespace-class and collapses/strips
  # RUNS of it regardless of custom IFS, so an empty field emitted as a bare
  # tab is misparsed (verified: "\t\t0" reads back as a="0", b/c empty). The
  # bash consumer below undoes the marker on each field.
  row="$(leadv2_tasks_by_id "$tid" 2>/dev/null)" || { printf -- '-\t-\t0'; return; }
  python3 -c "
import yaml, sys
items = yaml.safe_load(sys.argv[1]) or []
it = items[0] if items else {}
writes = it.get('writes', '')
if isinstance(writes, (list, tuple, set)):
    writes = ','.join(str(w).strip() for w in writes if str(w).strip())
else:
    writes = str(writes or '').strip()
acceptance = str(it.get('acceptance_cmd', '') or '').strip()
rollback = it.get('rollback_onestep', False)
rollback_flag = '1' if rollback else '0'
def esc(s):
    s = s.replace('\t', ' ').replace('\n', ' ')
    return s or '-'
print('\t'.join((esc(writes), esc(acceptance), rollback_flag)))
" "$row" 2>/dev/null || printf -- '-\t-\t0'
}

# _leadv2_new_session_exec <logfile> <cmd...> — P0-FANOUT-EXIT-KILLS-ITS-OWN-
# LANES-01 portability fix. Spawns <cmd...> detached into a NEW OS session
# (real setsid(2)) so it neither dies when this script exits nor shares this
# script's process group -- a group-directed signal (e.g. the harness Bash
# tool reaping a timed-out command's whole group) never reaches it. stdin is
# /dev/null; stdout+stderr append to <logfile>.
#
# FANOUT-MACOS-LAUNCHER-01's prior claim ("nohup + trailing & still detaches
# from the controlling terminal") is true for terminal detachment but FALSE
# for group-directed signals -- nohup only sets SIG_IGN for SIGHUP, it never
# calls setsid(2). On Linux (prod VPS) the real `setsid` binary does this
# properly already. On macOS (no setsid binary) this falls back to a python3
# shim that calls os.setsid() for real before exec'ing the target -- python3
# is already a hard dependency elsewhere in this pipeline
# (leadv2-dispatch-code.sh). Only if BOTH are unavailable does this fall back
# to plain nohup, and that fallback is logged loudly, never silently, because
# it reproduces exactly the bug this function exists to fix.
#
# Echoes "<pid> <used_new_session:true|false>" on stdout -- the boolean has
# the SAME meaning _fanout_kill_child's <used_setsid> arg already expects
# (true => pid is also the new process-group leader, kill the group; false =>
# it shares the caller's group, kill only the pid). Caller must NOT background
# this call again: $! is already captured internally via the backgrounded
# subshell that execs the primitive, so an extra `&` at the call site would
# capture the wrong pid.
_leadv2_new_session_exec() {
  local logf="$1"; shift
  local pid used=false
  if command -v setsid >/dev/null 2>&1; then
    used=true
    ( exec setsid nohup "$@" </dev/null >>"$logf" 2>&1 ) &
    pid=$!
  elif command -v python3 >/dev/null 2>&1; then
    used=true
    ( exec python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
        "$@" </dev/null >>"$logf" 2>&1 ) &
    pid=$!
  else
    log_error "_leadv2_new_session_exec: neither setsid nor python3 available -- launching '$1' NOT session-detached; a caller-group signal (e.g. harness Bash-tool teardown) WILL still reach this child (FANOUT-MACOS-LAUNCHER-01 regression path)"
    ( exec nohup "$@" </dev/null >>"$logf" 2>&1 ) &
    pid=$!
  fi
  printf '%s %s\n' "$pid" "$used"
}

# _fanout_write_lane_terminal <tid> <landed|parked|refused|dead> <cause>
# [<evidence>] — records a terminal row for a lane that never got far enough
# to have its own dispatch-code.sh sig8 (pre-dispatch failures: launcher
# binary missing, handoff-ack timeout, launcher died before spawning a
# worker). Keys on "fanout-<tid>" rather than a sig8 -- the ledger's own
# write-terminal only requires a non-empty, non-colliding key, and a lane
# that dies before dispatch-code.sh assigns a sig8 has no other identifier
# (T0/decision-default in the architect prepass; lead did not override it).
_fanout_write_lane_terminal() {
  local tid="$1" terminal="$2" cause="$3" evidence="${4:-}"
  local ledger_bin="${LEADV2_FANOUT_DISPATCH_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-dispatch-ledger.sh}"
  if [[ ! -x "$ledger_bin" ]]; then
    log_error "dispatch ledger missing/not executable at ${ledger_bin} -- cannot record terminal for task=${tid} cause=${cause}"
    return 1
  fi
  bash "$ledger_bin" write-terminal "fanout-${tid}" "$tid" "$terminal" "$cause" "$evidence" "" >/dev/null 2>&1 \
    || log_error "write-terminal failed for task=${tid} terminal=${terminal} cause=${cause}"
}

# _fanout_launch_lane_detached <tid> <cls> <lead_model> <lead_effort>
# <risk_tags> <class_reason> <provider> <route_reason> <group_key> <label>
# <mission> <lane_writes> <lane_acceptance> <lane_rollback> <dispatch_bin> —
# P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01 default path (LEADV2_FANOUT_LANE_
# DETACH=1). Hands the (up to 840s) architect-prepass + worker-spawn call to
# leadv2-dispatch-code.sh off to a per-lane launcher script running in its own
# OS session. Kimi adds a 60s caller-side verdict window after spawn
# (overrideable). Fanout blocks only for a short handoff ack (LEADV2_FANOUT_LANE_
# ACK_TIMEOUT_SEC, default 15s) instead of the full synchronous call --
# letting fanout return promptly regardless of how many lanes are launched or
# how long any one prepass takes. The launcher (leadv2-fanout-lane-launcher.sh)
# owns everything past this handoff: running dispatch-code.sh, finalizing the
# active.yaml registration with the real worker pid, and -- via its own EXIT
# trap -- guaranteeing a terminal record if it dies before a worker exists.
# No ack within the timeout => the launcher is killed, the claim and lane
# reservation are released, and a `dead` terminal row is written here instead
# -- this lane is never left silently dangling.
_fanout_launch_lane_detached() {
  local tid="$1" cls="$2" lead_model="$3" lead_effort="$4" risk_tags="$5"
  local class_reason="$6" provider="$7" route_reason="$8" group_key="$9"
  local label="${10}" mission="${11}" lane_writes="${12}" lane_acceptance="${13}"
  local lane_rollback="${14}" dispatch_bin="${15}"

  local lane_sig_dir="${PROJECT_ROOT}/docs/handoff/fanout-lane-${tid}"
  mkdir -p "$lane_sig_dir"
  local mission_file="${lane_sig_dir}/mission.txt"
  printf '%s' "$mission" > "$mission_file"
  local lane_log="${lane_sig_dir}/launcher.log"
  : > "$lane_log"

  local launcher_bin="${LEADV2_FANOUT_LANE_LAUNCHER_BIN:-${SCRIPT_DIR}/leadv2-fanout-lane-launcher.sh}"
  if [[ ! -x "$launcher_bin" ]]; then
    log_error "leadv2-fanout-lane-launcher.sh missing/not executable at ${launcher_bin} -- releasing claim+reservation, recording terminal for task=${tid}"
    leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
    leadv2_active_unregister "$tid" >/dev/null 2>&1 || true
    _fanout_write_lane_terminal "$tid" dead "lane_launcher_bin_missing" "$launcher_bin"
    return
  fi

  local -a launcher_cmd=(env "LEADV2_PROJECT_ROOT=${PROJECT_ROOT}" "PROJECT_ROOT=${PROJECT_ROOT}"
    bash "$launcher_bin"
    --task-id "$tid" --class "$cls" --mission-file "$mission_file"
    --project-root "$PROJECT_ROOT" --sig-dir "$lane_sig_dir"
    --lead-model "$lead_model" --lead-effort "$lead_effort"
    --risk-tags "$risk_tags" --class-reason "$class_reason"
    --provider "$provider" --route-reason "$route_reason" --group-key "$group_key"
    --dispatch-bin "$dispatch_bin")
  [[ -n "$lane_writes" ]] && launcher_cmd+=(--writes "$lane_writes")
  [[ -n "$lane_acceptance" ]] && launcher_cmd+=(--acceptance-cmd "$lane_acceptance")
  [[ "$lane_rollback" == "1" ]] && launcher_cmd+=(--rollback-onestep)

  local lnse_out lnse_pid lnse_used_setsid
  lnse_out="$(_leadv2_new_session_exec "$lane_log" "${launcher_cmd[@]}" 9>&-)"
  lnse_pid="${lnse_out%% *}"
  lnse_used_setsid="${lnse_out#* }"

  log "lane launcher spawned: task=${tid} launcher_pid=${lnse_pid} used_setsid=${lnse_used_setsid} log=${lane_log}"

  local pid_file="${lane_sig_dir}/launcher.pid"
  local ack_timeout="${LEADV2_FANOUT_LANE_ACK_TIMEOUT_SEC:-15}"
  local deadline=$(( $(date +%s) + ack_timeout ))
  local acked_pid=""
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if [[ -f "$pid_file" ]]; then
      acked_pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [[ -n "$acked_pid" ]] && kill -0 "$acked_pid" 2>/dev/null; then
        log "lane launcher acked: task=${tid} launcher_pid=${acked_pid}"
        return
      fi
    fi
    sleep 0.2
  done

  log_error "lane launcher handoff timed out after ${ack_timeout}s for task=${tid} (launcher_pid=${lnse_pid:-<none>}) -- killing launcher, releasing claim+reservation, recording terminal"
  _fanout_kill_child "$lnse_pid" "$lnse_used_setsid"
  leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
  leadv2_active_unregister "$tid" >/dev/null 2>&1 || true
  _fanout_write_lane_terminal "$tid" dead "launcher_handoff_timeout" "$lane_log"
}

# launch_via_dispatch_code <tid> <cls> <lead_model> <lead_effort> <risk_tags>
# <class_reason> <provider> <route_reason> <group_key> <label> — the
# FANOUT-CLASS-FUNNEL-01 single-worker path for Light/Standard tasks. Claims
# the task (same leadv2_tasks_claim/--by convention leadv2-backlog-pump.sh
# already uses), builds a mission from tasks.yaml (falling back to the
# already-computed `label` if the row has no title/note), and hands it to
# leadv2-dispatch-code.sh -- the SAME single funnel leadv2-backlog-pump.sh
# uses, so this task now gets the identical architect-prepass + e2e gate +
# cross-provider review the auto-refill path has had all along (design-map.md
# row 2/4). Any non-launch outcome (opus arm, duplicate-sig refusal, spawn
# failure) either releases the claim or falls back to the full 9-phase cycle
# via _fanout_launch_full_cycle -- a founder-picked task is never silently
# dropped just because the light funnel declined it.
launch_via_dispatch_code() {
  # BLOCKING fix (review-verdict.md fanout.sh:1410-1426): lazy-load tasks-lib here
  # (only place this path needs it) -- see the =0 rollback comment above.
  _fanout_ensure_tasks_lib
  local tid="$1" cls="$2" lead_model="${3:-sonnet}" lead_effort="${4:-medium}"
  local risk_tags="${5:-}" class_reason="${6:-}"
  local provider="${7:-claude}" route_reason="${8:-}"
  local group_key="${9:-}" label="${10:-}"
  local dispatch_bin="${LEADV2_FANOUT_DISPATCH_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"

  if [[ ! -x "$dispatch_bin" ]]; then
    log_error "leadv2-dispatch-code.sh missing/not executable at ${dispatch_bin} -- refusing the single-worker funnel for ${tid}, falling back to full-cycle launch"
    _fanout_launch_full_cycle "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key"
    return
  fi

  local mission
  mission="$(_fanout_mission_for_task "$tid")"
  [[ -n "$mission" ]] || mission="$label"
  [[ -n "$mission" ]] || mission="task ${tid}"
  # dispatch-code.sh keys its dedup ledger on a content hash of the mission
  # text, not on tid -- fold tid into the content so the same title text on
  # two different tasks never collides, and so journaled/handoff artifacts on
  # the dispatch-code side stay traceable back to this founder-picked task.
  mission="Task ${tid}: ${mission}"

  if ! leadv2_tasks_claim "$tid" --by "fanout-class-funnel:${tid}" >/dev/null 2>&1; then
    log "single-worker funnel: task=${tid} could not be claimed (already claimed elsewhere) -- skipping this run"
    return
  fi

  # BLOCKING fix (review-verdict.md fanout.sh:1425-1459): dispatch-code.sh's own
  # bash invocation below is what actually SPAWNS the glm/codex/sonnet worker --
  # that used to happen before this script ever checked the lane cap, so a lost
  # cap race left an unregistered, uncounted worker running (log-only WARN, never
  # killed). Reserve the lane under lock FIRST (pid=null placeholder,
  # pid_pending=true) so the SAME admission check dispatch-code.sh's spawn can
  # never bypass runs before, not after, the worker exists. Any non-launch
  # outcome below releases this reservation via leadv2_active_unregister.
  local _reserve_rc=0
  _fanout_register_session "$tid" "$cls" "null" "dispatch-code: ${tid} (reserving)" "true" "true" "dispatch-code" \
    "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" || _reserve_rc=$?
  if [[ "$_reserve_rc" -eq 3 ]]; then
    log "single-worker funnel: task=${tid} lane admission refused under lock BEFORE dispatch (F6/FIX3 cap) -- releasing claim, not launched this run"
    leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
    return
  elif [[ "$_reserve_rc" -ne 0 ]]; then
    # NB1 fix (SUPERVISOR-AUDIT-01 fix-round-3, review-verdict-3.md): this used
    # to WARN and fall through to dispatch anyway -- a reservation write that
    # fails for any reason OTHER than a lost admission race (e.g. active.yaml's
    # lockfile path is unwritable/a directory) is not "no signal", it is "we
    # cannot account for this session at all". Fail CLOSED like the -eq 3
    # branch above: no dispatch, claim released, loud error.
    log_error "single-worker funnel: task=${tid} could not reserve a lane in active.yaml (rc=${_reserve_rc}) -- refusing to dispatch (fail-closed); releasing claim, not launched this run"
    leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
    return
  fi

  # BLOCKING fix (review-verdict.md fanout.sh:1410-1426): pass the founder task id
  # through so dispatch-code.sh/dispatch-product-close.sh can (a) journal a
  # dispatch-<sig8> <-> tid bridge for liveness, and (b) unclaim this SAME id when
  # the close gate finishes -- see leadv2-dispatch-product-close.sh's EXIT trap.
  # B4 fix (review-verdict-2.md): also forward writes/acceptance_cmd/
  # rollback_onestep when the founder task row carries them -- dispatch-code.sh
  # already implements --writes/--acceptance-cmd/--rollback-onestep, this caller
  # simply never read them off the task before now.
  local _lane_writes="" _lane_acceptance="" _lane_rollback="0"
  IFS=$'\t' read -r _lane_writes _lane_acceptance _lane_rollback <<< "$(_fanout_task_lane_contract "$tid")"
  [[ "$_lane_writes" == "-" ]] && _lane_writes=""
  [[ "$_lane_acceptance" == "-" ]] && _lane_acceptance=""

  # WRITES-CONFLICT-NOTIFY (SUPERVISOR-AUDIT-01 T-E, founder point: notify,
  # not hard-block): when this lane declares writes, (a) stamp them onto its
  # own just-reserved active.yaml row so a LATER lane can see them, then
  # (b) check them against every currently-alive lane's own declared writes
  # and, on overlap, journal + surface a SUPERVISE-URGENT pulse line. Dispatch
  # below proceeds unconditionally either way -- this never blocks or delays
  # launch. LEADV2_WRITES_CONFLICT_NOTIFY=0 (checked inside the overlap
  # script) makes the whole block a no-op, restoring today's active.yaml
  # shape and behavior byte-for-byte; the guard is duplicated here too so
  # the stamp write itself is skipped, not just the notify.
  if [[ "${LEADV2_WRITES_CONFLICT_NOTIFY:-1}" != "0" && -n "$_lane_writes" ]]; then
    leadv2_active_set_writes "$tid" "$_lane_writes" >/dev/null 2>&1 || true
    local _writes_overlap_bin="${LEADV2_FANOUT_WRITES_OVERLAP_BIN:-${SCRIPT_DIR}/leadv2-writes-overlap.sh}"
    if [[ -x "$_writes_overlap_bin" ]]; then
      bash "$_writes_overlap_bin" --task-id "$tid" --writes "$_lane_writes" \
        --project-root "$PROJECT_ROOT" --notify >/dev/null 2>&1 || true
    fi
  fi

  # P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01: default path from here on is the
  # detached per-lane launcher (see _fanout_launch_lane_detached above) --
  # everything below this branch (synchronous dispatch-code.sh call + case)
  # is preserved byte-identical and only runs when LEADV2_FANOUT_LANE_
  # DETACH=0, the one-flag rollback to today's behavior. The claim and the
  # pid=null/pid_pending=true reservation above already happened identically
  # on both paths -- only what happens AFTER that reservation diverges.
  if [[ "$LEADV2_FANOUT_LANE_DETACH" != "0" ]]; then
    _fanout_launch_lane_detached "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" \
      "$class_reason" "$provider" "$route_reason" "$group_key" "$label" \
      "$mission" "$_lane_writes" "$_lane_acceptance" "$_lane_rollback" "$dispatch_bin"
    return
  fi

  local -a dc_args=("$mission" --kind "fanout-class-funnel" --task-id "$tid")
  [[ -n "$_lane_writes" ]] && dc_args+=(--writes "$_lane_writes")
  [[ -n "$_lane_acceptance" ]] && dc_args+=(--acceptance-cmd "$_lane_acceptance")
  [[ "$_lane_rollback" == "1" ]] && dc_args+=(--rollback-onestep)

  local dc_out dc_rc=0
  dc_out="$(bash "$dispatch_bin" "${dc_args[@]}" 2>&1)" || dc_rc=$?

  case "$dc_rc" in
    0)
      local handle
      handle="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .*handle=\(.*\)$/\1/p' | tail -1)"
      log "single-worker funnel launch: task=${tid} class=${cls} model=${lead_model} handle=${handle:-<none>} -- $(printf '%s\n' "$dc_out" | tail -1)"
      # LANE ACCOUNTING (mission req #4): dispatch-code.sh does not write
      # active.yaml itself (it is out-of-pipeline, unaware of fanout's
      # lane caps) -- upsert the reservation above with the SAME function
      # fanout's own backends use, so a funnel launch counts against
      # hard_limit/light_max/standard_max exactly like a full-cycle child
      # would. Only the sonnet arm's handle is a real OS pid (dispatch-code.sh
      # normalizes it to bare PID=<n>); glm/codex handles are provider-
      # internal run/job ids, not killable pids -- register those with
      # pid=null. leadv2-stale-sweeper.sh only marks a null-pid row stale
      # after BOTH pid-dead AND last_pulse_at/started_at > 2h old, so this
      # is not evicted the instant it's written; see build-a.md open risks
      # for the long-tail (>2h background job) case.
      # The sonnet arm's raw handle is "PID=<n> SESSION_ID=<s>" (claude-
      # subsession.sh's own output, unnormalized -- dispatch-code.sh only
      # normalizes it to a bare PID INTERNALLY, for its own ledger, never on
      # this stdout line). Extract with the SAME sed pattern dispatch-code.sh's
      # _dispatch_normalize_handle uses, so this stays correct if that format
      # ever changes there. glm/codex handles never match -> pid stays null.
      local pid_val="null" extracted_pid
      extracted_pid="$(printf '%s' "$handle" | sed -n 's/^PID=\([0-9][0-9]*\).*/\1/p')"
      [[ -n "$extracted_pid" ]] && pid_val="$extracted_pid"
      # BLOCKING fix (review-verdict.md fanout.sh:1410-1426): record the REAL
      # dispatch-code.sh artifact directory as this row's log source instead of
      # the phase-cycle default (docs/leadv2/tasks/<tid>/pulse.md) -- the funnel
      # writes to docs/handoff/dispatch-<sig8>/ and never touches the former,
      # which is exactly why liveness could never find this path's log.
      local _dc_sig8 _dc_log_path=""
      _dc_sig8="$(printf '%s\n' "$dc_out" | sed -n 's/.*task=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)"
      [[ -n "$_dc_sig8" ]] && _dc_log_path="docs/handoff/dispatch-${_dc_sig8}/developer.stream.jsonl"
      local _reg_rc=0
      _fanout_register_session "$tid" "$cls" "$pid_val" "dispatch-code: ${tid}" "true" "false" "dispatch-code" \
        "$risk_tags" "$lead_model" "$lead_effort" "$class_reason" "$provider" "$route_reason" "$group_key" "$_dc_log_path" || _reg_rc=$?
      if [[ "$_reg_rc" -eq 3 ]]; then
        log "WARN: ${tid} admission refused under lock while finalizing the single-worker funnel's registry row (F6/FIX3) -- dispatch-code.sh already spawned this worker; it cannot be killed generically from here (arm-specific handle=${handle:-<none>}), lane cap is now over-subscribed by one until it finishes"
      fi
      # SD-LEDGER-SWEEP-HARDEN-01: dispatch-code.sh's own $$ (its ledger attempt token,
      # see spawn_worker's worker_spawned line) is only knowable once this synchronous
      # call has already returned, so it is stamped onto the row AFTER the finalize
      # register call above, never onto the earlier pre-spawn placeholder -- see
      # leadv2-active-registry.sh's set_attempt op doc comment for why that ordering
      # matters (the placeholder row gets replaced wholesale, not merged, once the real
      # pid is known). Best-effort like set_writes above: never blocks or fails launch.
      local _dc_attempt
      _dc_attempt="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .*attempt=\([^[:space:]]*\).*/\1/p' | tail -1)"
      if [[ -n "$_dc_attempt" ]]; then
        leadv2_active_set_attempt "$tid" "$_dc_attempt" >/dev/null 2>&1 || true
      fi
      ;;
    2)
      log "single-worker funnel: task=${tid} refused by dispatch-code.sh as a duplicate task-signature -- releasing claim, not launched this run (see dispatch ledger)"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      [[ "$_reserve_rc" -eq 0 ]] && leadv2_active_unregister "$tid" >/dev/null 2>&1
      ;;
    3)
      log "single-worker funnel: task=${tid} resolved to arm=opus (requires lead judgment, dispatch-code.sh never auto-dispatches it) -- releasing claim and falling back to full-cycle launch so the task is not silently dropped"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      [[ "$_reserve_rc" -eq 0 ]] && leadv2_active_unregister "$tid" >/dev/null 2>&1
      _fanout_launch_full_cycle "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key"
      ;;
    6)
      # BURN-GOVERNOR-01 (architect prepass §1.3 D3): the refusal was cheap on purpose
      # (no worker, no worktree, no ledger row) -- falling back to _fanout_launch_full_cycle
      # here would upgrade a refused-to-save-tokens lane into the single most expensive
      # path in the system, which is strictly worse than not dispatching at all. The
      # fallback is deliberately suppressed for rc=6, unlike every other refusal above.
      log "single-worker funnel: task=${tid} refused by dispatch-code.sh's burn gate (24h local token burn over hard cap) -- releasing claim, task parked to burn-deferred.jsonl, NOT falling back to full-cycle (that would upgrade a token-saving refusal into the most expensive launch path)"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      [[ "$_reserve_rc" -eq 0 ]] && leadv2_active_unregister "$tid" >/dev/null 2>&1
      _fanout_write_lane_terminal "$tid" parked "burn_hard_24h" ""
      ;;
    *)
      log_error "single-worker funnel: task=${tid} dispatch-code.sh failed (rc=${dc_rc}) -- releasing claim and falling back to full-cycle launch so the founder-picked task is not silently dropped"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      [[ "$_reserve_rc" -eq 0 ]] && leadv2_active_unregister "$tid" >/dev/null 2>&1
      _fanout_launch_full_cycle "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key"
      ;;
  esac
}

for i in "${!LAUNCH_IDS[@]}"; do
  tid="${LAUNCH_IDS[$i]}"
  cls="${LAUNCH_CLASSES[$i]}"
  provider="${LAUNCH_PROVIDERS[$i]:-claude}"
  lead_model="${LAUNCH_MODELS[$i]:-sonnet}"
  lead_effort="${LAUNCH_EFFORTS[$i]:-medium}"
  risk_tags="${LAUNCH_RISK_TAGS[$i]:-}"
  class_reason="${LAUNCH_REASONS[$i]:-}"
  route_reason="${LAUNCH_ROUTE_REASONS[$i]:-}"
  group_key="${LAUNCH_GROUP_KEYS[$i]:-}"
  label="${LAUNCH_LABELS[$i]:-}"
  cls_lower="$(printf '%s' "$cls" | tr '[:upper:]' '[:lower:]')"
  # MAJOR fix (review-verdict.md fanout.sh:1478-1494): dispatch-code.sh
  # re-resolves its own arm and silently ignores any provider/model this loop
  # already computed -- an explicit --provider/--lead-model request would be
  # dropped without notice for Light/Standard funnel tasks. Reject the funnel
  # for an explicit override instead (fall through to the full-cycle path,
  # which already honors --lead-model/--provider a few lines above this loop).
  _explicit_route_override=false
  [[ -n "$LEAD_MODEL_OVERRIDE" ]] && _explicit_route_override=true
  [[ "$PROVIDER_REQUEST" != "auto" ]] && _explicit_route_override=true
  if [[ "$FANOUT_CLASS_FUNNEL" == "1" && "$_explicit_route_override" == "false" && ( "$cls_lower" == "light" || "$cls_lower" == "standard" ) ]]; then
    launch_via_dispatch_code "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key" "$label"
  else
    if [[ "$FANOUT_CLASS_FUNNEL" == "1" && "$_explicit_route_override" == "true" && ( "$cls_lower" == "light" || "$cls_lower" == "standard" ) ]]; then
      log "task=${tid}: explicit --provider/--lead-model override present -- funnel cannot honor it (dispatch-code.sh re-resolves its own arm), routing via full-cycle launch instead"
    fi
    _fanout_launch_full_cycle "$tid" "$cls" "$lead_model" "$lead_effort" "$risk_tags" "$class_reason" "$provider" "$route_reason" "$group_key"
  fi
done

if [[ "${#TMUX_LAUNCHED_IDS[@]}" -gt 0 ]]; then
  log "tmux: attach to all sessions: tmux attach -t ${TMUX_SESSION_NAME}"
  for tid in "${TMUX_LAUNCHED_IDS[@]}"; do
    log "tmux: attach directly to ${tid}: tmux attach -t ${TMUX_SESSION_NAME} \\; select-window -t ${tid}"
  done
fi

exit 0
