#!/usr/bin/env bash
# leadv2-branch-merged.sh — sourced helper: the single answer to "is branch B
# merged into the default branch?" and "what is the default branch?".
#
# WORKTREE-GC-NEVER-FIRED-01: the bug this helper exists to retire was
# `git branch --merged main | grep -qE "^\*?[[:space:]]+${branch}$"` — `git
# branch` marks a branch checked out in ANOTHER worktree with a leading `+`,
# not `*`, so every worktree-lane branch (by definition checked out in its
# own worktree) failed to match. `git merge-base --is-ancestor` never parses
# `git branch` porcelain text, so it has no prefix character to miss.
#
# Pure reads only. No side effects on source. Safe to `source` from any
# script under plugins/leadv2/scripts/.
set -uo pipefail

# lv2_default_branch <repo_root>
# Prints the default branch name. Ladder: origin/HEAD -> current HEAD -> "main".
lv2_default_branch() {
  local repo_root="$1"
  local branch
  branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||') || true
  if [[ -z "$branch" ]]; then
    branch=$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || printf -- 'main')
  fi
  printf -- '%s\n' "$branch"
}

# lv2_branch_merged <repo_root> <branch> [default_branch]
# rc 0 = branch is merged into default_branch (or does not exist as a
# distinct ref -- merge-base --is-ancestor treats a missing ancestor branch
# as a hard failure, so an absent branch correctly returns rc 1: never
# treated as "merged").
# rc 1 = not merged, or branch absent.
lv2_branch_merged() {
  local repo_root="$1"
  local branch="$2"
  local default_branch="${3:-}"
  [[ -z "$default_branch" ]] && default_branch="$(lv2_default_branch "$repo_root")"
  git -C "$repo_root" merge-base --is-ancestor "$branch" "$default_branch" 2>/dev/null
}
