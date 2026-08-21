#!/usr/bin/env bash
# SessionStart hook: remove lane worktrees whose work has already landed.
#
# WHY THIS EXISTS (founder, 2026-08-21): "это проеб плагина, вечно приходится
# то же самое просить тебя делать". Worktrees were created by every dispatch and
# removed by nothing, so they accumulated until the founder noticed his editor
# listing 52 repositories and 2000+ pending changes across them. He then had to ask
# for the same manual cleanup, repeatedly.
#
# The capability already existed and was never wired: leadv2-worktree-cleanup.sh has
# a --sweep-merged mode, and NOTHING called it. The only live caller passes --name at
# phase 8, which reaps a lane that "left nothing behind" — so any lane that produced
# commits (i.e. every lane that did work) survived forever, even after its branch
# merged. Dead code guarding against a problem it was written to solve.
#
# SAFETY — a worktree is removed only when ALL of these hold:
#   * `git worktree remove` accepts it without --force, i.e. the tree is CLEAN.
#     Uncommitted work always wins; we never pass --force from here.
#   * its branch is fully merged into the default branch, so the commits live on.
#   * it is a lane worktree under .claude/worktrees/, never a hand-made checkout.
# The branch itself is NOT deleted: `worktree remove` drops the checkout only, so
# even a misjudgement costs a `git worktree add`, never a commit.
#
# Advisory by default about what it could NOT remove — a lane holding unmerged work
# is reported, never touched, because that is exactly where a founder deliverable
# hides. Today's sweep found a 150-line sample-generation script in one such tree.
#
# Kill switch: LEADV2_MERGED_WORKTREE_SWEEP=0.

set -uo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_MERGED_WORKTREE_SWEEP:-1}" == "0" ]] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "${ROOT}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Default branch: main if it exists, else whatever HEAD points at.
BASE="main"
git rev-parse --verify --quiet "${BASE}" >/dev/null 2>&1 || \
  BASE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

REMOVED=0
KEPT_DIRTY=0
KEPT_AHEAD=0
declare -a KEPT_NAMES=()

# Only lane worktrees, and only ones that still exist on disk.
while IFS= read -r wt; do
  [[ -n "${wt}" ]] || continue
  case "${wt}" in
    */.claude/worktrees/*) ;;
    *) continue ;;
  esac
  [[ -d "${wt}" ]] || continue

  # Unmerged work stays, and is named so a human can decide.
  ahead="$(git -C "${wt}" rev-list --count "${BASE}..HEAD" 2>/dev/null || echo 0)"
  if [[ "${ahead}" != "0" ]]; then
    KEPT_AHEAD=$((KEPT_AHEAD + 1)); KEPT_NAMES+=("$(basename "${wt}") (+${ahead})")
    continue
  fi

  # No --force, ever: a dirty tree refuses and stays.
  if git worktree remove "${wt}" >/dev/null 2>&1; then
    REMOVED=$((REMOVED + 1))
  else
    KEPT_DIRTY=$((KEPT_DIRTY + 1)); KEPT_NAMES+=("$(basename "${wt}") (dirty)")
  fi
done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

git worktree prune >/dev/null 2>&1 || true

if (( REMOVED > 0 || KEPT_AHEAD > 0 || KEPT_DIRTY > 0 )); then
  printf '[leadv2-merged-worktree-sweep] removed %d merged lane worktree(s)' "${REMOVED}" >&2
  if (( KEPT_AHEAD > 0 || KEPT_DIRTY > 0 )); then
    printf '; kept %d with unmerged commits, %d dirty: %s' \
      "${KEPT_AHEAD}" "${KEPT_DIRTY}" "${KEPT_NAMES[*]}" >&2
  fi
  printf '\n' >&2
fi

exit 0
