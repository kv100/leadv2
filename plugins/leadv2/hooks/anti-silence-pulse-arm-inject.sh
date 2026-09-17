#!/usr/bin/env bash
# plugins/leadv2/hooks/anti-silence-pulse-arm-inject.sh — SessionStart hook
# ANTI-SILENCE-HEARTBEAT-01 / D1,D2,D3.
# ONE-STATUS-MECHANISM-01 (founder order 2026-09-12): canonical home is the
# PLUGIN tree — a repo that keeps a local copy keeps it as a symlink to
# this file. The per-repo settings.json registration is gone; this single
# plugin registration covers every repo the plugin serves.
#
# A SessionStart hook cannot arm a Monitor itself (D1: one-shot process,
# additionalContext-only contract, always exit 0). What it CAN do is tell
# the lead, at the top of its very first turn, that its first tool call
# must be to arm the pulse — a Bash(run_in_background=true) run of
# anti-silence-pulse.sh, watched by the lead's own Monitor call on its
# stdout (D2).
#
# Idempotent (D3): checks the PID marker anti-silence-pulse.pid via
# kill -0 (pid_alive() pattern from leadv2-lane-liveness.sh). If a live
# pid is already there, this hook is silent ({}) — never a second pulse.
# Fail-safe: any error -> {} (byte-identical to no-hook). Exit 0 always.
set -euo pipefail
trap 'printf "{}"; exit 0' ERR

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# ONE-STATUS-MECHANISM-01: this hook lives in the PLUGIN tree, so the old
# repo-hook derivation SCRIPT_DIR/../.. names the plugin tree, not the
# session repo — the pid marker would land in the wrong docs/leadv2 and
# the nag would fire forever. The session repo is CLAUDE_PROJECT_DIR when
# the harness provides it, else the git toplevel of this process cwd
# (Claude Code runs hooks with cwd = the session project dir), else the
# plugin tree as a documented last resort.
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || true)}"
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PLUGIN_ROOT}}"
PROJECT_ROOT="$CLAUDE_PROJECT_DIR"

