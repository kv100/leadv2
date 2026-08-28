#!/usr/bin/env bash
# leadv2-gate1-prompt.sh — Gate 1 founder approval prompt.
#
# Usage: leadv2-gate1-prompt.sh <task_id> <class> <plan_summary> [risk]
#   risk: none|data|safety_publish_payments (optional 4th arg, or
#   LEADV2_GATE1_RISK env). safety_publish_payments (or "high"/"critical")
#   routes through the Heavy blocking path regardless of class.
#
# Exit codes:
#   0 — accepted
#   1 — declined
#   2 — timed_out_auto_accepted
#
# Logic (PHASE-DISCIPLINE-01 D4):
#   Heavy/Strategic/high-risk: NEVER auto-accept, in ANY mode (DRY_RUN and
#   BOT_MODE included). With LEADV2_ASYNC_QUESTIONS=1 the gate is a BLOCKING
#   async question via leadv2-ask.sh (founder answers /leadv2 reply; the
#   declared default option is decline, so a timeout never accepts).
#   Otherwise: blocking stdin read, no timeout.
#   Standard/Light/Trivial (non-high-risk):
#     LEADV2_DRY_RUN=1       → auto-accept immediately (no wait)
#     LEADV2_DAEMON=1        → use LEADV2_GATE1_AUTO_ACCEPT_SEC (default 5)
#     non-interactive stdin  → treat as daemon (5s timeout)
#     interactive            → 60s timeout
#   Journal/ledger outcome: gate1_auto_accepted (timeout) vs answered.

set -euo pipefail

task_id="${1:?Usage: leadv2-gate1-prompt.sh <task_id> <class> <plan_summary> [risk]}"
cls="${2:?class required}"
plan_summary="${3:?plan_summary required}"
risk="${4:-${LEADV2_GATE1_RISK:-none}}"

log() { printf -- '[gate1] %s\n' "$*" >&2; }

# [D-2] Ledger emit: gate1_decision event — fire-and-forget, never breaks the caller.
# lv2-ledger-emit.py itself never raises; the `|| true` here is belt-and-suspenders around
# the python3 invocation and payload build so a missing script/python never blocks Gate 1.
# PHASE-DISCIPLINE-01 D4: outcome is journaled gate1_auto_accepted vs answered
# (plus declined for rc=1) so a close audit can tell a founder "да" from a
# 5-second daemon timeout without reconstructing it from the rc alone.
_gate1_emit_ledger() {
  local _rc="$1" _outcome="${2:-}"
  local _root="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local _emit="${_root}/.claude/scripts/lv2-ledger-emit.py"
  [[ -f "$_emit" ]] || _emit="$HOME/.claude/scripts/lv2-ledger-emit.py"
  [[ -f "$_emit" ]] || return 0
  local _payload
  _payload=$(python3 -c 'import json,sys; print(json.dumps({"event":"gate1_decision","task_id":sys.argv[1],"rc":int(sys.argv[2]),"outcome":sys.argv[3]}))' "$task_id" "$_rc" "$_outcome" 2>/dev/null) || return 0
  [[ -n "$_payload" ]] && { LEADV2_PROJECT_ROOT="$_root" python3 "$_emit" "$_payload" 2>/dev/null || true; }
  return 0
}

