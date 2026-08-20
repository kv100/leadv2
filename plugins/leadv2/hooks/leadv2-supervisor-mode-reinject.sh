#!/usr/bin/env bash
# hooks/leadv2-supervisor-mode-reinject.sh — PostCompact hook
# (SUPERVISOR-HARDENING-01 item 1, supersedes SUPERVISOR-FANOUT-GUARD-01's
# repo-local reinject).
#
# COMPACT-SURVIVAL half of the supervisor guard. A compact wipes the model's
# memory that it is supervising; the shared leadv2-postcompact-goal-reinject
# surfaces the open-threads header but sits behind a 60-line cap and can be
# truncated. This hook checks the LIVE SUPERVISOR SENTINEL directly and emits
# a short, dedicated SUPERVISOR MODE block as PostCompact stdout — injected
# verbatim into the post-compact context window.
#
# THE BUG THIS FIXES (root cause of session e9ca8660, 11.5h with zero
# BROAD_STATUS): there are TWO supervisor markers with different lifecycles,
# and the prior version of this hook only honoured one.
#   • `.supervise-active`  — written by `leadv2 supervise`; control-plane JSON
#     {pid,pid_birth,started_at}. A `/leadv2 supervise` session has ONLY this.
#   • `SUPERVISOR-MODE.on` — a legacy repo-relative marker the PreToolUse
#     fanout-guard still keys on (presence only, no PID).
# The prior hook checked only `SUPERVISOR-MODE.on`, so every supervise session
# got ZERO reinject after compact. This version honours BOTH (primary A,
# legacy B) and PID-checks the primary.
#
# BLOCK = a POINTER, not a copy: names plugins/leadv2/docs/supervisor-role.md
# as the role definition, then the three things a re-synthesised context
# cannot re-derive — (i) the status-beat format contract, (ii) the dispatch
# constraint, (iii) the live sentinel + how to turn it off. Kept <=35 lines:
# PostCompact stdout competes with the active-task restore block (60-line cap).
#
# FAIL-OPEN: any error ⇒ exit 0, empty stdout. Never wedge a session start.
# Kill-switch: LEADV2_SUPERVISOR_REINJECT=0.
set -o pipefail
trap 'exit 0' ERR

[[ "${LEADV2_SUPERVISOR_REINJECT:-1}" == "0" ]] && exit 0

# ── Resolve project root ──────────────────────────────────────────────────
# PostCompact passes a JSON object on stdin with a `cwd` field; fall back to
# CLAUDE_PROJECT_DIR then pwd. Never block on stdin.
_ROOT=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then _ROOT="$CLAUDE_PROJECT_DIR"; fi
if [[ -z "$_ROOT" ]]; then
  _INPUT="$(cat 2>/dev/null || true)"
  _ROOT="$(printf '%s' "$_INPUT" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    cwd = (d or {}).get("cwd") or ""
    if cwd: print(cwd)
except Exception:
    pass
' 2>/dev/null || true)"
fi
[[ -z "$_ROOT" ]] && _ROOT="$PWD"
export PROJECT_ROOT="$_ROOT"

# ── Resolve leadv2-state-path.sh resolver ─────────────────────────────────
_RESOLVER=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
  _RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
elif [[ -f "${_ROOT}/.claude/scripts/leadv2-state-path.sh" ]]; then
  _RESOLVER="${_ROOT}/.claude/scripts/leadv2-state-path.sh"
else
  _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _RESOLVER="${_DIR}/../scripts/leadv2-state-path.sh"
fi
[[ -x "$_RESOLVER" ]] || exit 0

