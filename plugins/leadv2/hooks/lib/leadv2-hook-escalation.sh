#!/usr/bin/env bash
# One-command, auditable escape hatch for hooks that have already decided to
# block. Source only from that deny path: an allowed command is not an event.

lv2_hook_escalation_reason_valid() { # <reason>
  local reason="$1" compact
  [[ "$reason" =~ [^[:space:]] ]] || return 1
  compact="$(printf '%s' "$reason" | tr -d '[:space:]')"
  [[ ${#compact} -ge 12 && "$reason" =~ [[:space:]] ]] || return 1
}

lv2_hook_escalation_closed_class() { # <command>
  local command="$1"
  # Closed even with an escalation: these operations mutate shared Git state or
  # discard work. Keep this list short and local to the escalation mechanism.
  printf '%s' "$command" | grep -Eiq \
    'git.*(reset[[:space:]].*--hard|clean([[:space:]]|$)|stash([[:space:]]|$)|worktree[[:space:]]+prune([[:space:]]|$))'
}

lv2_hook_escalation_try() { # <hook-id> <command> <session-id>
  local hook_id="$1" command="$2" session_id="$3"
  local reason="${LEADV2_HOOK_ESCALATE:-}" journal_bin
  [[ -n "$reason" ]] || return 1

  if lv2_hook_escalation_closed_class "$command"; then
    printf '[%s] BLOCKED: this command class is not eligible for LEADV2_HOOK_ESCALATE (reset --hard, clean, stash, or shared-tree worktree prune).\n' "$hook_id" >&2
    return 3
  fi

  if ! lv2_hook_escalation_reason_valid "$reason"; then # escalation-reason-validation
    printf '[%s] BLOCKED: LEADV2_HOOK_ESCALATE needs a meaningful reason: at least 12 non-space characters and more than one word.\n' "$hook_id" >&2
    return 1
  fi

  [[ -n "$session_id" ]] || session_id="unknown-session"
  journal_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/leadv2-journal.sh"
  if [[ ! -f "$journal_bin" ]] || ! bash "$journal_bin" path "$session_id" >/dev/null 2>&1; then
    printf '[%s] ESCALATED: command allowed, but escalation journal recording failed (journal unavailable).\n' "$hook_id" >&2
    return 0
  fi
  if ! bash "$journal_bin" append "$session_id" decision \
    "hook_id=${hook_id} session_id=${session_id} command=${command} reason=${reason}"; then
    printf '[%s] ESCALATED: command allowed, but escalation journal recording failed.\n' "$hook_id" >&2
    return 0
  fi
  printf '[%s] ESCALATED: recorded one-command override for session %s.\n' "$hook_id" "$session_id" >&2
  return 0
}