# Register task into active.yaml so recovery hooks and pre-compact checkpoint can find it.
# Uses the active-registry source-able script; falls back to direct YAML write on error.
_gate1_register_active() {
  local _registry
  _registry="$(dirname "${BASH_SOURCE[0]}")/leadv2-active-registry.sh"
  local _yaml_dir="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/docs/leadv2"
  mkdir -p "$_yaml_dir"
  if [[ -f "$_registry" ]]; then
    LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" \
      source "$_registry" \
      && leadv2_active_register "$task_id" "${cls:-Standard}" "$(pwd)" "" "false" \
      && { log "registered task in active.yaml via registry"; return 0; } \
      || { log "WARNING: registry register failed — falling back to direct write"; true; }
  fi
  # Fallback: write minimal session row directly.
  # Compute durable pid in shell first so the python subprocess doesn't register
  # os.getpid() (a short-lived process the sweep would drop immediately).
  local _yaml="${_yaml_dir}/active.yaml"
  local _ts _durable_pid _fb_registry
  _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  _fb_registry="$(dirname "${BASH_SOURCE[0]}")/leadv2-active-registry.sh"
  if [[ -f "$_fb_registry" ]]; then
    # Source just to get _lv2_durable_pid function; suppress set -euo noise on source
    # lean: guard via subshell to avoid polluting current env — upgrade when registry is always loaded
    _durable_pid="$(bash -c "source \"$_fb_registry\" 2>/dev/null; _lv2_durable_pid" 2>/dev/null || printf -- '%s' "$PPID")"
  else
    _durable_pid="$PPID"
  fi
  python3 - "$_yaml" "$task_id" "${cls:-Standard}" "$_ts" "${_durable_pid}" <<'PYEOF' 2>/dev/null || true
import sys, os, fcntl, tempfile
try:
    import yaml
except ImportError:
    sys.exit(0)
yaml_path, task_id, cls, ts, durable_pid_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
try:
    durable_pid = int(durable_pid_str)
except ValueError:
    durable_pid = None
