#!/usr/bin/env bash
# leadv2-merge-old-branch.sh — CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01
#
# Merges an old branch into the current branch WITHOUT hand-holding and
# WITHOUT ever replacing the control-plane symlinks with regular files.
#
# Why this exists (measured 2026-09-04): on main, docs/leadv2's control-plane
# entries are symlinks (mode 120000) into ~/.claude/leadv2-state/leadv2/;
# seventeen old branches carry them as ordinary files committed before the
# control plane moved out of the tree. A merge therefore hits a git
# "distinct types" conflict, and BOTH obvious resolutions — take-theirs or
# checkout-ours — destroy the symlink (active.yaml was restored five times in
# one session). No .gitattributes merge driver helps here: git measured NEVER
# invoking any merge driver when the two sides differ in type. What git does
# is already the right resolution — ours (the symlink) stays, theirs is parked
# at "<path>~<branch>" — but finishing the merge is then manual.
#
# What this script does:
#   1. self-registers the merge.leadv2-control-plane driver if missing
#      (covers same-type content conflicts on pinned paths: ours always wins);
#   2. runs `git merge --no-edit <branch>`;
#   3. auto-resolves EXACTLY ONE conflict shape: a control-plane path where
#      ours is a symlink — drops the parked "<path>~<branch>" regular file,
#      re-adds ours. Any other conflict: reported loudly, merge left in
#      progress, exit 1 (the caller decides; nothing of the branch's is lost);
#   4. runs the guard (leadv2-control-plane-merge-driver.sh --verify):
#      every pinned path a symlink, total symlink count == expected (16).
#      Guard failure aborts the merge — a merge that cannot keep the control
#      plane intact must not land half-finished;
#   5. commits the merge.
#
# Never touches main; never discards non-control-plane work.
#
# Usage: leadv2-merge-old-branch.sh <branch> [--dry-run]
#   --dry-run  stop after auto-resolution + guard, print what WOULD be committed
#
# Exit codes: 0 merged and guard green · 1 unresolved conflicts / guard failed
#             · 2 usage / environment error
set -uo pipefail

BRANCH=""
DRY_RUN=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="${HERE}/leadv2-control-plane-merge-driver.sh"

_mrg_log()  { printf '[merge-old] %s\n' "$*"; }
_mrg_die()  { printf 'leadv2-merge-old-branch: FATAL %s\n' "$*" >&2; exit 2; }
_mrg_fail() { printf 'leadv2-merge-old-branch: FAIL %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [[ -z "${BRANCH}" ]]; then BRANCH="$1"; shift; else
         _mrg_die "unknown argument: $1"; fi ;;
  esac
done
[[ -n "${BRANCH}" ]] || _mrg_die "usage: leadv2-merge-old-branch.sh <branch> [--dry-run]"
[[ -x "${DRIVER}" ]] || _mrg_die "driver not found/executable: ${DRIVER}"
git rev-parse --show-toplevel >/dev/null 2>&1 || _mrg_die "not inside a git repository"
git show-ref --verify -q "refs/heads/${BRANCH}" \
  || _mrg_die "no local branch '${BRANCH}'"

# 1) driver registration (shared .git/config → covers every worktree)
if ! git config merge.leadv2-control-plane.driver >/dev/null 2>&1; then
  "${DRIVER}" --register >/dev/null || _mrg_die "driver registration failed"
  _mrg_log "registered merge.leadv2-control-plane driver"
fi

# 2) merge
_mrg_log "merging ${BRANCH} into $(git rev-parse --abbrev-ref HEAD)"
if ! git merge --no-edit "${BRANCH}"; then
  _mrg_log "merge reported conflicts — resolving the control-plane shape"
else
  _mrg_log "merge was clean"
fi

# 3) auto-resolve the ONE safe shape
unresolved=""
if git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    parked=""
    case "${entry}" in
      *\~*)
        cand="${entry%\~*}"                     # strip ~<branch> suffix
        if git check-attr merge -- "${cand}" 2>/dev/null \
             | grep -q "merge: leadv2-control-plane"; then
          parked="${entry}"
        fi
        ;;
      *)
        if git check-attr merge -- "${entry}" 2>/dev/null \
             | grep -q "merge: leadv2-control-plane"; then
          if [[ -L "${entry}" ]]; then
            git add -- "${entry}" || _mrg_fail "cannot stage kept symlink ${entry}"
            _mrg_log "kept ours (symlink): ${entry}"
          else
            unresolved+="ours-not-a-symlink:${entry} "
          fi
        else
          unresolved+="not-control-plane:${entry} "
        fi
        ;;
    esac
    if [[ -n "${parked}" ]]; then
      cand="${parked%\~*}"
      if [[ ! -L "${cand}" ]]; then
        unresolved+="ours-not-a-symlink:${cand} "
        continue
      fi
      git rm -q -- "${parked}" || _mrg_fail "cannot drop parked file ${parked}"
      git add -- "${cand}" || _mrg_fail "cannot stage symlink ${cand}"
      _mrg_log "resolved distinct-types: dropped ${parked}, kept symlink ${cand}"
    fi
  done < <(git diff --name-only --diff-filter=U | sort -u)
fi

if [[ -n "${unresolved}" ]]; then
  printf 'leadv2-merge-old-branch: unresolved conflicts (merge left IN PROGRESS):\n' >&2
  for u in ${unresolved}; do printf '  %s\n' "${u}" >&2; done
  printf 'Resolve them by hand, or `git merge --abort`.\n' >&2
  exit 1
fi

# 4) the guard — a merge that cannot keep the control plane intact must not land
if ! "${DRIVER}" --verify; then
  printf 'leadv2-merge-old-branch: guard failed — aborting the merge\n' >&2
  git merge --abort >/dev/null 2>&1 || true
  exit 1
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  _mrg_log "dry-run: stopping before commit (resolution staged, guard green)"
  exit 0
fi

# 5) conclude
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  git commit --no-edit || _mrg_fail "git commit failed"
  _mrg_log "merge commit: $(git rev-parse --short HEAD)"
else
  _mrg_log "nothing to commit (already up to date)"
fi
_mrg_log "done"
exit 0
