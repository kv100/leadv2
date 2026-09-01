#!/usr/bin/env bash
# hooks/lib/leadv2-hook-session-kind.sh — BEAT-LOOP-ORPHANS-01
#
# One shared predicate deciding whether the CURRENT session is the founder's
# lead session or a headless worker (glm-coder / freepool-coder / kimi-coder /
# claude-subsession). Every hook or dispatcher path that ARMS a persistent
# loop (single-lead beat hook, dispatch-code's lane-pulse-watch and
# single-lead-beat-loop arms) must call this first and exit/return 0 silently
# for `worker` — a worker session's plugin hooks fire exactly like a lead's
# (SessionStart/UserPromptSubmit/Stop), so without this gate every headless
# run arms its own beat/watch loop that has no lead left to disarm it when the
# worker process exits (measured 2026-09-01 21:50: 53 orphaned loops, load 244).
#
# Usage: source this file, then:
#   kind="$(leadv2_hook_session_kind "$TRANSCRIPT_PATH")"   # lead | worker | unknown
#
# Evidence checked, in order (first match wins):
#   0. LEADV2_SESSION_KIND pin (lead|worker|unknown) — test seam, and an
#      escape hatch for a caller that knows better than the heuristic.
#   1. LEADV2_WORKER_ARM=1 — exported by glm-coder.sh / freepool-coder.sh /
#      kimi-coder.sh around every claude spawn.
#   2. LEADV2_SUBSESSION_ROLE non-empty and != "lead" — exported by
#      claude-subsession.sh.
#   3. transcript path under docs/handoff/ or a *-runs/ directory — the shape
#      every worker session's transcript is written under.
#   4. non-empty transcript path with no worker evidence -> lead.
# Anything matching none of the above (no transcript, no env markers) is
# `unknown` — callers FAIL OPEN (arm, but journal loop_armed_by_unknown_session)
# rather than silently starving a lead session whose evidence the predicate
# does not yet cover.
#
# CLAUDE_CODE_ENTRYPOINT is deliberately NOT a classifier here: the live probe
# on 2026-09-01 showed the interactive lead session running with
# CLAUDE_CODE_ENTRYPOINT=sdk-cli, and no verified value separates `claude -p`
# workers from it — so gating on it could starve the real lead. It is recorded
# in the arm journal (leadv2_loop_arm_journal) for future tuning instead.
#
# The same file also carries the loop-owner liveness helpers (rule 2 of
# BEAT-LOOP-ORPHANS-01): a loop records its owner session id + owner pid at
# arm time and exits when the owner is gone — see leadv2_loop_owner_record /
# leadv2_loop_owner_check.
#
# Bash 3.2 compatible (no assoc arrays, no ${var,,}).

leadv2_hook_session_kind() {  # <transcript_path> -> prints lead|worker|unknown
  local transcript="${1:-}"

  case "${LEADV2_SESSION_KIND:-}" in
    lead|worker|unknown) printf '%s\n' "$LEADV2_SESSION_KIND"; return 0 ;;
  esac

  if [[ "${LEADV2_WORKER_ARM:-0}" == "1" ]]; then
    printf 'worker\n'
    return 0
  fi

  local sub_role="${LEADV2_SUBSESSION_ROLE:-}"
  if [[ -n "$sub_role" && "$sub_role" != "lead" ]]; then
    printf 'worker\n'
    return 0
  fi

  if [[ -n "$transcript" ]]; then
    case "$transcript" in
      */docs/handoff/*|*-runs/*)
        printf 'worker\n'
        return 0
        ;;
      *)
        printf 'lead\n'
        return 0
        ;;
    esac
  fi

  printf 'unknown\n'
  return 0
}

# leadv2_loop_owner_pid -> prints the nearest ancestor pid running the claude
# harness, or 0 when none is found. Hooks are direct children of claude, so
# for hook-armed loops $PPID would do; dispatcher-armed loops (nohup from
# leadv2-dispatch-code.sh) sit under the Bash-tool shell chain, which is
# short-lived — walking up to the harness is what makes the recorded pid a
# liveness token worth checking.
leadv2_loop_owner_pid() {
  local p="$$" i cmd
  for i in 1 2 3 4 5 6 7 8; do
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$p" in ''|0|1) break ;; esac
    case "$p" in *[!0-9]*) break ;; esac
    cmd="$(ps -o comm= -p "$p" 2>/dev/null || true)"
    case "${cmd##*/}" in
      claude|node) printf '%s\n' "$p"; return 0 ;;
    esac
  done
  printf '0\n'
  return 0
}