lock_path = yaml_path + ".lock"
os.makedirs(os.path.dirname(yaml_path), exist_ok=True)
lock_fd = open(lock_path, "a+")
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    data = {}
    if os.path.exists(yaml_path):
        with open(yaml_path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    if "sessions" not in data or data["sessions"] is None:
        data["sessions"] = []
    existing = next((s for s in data["sessions"] if s.get("task_id") == task_id), None)
    if not existing:
        data["sessions"].append({
            "session_id": "s-{}-{}-{}".format(
                ts.replace(':', '').replace('-', ''), durable_pid or os.getpid(), os.getpid()
            ),
            "task_id": task_id,
            "phase": "build",
            "class": cls,
            "gate1_status": "approved",
            "started_at": ts,
            "pid": durable_pid,
            "stale": False,
        })
    d = os.path.dirname(yaml_path)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tf:
            yaml.dump(data, tf, default_flow_style=False, sort_keys=False)
        os.replace(tmp, yaml_path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
PYEOF
  log "registered task in active.yaml (fallback direct write, durable_pid=${_durable_pid})"
}

# On accept: capture context.yaml SHA and write Gate 1 sentinel for C2 guard.
_gate1_accept() {
  local _ctx="docs/handoff/${task_id}/context.yaml"
  if [[ -f "$_ctx" ]]; then
    local _sha; _sha=$(sha256sum "$_ctx" 2>/dev/null | awk '{print $1}' || true)
    local _state="docs/leadv2/tasks/${task_id}/STATE.md"
    if [[ -f "$_state" ]]; then
      grep -q "^gate1_context_sha:" "$_state" 2>/dev/null \
        || printf -- '\ngate1_context_sha: %s\n' "$_sha" >> "$_state"
    fi
  fi
  # Write Gate 1 sentinel — required by leadv2-gate-artifact-guard.sh (C2)
  touch "docs/handoff/${task_id}/.gate1-passed" 2>/dev/null || true
  # PHASE-DISCIPLINE-01 D2 step 2: bind this accept to the admission receipt
  # so a Phase-4 re-entry through dispatch-code's pre-build guard can assert
  # SAME-TASK plan+gate1 records (leadv2-phase-record.sh under the receipt's
  # sig8). The receipt carries task_id, so a dispatch dir minted for THIS task
  # is the only one that can match — a foreign task's records never satisfy
  # the re-entry. All writes pinned to LEADV2_PROJECT_ROOT (control plane):
  # this script frequently runs with cwd = a lane worktree, and dispatch-code
  # asserts against the shared root.
  local _g_root _g_receipt _g_sig8 _g_pr
  _g_root="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  _g_receipt="$(grep -l -E "^task_id:[[:space:]]*${task_id}\$" "${_g_root}"/docs/handoff/dispatch-*/admission-receipt.yaml 2>/dev/null | head -1 || true)"
  _g_pr="$(dirname "${BASH_SOURCE[0]}")/leadv2-phase-record.sh"
  if [[ -n "$_g_receipt" && -x "$_g_pr" ]]; then
    _g_sig8="$(basename "$(dirname "$_g_receipt")")"   # dispatch-<sig8> -> <sig8>
    _g_sig8="${_g_sig8#dispatch-}"
    mkdir -p "${_g_root}/docs/handoff/dispatch-${_g_sig8}" 2>/dev/null || true
    # phase-record's gate1 verify requires a NON-empty sentinel; the legacy
    # touch above stays for the artifact guard, the mirrored one carries body.
    printf 'gate1 accepted task=%s class=%s risk=%s at=%s\n' \
      "$task_id" "$cls" "$risk" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      >"${_g_root}/docs/handoff/dispatch-${_g_sig8}/.gate1-passed" 2>/dev/null || true
    LEADV2_PROJECT_ROOT="$_g_root" bash "$_g_pr" record "$_g_sig8" classify --task-id "$task_id" >/dev/null 2>&1 || true
    if [[ -s "${_g_root}/docs/handoff/${task_id}/context.yaml" ]]; then
      cp -f "${_g_root}/docs/handoff/${task_id}/context.yaml" \
        "${_g_root}/docs/handoff/dispatch-${_g_sig8}/context.yaml" 2>/dev/null || true
      LEADV2_PROJECT_ROOT="$_g_root" bash "$_g_pr" record "$_g_sig8" plan \
        --task-id "$task_id" --artifact "docs/handoff/dispatch-${_g_sig8}/context.yaml" >/dev/null 2>&1 || true
    fi
    LEADV2_PROJECT_ROOT="$_g_root" bash "$_g_pr" record "$_g_sig8" gate1 \
      --task-id "$task_id" --artifact "docs/handoff/dispatch-${_g_sig8}/.gate1-passed" >/dev/null 2>&1 || true
  fi
  # Register task in active.yaml — root fix for post-/compact amnesia (C-1 R4)
  _gate1_register_active
}

# ── Heavy / Strategic / high-risk: blocking, NEVER auto-accept ────────────
# PHASE-DISCIPLINE-01 D4: this branch runs BEFORE the DRY_RUN/BOT_MODE
# auto-accepts — "no timeout acceptance in any mode" includes those. With
# LEADV2_ASYNC_QUESTIONS=1 (headless full-cycle children) the gate is a
# BLOCKING async question via leadv2-ask.sh; the declared default option is
# decline, so an ask timeout parks the task rather than accepting.
_gate1_heavy_like=false
case "${cls,,}" in
  heavy|strategic) _gate1_heavy_like=true ;;
esac
case "${risk,,}" in
  safety_publish_payments|high|critical) _gate1_heavy_like=true ;;
esac