# ── Resolve leadv2_dir (repo-relative, for the legacy marker only) ─────────
_LEADV2_DIR="$(python3 -c "
import sys, re
try:
    for line in open(sys.argv[1]):
        m = re.match(r\"^\s*leadv2_dir\s*:\s*['\\\"]*([\w/._-]+)['\\\"]*(\s.*)?\$\", line)
        if m:
            print(m.group(1)); sys.exit(0)
except Exception:
    pass
print('docs/leadv2')
" "${_ROOT}/.claude/leadv2-overrides/state-paths.yaml" 2>/dev/null || printf 'docs/leadv2')"

# ── BRANCH A (primary): live .supervise-active with a live PID ─────────────
# Same sentinel + os.kill(pid,0) liveness reader as leadv2-supervisor-guard.sh
# (:144-160). A supervise session has only this marker.
_ACTIVE_SENTINEL="$(PROJECT_ROOT="$_ROOT" "$_RESOLVER" --no-link .supervise-active 2>/dev/null || true)"
_BRANCH=""
_ACTIVE_PID=""
if [[ -n "$_ACTIVE_SENTINEL" && -f "$_ACTIVE_SENTINEL" ]]; then
  _INFO="$(python3 -c "
import sys, json, os
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        sys.exit(0)
    os.kill(int(pid), 0)
    print(int(pid))
except Exception:
    sys.exit(0)
" "$_ACTIVE_SENTINEL" 2>/dev/null || true)"
  if [[ -n "$_INFO" ]]; then
    _BRANCH="A"
    _ACTIVE_PID="$_INFO"
  fi
fi

# ── BRANCH B (legacy): repo-relative SUPERVISOR-MODE.on (presence only) ────
# Kept because the PreToolUse fanout-guard hard-denies worker spawns while this
# marker exists; dropping B would leave a post-compact model denied with no
# explanation. Known hazard (stale-supervisor-markers-block-workers): a stale
# SUPERVISOR-MODE.on re-asserts supervisor mode forever — so B's block carries
# the `rm` off-switch line verbatim and a (legacy marker) label.
_LEGACY_MARKER="${_ROOT}/${_LEADV2_DIR}/SUPERVISOR-MODE.on"
if [[ -z "$_BRANCH" && -f "$_LEGACY_MARKER" ]]; then
  _BRANCH="B"
fi

# Neither marker live → silent no-op.
[[ -n "$_BRANCH" ]] || exit 0

if [[ "$_BRANCH" == "A" ]]; then
  _WHY="(.supervise-active live, pid=${_ACTIVE_PID})"
  _OFF="Turn supervisor mode OFF: end the supervise session, or rm ${_ACTIVE_SENTINEL}"
else
  _WHY="(legacy marker ${_LEADV2_DIR}/SUPERVISOR-MODE.on exists)"
  _OFF="Turn supervisor mode OFF: rm ${_LEADV2_DIR}/SUPERVISOR-MODE.on"
fi

# ── Emit the role block (<=35 lines, pointer not copy) ─────────────────────
cat <<EOF
<supervisor-mode>
SUPERVISOR MODE IS ON ${_WHY}.
Role definition: plugins/leadv2/docs/supervisor-role.md (read it for the full
contract). You are the SUPERVISOR, not a hand-orchestrator.

Status beat: every ~30 min leadv2-broad-status.sh appends a [BROAD_STATUS]
block to the supervise loop log and emits one BROAD_STATUS_READY line. Relay
when your URGENT-filtered watcher wakes you on it — RELAY=full: paste
docs/leadv2/founder-status.md verbatim, never compose one; RELAY=none: relay
only that single beat line, verbatim, and do not read the file. Narration is
model-generated prose about its own work; the pulse is a verbatim relay of a
plugin-generated artifact — never a CronCreate job; the beat is plugin-owned.
Your only chat outputs are: the 5-min pulse line, that BROAD_STATUS_READY
relay, an AskUserQuestion with options, and silence. End every BROAD_STATUS
block with a BROAD_STATUS_END line.

Dispatch constraint: ALL work goes out as child /leadv2 sessions via
  bash .claude/scripts/leadv2-fanout.sh --tasks <id1,id2> --tmux
Each child runs the full 8-phase pipeline (plan→gate→build→review→deploy→verify→close)
with its OWN critic + Codex review + live-verify.
BANNED (a PreToolUse guard hard-denies these while the marker is live):
Agent(developer|postgres-pro|frontend-developer|devops-engineer), and
Bash glm-coder.sh bg / omp-task.sh.
Allowed: leadv2-fanout.sh, leadv2-lanes-snapshot.sh, read-only probes,
Explore/general-purpose. One-off override: SUPERVISOR_ALLOW_WORKER=<reason>.

${_OFF}
</supervisor-mode>
EOF
exit 0
