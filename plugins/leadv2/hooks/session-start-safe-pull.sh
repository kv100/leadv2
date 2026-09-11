#!/usr/bin/env bash
# .claude/hooks/session-start-safe-pull.sh — LANE-WORKTREE-HOSTS-OTHER-TASKS-PROCESSES-01
#
# Replaces the old inline SessionStart hook
#   ( if [ -z "$(git status --porcelain)" ]; then git pull --rebase origin main
#     >/dev/null 2>&1 || true; fi ) & disown
# which rebased ANY clean checkout onto origin/main — including a freshly
# created, still-clean lane worktree, the exact moment its branch is most
# destructible. origin/main on this machine is frozen (we never push), so the
# rebase replayed hundreds of stale commits onto a branch that was never
# behind them. Silenced output + `|| true` + `& disown` meant the wreck was
# invisible until a lane's own work collided with the replay.
#
# This version refuses unless ALL of:
#   1. cwd is not inside a `.claude/worktrees/` path (a lane worktree).
#   2. HEAD is exactly refs/heads/main (not detached, not a lane branch).
#   3. the working tree is clean.
#   4. origin/main is actually ahead of local main (git rev-list --count).
# Every refusal and every outcome is appended to a log file instead of being
# discarded — a hook that cannot report its own failure is indistinguishable
# from one that never ran.

SAFE_PULL_LOG_FILE="${SAFE_PULL_LOG_FILE:-${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/session-start-safe-pull.log}"

safe_pull_log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"${SAFE_PULL_LOG_FILE}" 2>/dev/null || true
}

# Echoes a non-empty refusal reason and returns 0 when the pull must be
# skipped; echoes nothing and returns 1 when it is safe to proceed.
safe_pull_refusal_reason() {
  local cwd head_ref
  cwd="$(pwd -P 2>/dev/null || pwd)"
  case "${cwd}" in
    */.claude/worktrees/*)
      echo "cwd is a lane worktree: ${cwd}"
      return 0
      ;;
  esac

  head_ref="$(git symbolic-ref -q HEAD 2>/dev/null || true)"
  if [ "${head_ref}" != "refs/heads/main" ]; then
    echo "HEAD=${head_ref:-detached} is not refs/heads/main"
    return 0
  fi

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "working tree dirty"
    return 0
  fi

  return 1
}

safe_pull_run() {
  local reason behind_origin
  if reason="$(safe_pull_refusal_reason)"; then
    safe_pull_log "REFUSED: ${reason}"
    return 0
  fi

  if ! git fetch origin main --quiet >>"${SAFE_PULL_LOG_FILE}" 2>&1; then
    safe_pull_log "REFUSED: git fetch origin main failed"
    return 0
  fi

  behind_origin="$(git rev-list --count main..origin/main 2>/dev/null || echo 0)"
  if [ "${behind_origin}" -le 0 ] 2>/dev/null; then
    safe_pull_log "SKIPPED: origin/main not ahead of local main (behind=${behind_origin})"
    return 0
  fi

  if git pull --rebase origin main >>"${SAFE_PULL_LOG_FILE}" 2>&1; then
    safe_pull_log "OK: rebased local main onto origin/main (was behind=${behind_origin})"
  else
    safe_pull_log "FAILED: git pull --rebase origin main (see log above)"
    git rebase --abort >/dev/null 2>&1 || true
  fi
}

# Only run the flow when executed directly (not when a test sources this
# file to call the functions in isolation).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ( safe_pull_run ) & disown
fi