if [[ "${_gate1_heavy_like}" == "true" ]]; then
  if [[ "${LEADV2_DRY_RUN:-0}" == "1" || "${LEADV2_BOT_MODE:-0}" == "1" ]]; then
    log "heavy/high-risk gate: auto-accept modes are IGNORED for class=${cls} risk=${risk} — blocking question required (D4)"
  fi
  if [[ "${LEADV2_ASYNC_QUESTIONS:-0}" == "1" ]]; then
    _gate1_ask_bin="$(dirname "${BASH_SOURCE[0]}")/leadv2-ask.sh"
    if [[ -x "${_gate1_ask_bin}" ]]; then
      printf -- '\n> Gate 1 — HEAVY/high-risk (%s/%s). Blocking founder question.\n' "$cls" "$risk"
      printf -- 'задача: %s\nплан: %s\n\n' "$task_id" "$plan_summary"
      _gate1_choice="$(bash "${_gate1_ask_bin}" "${task_id}" \
        "Gate-1 (class=${cls} risk=${risk}): принять план? ${plan_summary}" \
        --option "go|принять план и продолжить full-cycle" \
        --option "n|отклонить план" \
        --default-option "n" 2>/dev/null || printf 'n')"
      case "${_gate1_choice}" in
        go)
          log "accepted by founder (heavy, async question)"
          _gate1_accept
          _gate1_emit_ledger 0 answered
          exit 0
          ;;
        *)
          log "declined by founder (heavy, async question)"
          _gate1_emit_ledger 1 declined
          exit 1
          ;;
      esac
    fi
    # ask binary missing: fall through to the blocking stdin read below —
    # still no auto-accept, but a headless caller with no stdin will hang;
    # that is the documented D4 failure shape (park, not accept).
  fi
  printf -- '\n> Gate 1 — HEAVY task. Explicit да/go required.\n'
  printf -- 'задача: %s\nплан: %s\n\n' "$task_id" "$plan_summary"
  printf -- 'принять? [да/go/n]: '
  read -r answer
  case "${answer,,}" in
    да|go|y|yes|d)
      log "accepted by founder (heavy)"
      _gate1_accept
      _gate1_emit_ledger 0 answered
      exit 0
      ;;
    *)
      log "declined by founder"
      _gate1_emit_ledger 1 declined
      exit 1
      ;;
  esac
fi

# ── DRY_RUN: immediate auto-accept ────────────────────────────────────────
if [[ "${LEADV2_DRY_RUN:-0}" == "1" ]]; then
  log "DRY_RUN mode — auto-accepted immediately"
  printf -- 'план: %s. [DRY-RUN — авто-принятие]\n' "$plan_summary"
  _gate1_accept
  _gate1_emit_ledger 2 gate1_auto_accepted
  exit 2
fi

# ── BOT_MODE: immediate auto-accept (Telegram bot, headless claude -p) ────
if [[ "${LEADV2_BOT_MODE:-0}" == "1" ]]; then
  log "BOT_MODE — auto-accepted immediately"
  printf -- 'Gate 1: auto-accepted (bot mode). plan: %s\n' "$plan_summary"
  _gate1_accept
  _gate1_emit_ledger 2 gate1_auto_accepted
  exit 2
fi

# ── Standard / Light / Trivial: determine timeout ─────────────────────────
# Determine if daemon or non-interactive
is_daemon=false
if [[ "${LEADV2_DAEMON:-0}" == "1" ]]; then
  is_daemon=true
elif [[ ! -t 0 ]]; then
  is_daemon=true  # non-interactive stdin → treat as daemon
fi

if [[ "$is_daemon" == "true" ]]; then
  timeout_sec="${LEADV2_GATE1_AUTO_ACCEPT_SEC:-5}"
else
  timeout_sec=60
fi

# ── Print prompt ───────────────────────────────────────────────────────────
printf -- '\nплан: %s. авто-принятие через %ss. давай? [да/go/n] ' \
  "$plan_summary" "$timeout_sec"

# ── Read with timeout ──────────────────────────────────────────────────────
answer=""
if read -r -t "$timeout_sec" answer 2>/dev/null; then
  # Got a response within timeout
  case "${answer,,}" in
    да|go|y|yes|d)
      log "accepted by founder"
      _gate1_accept
      _gate1_emit_ledger 0 answered
      exit 0
      ;;
    n|no|нет)
      log "declined by founder"
      _gate1_emit_ledger 1 declined
      exit 1
      ;;
    *)
      log "unrecognized input '$answer' — treating as declined"
      _gate1_emit_ledger 1 declined
      exit 1
      ;;
  esac
else
  # Timeout
  printf -- '\n'
  log "Gate 1 auto-accepted (timeout ${timeout_sec}s)"
  _gate1_accept
  _gate1_emit_ledger 2 gate1_auto_accepted
  exit 2
fi