# leadv2_loop_owner_record <owner_file> <transcript_path>
# Writes the owner liveness record for a loop about to start. Env inputs set
# by the armer win (LEADV2_LOOP_OWNER_PID / _SID / _TRANSCRIPT); the walked
# harness pid and CLAUDE_CODE_SESSION_ID are the fallbacks. A pid that is not
# verifiably ALIVE right now is recorded as 0 — a dead or guessed pid must
# never become a liveness token (the transcript-mtime rule still applies).
leadv2_loop_owner_record() {  # <owner_file> <transcript_path>
  local f="$1" tp="${2:-}"
  local pid="${LEADV2_LOOP_OWNER_PID:-}"
  case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  if [[ -z "$pid" ]]; then
    pid="$(leadv2_loop_owner_pid)"
  fi
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && ! kill -0 "$pid" 2>/dev/null; then
    pid=0
  fi
  local sid="${LEADV2_LOOP_OWNER_SID:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}}"
  sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)"
  [[ -n "$tp" ]] || tp="${LEADV2_LOOP_OWNER_TRANSCRIPT:-}"
  {
    printf 'pid=%s\n' "$pid"
    printf 'sid=%s\n' "$sid"
    printf 'transcript=%s\n' "$tp"
    printf 'armed=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  } > "${f}.tmp.$$" 2>/dev/null && mv -f "${f}.tmp.$$" "$f" 2>/dev/null || true
}

# leadv2_loop_owner_check <owner_file> <loop_name> -> rc 0 keep running, 1 exit.
# Rule 2 of BEAT-LOOP-ORPHANS-01: the loop exits when its owner's recorded pid
# is dead OR the owner's transcript mtime is older than
# LEADV2_LOOP_ORPHAN_MAX_MIN (default 30). A missing owner file (loop armed by
# a pre-lane dispatcher) fails open — the lifetime cap and SessionEnd still
# bound it.
leadv2_loop_owner_check() {  # <owner_file> <loop_name>
  local f="$1" name="${2:-loop}"
  [[ -f "$f" ]] || return 0
  local line pid="" tp="" mt maxmin age now
  while IFS= read -r line; do
    case "$line" in
      pid=*) pid="${line#pid=}" ;;
      transcript=*) tp="${line#transcript=}" ;;
    esac
  done < "$f"
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && ! kill -0 "$pid" 2>/dev/null; then
    printf '[%s] owner pid %s gone, exiting (BEAT-LOOP-ORPHANS-01)\n' "$name" "$pid" >&2
    return 1
  fi
  if [[ -n "$tp" && -f "$tp" ]]; then
    maxmin="${LEADV2_LOOP_ORPHAN_MAX_MIN:-30}"
    [[ "$maxmin" =~ ^[0-9]+$ ]] || maxmin=30
    mt="$(stat -f %m "$tp" 2>/dev/null || true)"
    case "$mt" in ''|*[!0-9]*)
      mt="$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$tp" 2>/dev/null || true)"
      ;; esac
    case "$mt" in ''|*[!0-9]*) return 0 ;; esac
    now="$(date +%s)"
    age=$(( now - mt ))
    if (( age > maxmin * 60 )); then
      printf '[%s] owner transcript stale %ss (> %ss), exiting (BEAT-LOOP-ORPHANS-01)\n' \
        "$name" "$age" "$(( maxmin * 60 ))" >&2
      return 1
    fi
  fi
  return 0
}

# leadv2_loop_arm_journal <journal_file> <loop_name> <kind>
# One line per arming decision that was not a clean lead arm — currently only
# the fail-open `unknown` case. Best-effort: journaling must never break arming.
leadv2_loop_arm_journal() {  # <journal_file> <loop_name> <kind>
  local f="$1" name="$2" kind="$3"
  local sid="${LEADV2_LOOP_OWNER_SID:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-none}}}"
  printf '%s event=loop_armed_by_%s_session loop=%s kind=%s sid=%s pid=%s entrypoint=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" "$kind" "$name" "$kind" \
    "$sid" "$$" "${CLAUDE_CODE_ENTRYPOINT:-none}" >> "$f" 2>/dev/null || true
  return 0
}
