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
#   2. LEADV2_SUBSESSION_ROLE non-empty and != "lead" — exported at EVERY
#      headless `claude -p` spawn site (grep-gated by the orphan suite).
#   3. the TRANSCRIPT'S OWN CONTENT (fix-round 2: the round-1 path patterns
#      docs/handoff|*-runs never match a real transcript — worker transcripts
#      live at ~/.claude/projects/<munged-cwd>/<sid>.jsonl exactly like a
#      lead's):
#      a. the munged-cwd directory name contains `-claude-worktrees-` (true
#         for every lane worker's worktree cwd, never for a repo-root lead);
#      b. the first ~20 lines carry a lane-mission marker (LANE ROOT: /
#         WORKTREE PIN: / LANE_WRITES: / LEADV2_LANE_OUTCOME) — a headless
#         `claude -p` session's first user message IS the mission text.
#      Either signal -> `worker`.
#   4. neither signal AND no env pin -> `unknown`, and `unknown` FAILS CLOSED
#      for loops: no loop-arming caller may arm on `unknown`; it journals
#      session_kind=unknown reason=<why> instead. (The single-shot beat HOOK
#      keeps its documented fail-open: it spawns no loop.)
# Why fail closed: a worker that slips through arms an orphan loop nobody
# disarms (measured 2026-09-01: 53 orphans, load 244); a lead that is
# misjudged `unknown` loses only the autonomous beat loop and the journal
# line makes the starvation visible the same minute it happens.
# leadv2_hook_session_kind also sets — in the CALLER'S shell, so call it
# directly (never inside a $(...) subshell, which would drop both globals):
#   LEADV2_SESSION_KIND_OUT    lead|worker|unknown (mirror of stdout)
#   LEADV2_SESSION_KIND_REASON env_pin|env_worker_arm|env_subsession_role|
#       worktree_path|mission_transcript|no_transcript|no_worker_evidence
# for the journal.
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

# leadv2_transcript_worker_signal <transcript_path> -> rc 0 when the
# transcript itself carries worker evidence (sets LEADV2_SESSION_KIND_REASON).
# Signal (a): worktree munged-cwd in the path. Signal (b): a lane-mission
# marker within the first 20 lines (bounded read — jsonl lines can be huge).
leadv2_transcript_worker_signal() {  # <transcript_path>
  local tp="${1:-}"
  [[ -n "$tp" ]] || return 1
  case "$tp" in
    *-claude-worktrees-*)
      LEADV2_SESSION_KIND_REASON="worktree_path"
      return 0
      ;;
  esac
  [[ -r "$tp" ]] || return 1
  if head -n 20 "$tp" 2>/dev/null | grep -aqm1 \
       -e 'LANE ROOT:' -e 'WORKTREE PIN:' -e 'LANE_WRITES:' -e 'LEADV2_LANE_OUTCOME'; then
    LEADV2_SESSION_KIND_REASON="mission_transcript"
    return 0
  fi
  return 1
}

leadv2_hook_session_kind() {  # <transcript_path> -> prints lead|worker|unknown
  local transcript="${1:-}"
  local _kind
  LEADV2_SESSION_KIND_REASON=""

  case "${LEADV2_SESSION_KIND:-}" in
    lead|worker|unknown)
      LEADV2_SESSION_KIND_REASON="env_pin"
      _kind="$LEADV2_SESSION_KIND"
      LEADV2_SESSION_KIND_OUT="$_kind"
      printf '%s\n' "$_kind"
      return 0
      ;;
  esac

  if [[ "${LEADV2_WORKER_ARM:-0}" == "1" ]]; then
    LEADV2_SESSION_KIND_REASON="env_worker_arm"
    _kind="worker"
    LEADV2_SESSION_KIND_OUT="$_kind"
    printf '%s\n' "$_kind"
    return 0
  fi

  local sub_role="${LEADV2_SUBSESSION_ROLE:-}"
  if [[ -n "$sub_role" && "$sub_role" != "lead" ]]; then
    LEADV2_SESSION_KIND_REASON="env_subsession_role"
    _kind="worker"
    LEADV2_SESSION_KIND_OUT="$_kind"
    printf '%s\n' "$_kind"
    return 0
  fi

  if leadv2_transcript_worker_signal "$transcript"; then
    _kind="worker"
    LEADV2_SESSION_KIND_OUT="$_kind"
    printf '%s\n' "$_kind"
    return 0
  fi

  # Fix-round 2: no env pin, no worker signal in the transcript itself.
  # FAIL CLOSED for loops — this is `unknown`, never `lead`.
  if [[ -n "$transcript" && -r "$transcript" ]]; then
    LEADV2_SESSION_KIND_REASON="no_worker_evidence"
  else
    LEADV2_SESSION_KIND_REASON="no_transcript"
  fi
  _kind="unknown"
  LEADV2_SESSION_KIND_OUT="$_kind"
  printf '%s\n' "$_kind"
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
  printf '%s event=loop_armed_by_%s_session loop=%s kind=%s reason=%s sid=%s pid=%s entrypoint=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" "$kind" "$name" "$kind" \
    "${LEADV2_SESSION_KIND_REASON:-none}" \
    "$sid" "$$" "${CLAUDE_CODE_ENTRYPOINT:-none}" >> "$f" 2>/dev/null || true
  return 0
}