# ── stdin: session_id + transcript_path (round 6 H2/H3) ──────────────────
# Same read-once-guarded pattern as .claude/hooks/leadv2-pulse-json.sh:58-64
# — this repo's hooks never jq/python a stdin field. A payload without these
# fields degrades to empty, never to an error.
_stdin=""
if [[ ! -t 0 ]]; then read -r -d '' -t 2 _stdin 2>/dev/null || true; fi
_sid=""; _tpath=""
[[ "$_stdin" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && _sid="${BASH_REMATCH[1]}"
[[ "$_stdin" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && _tpath="${BASH_REMATCH[1]}"

# ── H3 (round 6): the pulse is for an INTERACTIVE lead session only ──────
# A dispatched/headless worker has no founder watching its terminal, so a
# pulse there is pure noise and can spawn a competing loop. Three
# independently-sufficient signals, each covering a gap the others miss:
#   LEADV2_ASYNC_QUESTIONS — exported into every headless full-cycle child
#     (the same check leadv2-supervisor-fanout-guard.sh already uses);
#   LEADV2_TASK_ID         — exported by claude-subsession.sh into every lane
#     / dev-worker subsession, which does NOT carry the var above;
#   transcript_path under /subagents/ — the in-process Agent-tool fork, which
#     carries neither env var (precedent: leadv2-pulse-json.sh);
#   LEADV2_PULSE_MODE=0    — the documented off switch. A fourth case the three
#     above do not cover: an UNATTENDED lead session (the VPS fleet), which is a
#     top-level session with no task id and no async-question flag, yet has no
#     human watching a chat to prove liveness to. Measured 2026-09-18: such a
#     session spent whole steps re-arming a Monitor on its own pulse file and
#     reasoning about the 1800s tick interval, having exported LEADV2_PULSE_MODE=0
#     and been ignored — the var was documented in the command file but read by
#     nothing on this path.
if [[ "${LEADV2_PULSE_MODE:-1}" == "0" ]] || [[ -n "${LEADV2_ASYNC_QUESTIONS:-}" ]] || [[ -n "${LEADV2_TASK_ID:-}" ]] || [[ "$_tpath" == *"/subagents/"* ]]; then
  printf '{}'
  exit 0
fi

# ── H2 (round 6): per-SESSION, never per-repo ────────────────────────────
# A repo-scoped marker meant that once ANY session armed the pulse, every
# other concurrent session got {} and no beats at all — the exact silence
# this task exists to remove, and the founder runs several /leadv2 sessions
# in one repo by design (docs/leadv2/single-lead-mode.md). session_id is the
# only identifier visible here that is stable for a whole session; $PPID is
# this hook invocation's parent, not a session handle.
# Pure-builtin sanitisation: a hook must never depend on PATH. An external
# tr/head here exits 127 under a broken PATH inside $( ), where the ERR trap
# cannot save it — the hook's own fail-safe test caught exactly that.
#
# round 3: session_id is a required top-level field of every real
# SessionStart/UserPromptSubmit hook payload (Claude Code hooks contract) --
# it is never empty on a genuine invocation. Two prior fallbacks were both
# wrong: $PPID (round 2) is this hook PROCESS's parent, which changes on
# every invocation, so the key rotates and every "already armed?" check
# starts from zero; a literal "default" (round 1) buckets every concurrent
# session into one shared marker file, so a second session reads the
# first session's PID as its own and goes silently silent. Neither is a
# session handle. An empty _sid can only mean a malformed/non-standard
# payload -- that is an error path, not a case to paper over with a
# shared or rotating key, so it degrades to the same silent {} as any
# other unrecognised-shape input rather than guessing.
_SESSION_KEY="${_sid//[^a-zA-Z0-9_-]/_}"
if [[ -z "$_SESSION_KEY" ]]; then
  printf '{}'
  exit 0
fi
PID_FILE="${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.${_SESSION_KEY}.pid"
HEARTBEAT_FILE="${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.${_SESSION_KEY}.heartbeat"
PULSE_LOG_FILE_PATH="${PROJECT_ROOT}/docs/leadv2/anti-silence-pulse.${_SESSION_KEY}.log"
# scripts/anti-silence-pulse.sh already supports fully independent per-instance
# files through these three env overrides (used throughout its unit suite), so
# H2 needs no change to the loop itself — only to what this hook tells the lead to run.
# ONE-STATUS-MECHANISM-01: the pulse lives in the plugin, canonically (the
# repo copy is a symlink to it). CLAUDE_PROJECT_DIR rides along so the
# pulse reads THIS session repo board even though the script lives in the
# plugin tree.
PULSE_SCRIPT="${PLUGIN_ROOT}/scripts/anti-silence-pulse.sh"
[[ -f "${PULSE_SCRIPT}" ]] || PULSE_SCRIPT="${PROJECT_ROOT}/scripts/anti-silence-pulse.sh"
_ARM_CMD="CLAUDE_PROJECT_DIR=\\\"${PROJECT_ROOT}\\\" PULSE_PID_FILE=\\\"${PID_FILE}\\\" PULSE_HEARTBEAT_FILE=\\\"${HEARTBEAT_FILE}\\\" PULSE_LOG_FILE=\\\"${PULSE_LOG_FILE_PATH}\\\" ${PULSE_SCRIPT}"

# H1 (round 8): an unverified takeover does not kill the old process -- it
# mints a new instance key and points PULSE_PID_FILE/HEARTBEAT_FILE/LOG_FILE
# at suffixed sibling files (scripts/anti-silence-pulse.sh's
# _resolve_current_files), so the zombie's continued stamps to the BASE
# heartbeat file can never be read as the live owner's freshness. This hook
# must resolve the same pointer before checking PID/heartbeat freshness, or
# it will keep reading the zombie's fresh base-file stamp forever and never
# nag about a wedged new loop underneath it. _ARM_CMD intentionally still
# names the BASE files: the arm command's job is to (re)claim the base
# identity, not to reach into whatever instance key happened to be current.
_POINTER_FILE="${PID_FILE%.pid}.current"
if [[ -f "$_POINTER_FILE" ]]; then
  _instance_key="$(cat "$_POINTER_FILE" 2>/dev/null || true)"
  _instance_key="${_instance_key//[^a-zA-Z0-9_]/}"
  if [[ -n "$_instance_key" ]]; then
    PID_FILE="${PID_FILE%.pid}.${_instance_key}.pid"
    HEARTBEAT_FILE="${HEARTBEAT_FILE%.heartbeat}.${_instance_key}.heartbeat"
    PULSE_LOG_FILE_PATH="${PULSE_LOG_FILE_PATH%.log}.${_instance_key}.log"
  fi
fi
INTERVAL_S="${LEADV2_ANTI_SILENCE_INTERVAL_S:-1800}"
HEARTBEAT_SLACK_S="${LEADV2_ANTI_SILENCE_HEARTBEAT_SLACK_S:-300}"

# round 4: SessionStart/UserPromptSubmit additionalContext must be nested
# under hookSpecificOutput.hookEventName -- the documented Claude Code hooks
# JSON output contract for these two event types. A prior round's
# top-level {"additionalContext": ...} (no hookSpecificOutput wrapper) is
# the shape the harness silently discards: round-4 review found the
# literal string ANTI-SILENCE in zero of 86 hook_additional_context
# transcript attachments even after this hook had fired repeatedly.
#
# HOOK-OUTPUT-BUDGET-UNMANAGED-01 round 3 (M1): this hook measured 1,064B
# armed (not the 2B its stub "{}" idle path suggested) and carried no cap at
# all -- same cap-at-source + overflow-to-file contract as
# feature-liveness-session-inject.sh / learnings-recent-inject.sh.
# LEADV2_HOOK_OVERFLOW_TRIGGER_BYTES is a TRIGGER threshold (default 2048B),
# not a hard ceiling -- the headline+note emitted when it's crossed is not
# itself bounded by this value. The cap applies to the NESTED round-4
# payload: every emit below goes out in the hookSpecificOutput shape.
HOOK_OUTPUT_CAP_BYTES="${LEADV2_HOOK_OVERFLOW_TRIGGER_BYTES:-2048}"
OVERFLOW_DIR="${PROJECT_ROOT}/docs/leadv2/hook-overflow"
OVERFLOW_FILE="${OVERFLOW_DIR}/anti-silence-pulse-arm-inject.log"

_emit() {
  python3 - "$1" "$2" "$HOOK_OUTPUT_CAP_BYTES" "$OVERFLOW_FILE" <<'PYEOF'
import json, os, sys
block = sys.argv[1]
event_name = sys.argv[2]
cap = int(sys.argv[3])
overflow_path = sys.argv[4]
if not block:
    print("{}")
    raise SystemExit(0)
payload = json.dumps({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": block}})
if len(payload.encode("utf-8")) > cap:
    os.makedirs(os.path.dirname(overflow_path), exist_ok=True)
    with open(overflow_path, "w", encoding="utf-8") as f:
        f.write(block + "\n")
    headline = block.splitlines()[0] if block.splitlines() else ""
    if len(headline) > 300:
        headline = headline[:300] + "\u2026"
    note = f"output capped ({len(payload)}B > {cap}B); full detail at {overflow_path}"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": f"{headline} | {note}"}}))
else:
    print(payload)
PYEOF
}

_pid_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# H1 (round 5): a live PID only proves the loop process exists. The
# heartbeat stamp (written by the loop itself, from inside the loop) only
# proves the loop is not wedged or dead -- it CANNOT prove a Monitor is still
# attached to its stdout, because a healthy loop keeps stamping fresh
# regardless of who (if anyone) is watching. Detached-Monitor-with-healthy-
# loop is a known, undetected gap from inside this repo; requiring BOTH a
# live PID AND a fresh heartbeat stamp before staying silent catches a
# wedged/dead loop, nothing more.
# H3 (round 5): read the interval the WRITER recorded in the heartbeat
# file, not this hook process's own env resolution of
# LEADV2_ANTI_SILENCE_INTERVAL_S -- the arm loop and this hook are two
# independent processes and can resolve that var differently. A
# single-field (stamp-only) file is the pre-H3 / rollout-gap format:
# fall back to this process's own env value, same as a missing file would.
_heartbeat_fresh() {
  [[ -f "$HEARTBEAT_FILE" ]] || return 1
  local line stamp interval now age
  line="$(cat "$HEARTBEAT_FILE" 2>/dev/null || true)"
  read -r stamp interval <<<"$line"
  [[ "$stamp" =~ ^[0-9]+$ ]] || return 1
  [[ "$interval" =~ ^[0-9]+$ ]] || interval="$INTERVAL_S"
  now="$(date +%s)"
  age=$(( now - stamp ))
  (( age >= 0 && age <= interval + HEARTBEAT_SLACK_S ))
}

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if _pid_alive "$pid"; then
    if _heartbeat_fresh; then
      printf '{}'
      exit 0
    fi
    block="ANTI-SILENCE PULSE ALIVE BUT WEDGED/DEAD (ANTI-SILENCE-HEARTBEAT-01): the pulse process (pid ${pid}) is running but its heartbeat stamp is stale, meaning the loop itself is wedged or dead -- this is NOT a detached-Monitor detector (that case is undetectable from inside this repo; a healthy loop keeps stamping fresh no matter who is watching). Re-arm now: Bash(command=\"${_ARM_CMD}\", run_in_background=true) then Monitor its stdout (persistent=true). A live process is not proof the founder is being notified."
    _emit "$block" "SessionStart" || { printf '{}'; exit 0; }
    exit 0
  fi
fi

block="ANTI-SILENCE PULSE NOT ARMED (ANTI-SILENCE-HEARTBEAT-01): your FIRST tool call this turn must be Bash(command=\"${_ARM_CMD}\", run_in_background=true), immediately followed by Monitor on its stdout with description \"anti-silence pulse\" and persistent=true. This is the only way a 30-minute never-silent heartbeat gets armed — a SessionStart hook cannot arm a Monitor itself. Do this before any other work."

_emit "$block" "SessionStart" || { printf '{}'; exit 0; }
exit 0
