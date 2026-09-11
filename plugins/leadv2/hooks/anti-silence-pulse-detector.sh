#!/usr/bin/env bash
# .claude/hooks/anti-silence-pulse-detector.sh — UserPromptSubmit hook
# ANTI-SILENCE-HEARTBEAT-01 / D4.
#
# SessionStart's arm-inject nag fires exactly once, before the lead has
# had any chance to act on it (D4). This hook re-checks the same PID
# marker on EVERY user turn and re-emits the identical nag whenever the
# pulse is missing or dead — so a pulse that silently died mid-session
# (e.g. process killed, worktree torn down) gets re-armed on the very
# next turn instead of staying dark indefinitely.
#
# Same idempotency check as anti-silence-pulse-arm-inject.sh (D3): a live
# pid means silence ({}), never a duplicate nag.
#
# Fail-safe: any error -> {}. Exit 0 always.
set -euo pipefail
trap 'printf "{}"; exit 0' ERR

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
# ── stdin: session_id + transcript_path (round 6 H2/H3) ──────────────────
# Same read-once-guarded pattern as .claude/hooks/leadv2-pulse-json.sh:58-64,
# and the same bash-regex-on-JSON-string extraction used there and in
# open-threads-anchor-inject.sh — this repo's hooks never jq/python a stdin
# field. A payload without these fields degrades to empty, never to an error.
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
#     carries neither env var (precedent: leadv2-pulse-json.sh).
if [[ -n "${LEADV2_ASYNC_QUESTIONS:-}" ]] || [[ -n "${LEADV2_TASK_ID:-}" ]] || [[ "$_tpath" == *"/subagents/"* ]]; then
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
_ARM_CMD="PULSE_PID_FILE=\\\"${PID_FILE}\\\" PULSE_HEARTBEAT_FILE=\\\"${HEARTBEAT_FILE}\\\" PULSE_LOG_FILE=\\\"${PULSE_LOG_FILE_PATH}\\\" ${PROJECT_ROOT}/scripts/anti-silence-pulse.sh"

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
_emit() {
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
block = sys.argv[1]
event_name = sys.argv[2]
if not block:
    print("{}")
else:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": block}}))
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
    _emit "$block" "UserPromptSubmit" || { printf '{}'; exit 0; }
    exit 0
  fi
fi

block="ANTI-SILENCE PULSE NOT ARMED (ANTI-SILENCE-HEARTBEAT-01): re-arm now — Bash(command=\"${_ARM_CMD}\", run_in_background=true) then Monitor its stdout (persistent=true). It was missing or had died; re-arm before continuing other work."

_emit "$block" "UserPromptSubmit" || { printf '{}'; exit 0; }
exit 0
