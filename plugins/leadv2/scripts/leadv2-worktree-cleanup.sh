#!/usr/bin/env bash
set -euo pipefail
# leadv2-worktree-cleanup.sh — safely remove a /leadv2 worktree and its branch.
# Usage: leadv2-worktree-cleanup.sh --name <worktree-name> [--force]

readonly SCRIPT_NAME="leadv2-worktree-cleanup.sh"

_LV2_WT_CLEANUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-branch-merged.sh
source "${_LV2_WT_CLEANUP_DIR}/leadv2-branch-merged.sh"

log()       { printf -- '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { log "ERROR: $*"; }
log_info()  { log "INFO: $*"; }

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME --name <worktree-name> [--force]
       $SCRIPT_NAME --sweep-merged
       $SCRIPT_NAME --sweep-dead

  --name <name>    Name of the worktree under .claude/worktrees/<name>
  --force          Remove even if worktree has uncommitted/untracked changes,
                    unmerged commits, or a merge-blocker.flag is present
  --sweep-merged   Remove all .claude/worktrees/<name> worktrees whose branches
                   are fully merged into the default branch AND whose lane is
                   not live (leadv2-lane-liveness.sh). Unmerged, dirty
                   (uncommitted changes), still-live, carrying a
                   docs/handoff/<id>/merge-blocker.flag, and the current CWD
                   worktree are all kept, each printed with its reason.
  --sweep-dead     Remove all .claude/worktrees/<lane-id> worktrees whose lane is
                   no longer live (leadv2-lane-liveness.sh) AND provably empty
                   (clean tree, 0 commits ahead of the default branch). A lane
                   still live in active.yaml, a dirty tree, a worktree with
                   unmerged commits, or one carrying docs/handoff/<id>/
                   merge-blocker.flag is KEPT and printed with its reason --
                   never forced.
EOF
  exit 1
}

NAME=""; FORCE=0; SWEEP_MERGED=0; SWEEP_DEAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         NAME="$2"; shift 2 ;;
    --force)        FORCE=1;   shift ;;
    --sweep-merged) SWEEP_MERGED=1; shift ;;
    --sweep-dead)   SWEEP_DEAD=1; shift ;;
    *) log_error "Unknown argument: $1"; usage ;;
  esac
done

# ── --sweep-dead mode ───────────────────────────────────────────────────────
# W-1 lane-worktree-isolation (§1.4): --sweep-merged only ever matched
# agent-<hex> names against MERGED branches; lane worktrees are named after
# the founder task id and their branches are typically still unmerged at the
# point a lane dies mid-run (empty worker, launcher refusal, close-phase
# exit), so --sweep-merged never reaped them. This mode targets exactly that
# gap: a lane that is no longer live AND left nothing behind is safe to
# remove; anything else is reported, never forced.
if [[ "$SWEEP_DEAD" -eq 1 ]]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    log_error "Not inside a git repository"
    exit 1
  }
  LIVENESS_BIN="${_LV2_WT_CLEANUP_DIR}/leadv2-lane-liveness.sh"

  DEFAULT_BRANCH="$(lv2_default_branch "$REPO_ROOT")"
  log_info "Default branch: ${DEFAULT_BRANCH}"

  CWD_WT=$(git rev-parse --show-toplevel 2>/dev/null || printf -- '')

  removed=0; kept=0

  while IFS= read -r wt_path; do
    lane_id="${wt_path##*/.claude/worktrees/}"
    [[ "$wt_path" == "$lane_id" ]] && continue  # not under .claude/worktrees/

    if [[ -n "$CWD_WT" && "$wt_path" == "$CWD_WT" ]]; then
      log_info "KEPT (cwd): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    # Still live? leadv2-lane-liveness.sh is the single authority; any verdict
    # NOT prefixed "dead:" (live/starting/silent) or a liveness check that
    # itself fails to run is treated as live -- safe-default is to KEEP, never
    # to remove a lane we could not confidently prove dead.
    verdict=""
    if [[ -x "$LIVENESS_BIN" ]]; then
      verdict="$(LEADV2_PROJECT_ROOT="$REPO_ROOT" bash "$LIVENESS_BIN" --lane "$lane_id" --json --project-root "$REPO_ROOT" 2>/dev/null \
        | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("verdict",""))
except Exception:
    print("")' 2>/dev/null || printf -- '')"
    fi
    if [[ -z "$verdict" || "$verdict" != dead:* ]]; then
      log_info "KEPT (lane-live verdict=${verdict:-unknown}): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    # merge-blocker.flag lives in the control-plane docs/handoff tree, keyed by
    # the same lane id the worktree is named after (leadv2-deploy-merge.sh).
    if [[ -f "$REPO_ROOT/docs/handoff/${lane_id}/merge-blocker.flag" ]]; then
      log_info "KEPT (merge-blocker.flag): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    _dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$_dirty" ]]; then
      log_info "KEPT (dirty-uncommitted): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    wt_branch=$(git -C "$REPO_ROOT" worktree list --porcelain \
      | awk -v wt="$wt_path" '
          /^worktree / { cur=$2 }
          /^branch /   { if (cur==wt) { sub("refs/heads/",""); print $2 } }
        ')
    ahead=0
    if [[ -n "$wt_branch" ]]; then
      ahead="$(git -C "$REPO_ROOT" rev-list --count "${DEFAULT_BRANCH}..${wt_branch}" 2>/dev/null || printf -- '0')"
    fi
    if [[ "${ahead:-0}" -gt 0 ]]; then
      log_info "KEPT (unmerged commits ahead=${ahead}): $wt_path  branch=${wt_branch}"
      kept=$(( kept + 1 ))
      continue
    fi

    log_info "REMOVED (dead+empty): $wt_path  branch=${wt_branch:-none}"
    git -C "$REPO_ROOT" worktree remove --force "$wt_path" 2>/dev/null || true
    [[ -n "$wt_branch" ]] && git -C "$REPO_ROOT" branch -D "$wt_branch" 2>/dev/null || true
    removed=$(( removed + 1 ))
  done < <(git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree / {print $2}' | grep -F '/.claude/worktrees/')

  git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
  printf -- 'sweep-dead: %d removed / %d kept\n' "$removed" "$kept"
  exit 0
fi
# ── end --sweep-dead ────────────────────────────────────────────────────────

# ── --sweep-merged mode ────────────────────────────────────────────────────────
if [[ "$SWEEP_MERGED" -eq 1 ]]; then
  # Resolve repo root
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    log_error "Not inside a git repository"
    exit 1
  }

  DEFAULT_BRANCH="$(lv2_default_branch "$REPO_ROOT")"
  log_info "Default branch: ${DEFAULT_BRANCH}"

  LIVENESS_BIN_SM="${_LV2_WT_CLEANUP_DIR}/leadv2-lane-liveness.sh"

  # Determine CWD worktree top-level — NEVER remove this one
  CWD_WT=$(git rev-parse --show-toplevel 2>/dev/null || printf -- '')

  removed=0; kept=0

  # Parse porcelain output: collect worktree paths and their HEAD branch
  while IFS= read -r wt_path; do
    # Extract branch for this worktree from porcelain output
    wt_branch=$(git -C "$REPO_ROOT" worktree list --porcelain \
      | awk -v wt="$wt_path" '
          /^worktree / { cur=$2 }
          /^branch /   { if (cur==wt) { sub("refs/heads/",""); print $2 } }
        ')

    # W-1 lane-worktree-isolation follow-up (WORKTREE-GC-NEVER-FIRED-01 R3):
    # widened from the original agent-<hex>-only glob to every worktree
    # under .claude/worktrees/ — gated by the liveness + merge-blocker
    # checks below, which the agent-<hex>-only version never needed because
    # subagent worktrees have no lane-liveness or merge-blocker concept.
    case "$wt_path" in
      */.claude/worktrees/*) ;;
      *) continue ;;
    esac

    # Skip CWD worktree
    if [[ -n "$CWD_WT" && "$wt_path" == "$CWD_WT" ]]; then
      log_info "KEPT (cwd): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    # Skip if no branch (detached HEAD)
    if [[ -z "$wt_branch" ]]; then
      log_info "KEPT (detached/no-branch): $wt_path"
      kept=$(( kept + 1 ))
      continue
    fi

    # Check if branch is fully merged into default branch. lv2_branch_merged
    # uses merge-base --is-ancestor, never a `git branch --merged | grep`
    # reparse — this is the fix for WORKTREE-GC-NEVER-FIRED-01's root cause:
    # `git branch` prefixes a branch checked out in ANOTHER worktree with
    # `+`, not `*`, so the old regex never matched a lane branch.
    if lv2_branch_merged "$REPO_ROOT" "$wt_branch" "$DEFAULT_BRANCH"; then
      lane_id_sm=$(basename "$wt_path")

      # Liveness gate (R3): a lane worktree whose lane is still live must
      # never be reaped just because its branch merged mid-session. Only a
      # verdict prefixed "dead:" permits removal; empty/unparseable/missing
      # liveness binary all mean KEEP.
      verdict_sm=""
      if [[ -x "$LIVENESS_BIN_SM" ]]; then
        verdict_sm="$(LEADV2_PROJECT_ROOT="$REPO_ROOT" bash "$LIVENESS_BIN_SM" --lane "$lane_id_sm" --json --project-root "$REPO_ROOT" 2>/dev/null \
          | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("verdict",""))
except Exception:
    print("")' 2>/dev/null || printf -- '')"
      fi
      if [[ -z "$verdict_sm" || "$verdict_sm" != dead:* ]]; then
        log_info "KEPT (lane-live verdict=${verdict_sm:-unknown}): $wt_path  branch=${wt_branch}"
        kept=$(( kept + 1 ))
        continue
      fi

      # Merge-blocker gate (R3): a merged branch can still be flagged if the
      # ff-merge back to default failed after the fact.
      if [[ -f "$REPO_ROOT/docs/handoff/${lane_id_sm}/merge-blocker.flag" ]]; then
        log_info "KEPT (merge-blocker.flag): $wt_path  branch=${wt_branch}"
        kept=$(( kept + 1 ))
        continue
      fi

      # Dirty-guard: never destroy uncommitted files in a merged worktree.
      # These are exactly the worktrees that pile up — dirty = not cleanly closed.
      _dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
      if [[ -n "$_dirty" ]]; then
        log_info "KEPT (dirty-uncommitted): $wt_path  branch=${wt_branch}"
        kept=$(( kept + 1 ))
        continue
      fi
      log_info "REMOVED (merged): $wt_path  branch=${wt_branch}"
      git -C "$REPO_ROOT" worktree remove --force "$wt_path" 2>/dev/null || true
      git -C "$REPO_ROOT" branch -D "$wt_branch" 2>/dev/null || true
      removed=$(( removed + 1 ))
    else
      log_info "KEPT (unmerged): $wt_path  branch=${wt_branch}"
      kept=$(( kept + 1 ))
    fi
  done < <(git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree / {print $2}')

  git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
  printf -- 'sweep-merged: %d removed / %d kept\n' "$removed" "$kept"
  exit 0
fi
# ── end --sweep-merged ────────────────────────────────────────────────────────

[[ -z "$NAME" ]] && { log_error "--name is required (or use --sweep-merged)"; usage; }

# Resolve repo root — must run from inside the repo (main or worktree).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  log_error "Not inside a git repository"
  exit 1
}

WORKTREE_PATH="${REPO_ROOT}/.claude/worktrees/${NAME}"

# Security: ensure the resolved path stays under .claude/worktrees/ (no path escape).
WORKTREES_DIR="${REPO_ROOT}/.claude/worktrees"
# realpath --relative-base is not portable; use string prefix check on canonical paths.
CANONICAL_WT=$(realpath "$WORKTREE_PATH" 2>/dev/null || printf -- '%s' "$WORKTREE_PATH")
CANONICAL_BASE=$(realpath "$WORKTREES_DIR" 2>/dev/null || printf -- '%s' "$WORKTREES_DIR")

if [[ "$CANONICAL_WT" != "${CANONICAL_BASE}/"* ]]; then
  log_error "Path escape detected: '$WORKTREE_PATH' is not under '$WORKTREES_DIR'"
  exit 1
fi

# Guard: if the calling process's CWD is inside the worktree we're about to
# delete, removing it would leave the shell in a non-existent directory and
# cause ENOENT crashes in hooks. Print instructions and exit non-zero so the
# caller (phase8-close.sh) sees a clean "skip" rather than a crash.
CURRENT_DIR=$(pwd -P 2>/dev/null || pwd)
CANONICAL_WT_REAL=$(realpath "$WORKTREE_PATH" 2>/dev/null || printf -- '%s' "$WORKTREE_PATH")
if [[ "$CURRENT_DIR" == "${CANONICAL_WT_REAL}"* ]]; then
  printf -- '\n'
  printf -- 'SKIP: CWD is inside worktree — cannot delete while session is open.\n'
  printf -- 'Close this Claude session, then remove manually:\n'
  printf -- '  git worktree remove --force .claude/worktrees/%s\n' "$NAME"
  printf -- '  git branch -D worktree-%s\n' "$NAME"
  printf -- '\n'
  exit 2
fi

# Confirm worktree is registered with git.
if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -qF "worktree $WORKTREE_PATH"; then
  log_error "Worktree not found in git worktree list: $WORKTREE_PATH"
  exit 1
fi

BRANCH_NAME="worktree-${NAME}"

# W-1 lane-worktree-isolation (§1.5): reap must refuse a lane that failed to
# merge back, explicitly and loudly -- not just "happens to be the success
# path". A merge-blocker.flag or unmerged commits mean the lane's work is not
# yet on the default branch; removing the worktree here would discard it
# silently. Make it explicit and defensive, matching the dirty-tree guard
# below. --force is the one deliberate human override for all three checks.
if [[ "$FORCE" -eq 0 ]]; then
  BLOCKER_FLAG="${REPO_ROOT}/docs/handoff/${NAME}/merge-blocker.flag"
  if [[ -f "$BLOCKER_FLAG" ]]; then
    log_error "Worktree's merge-back failed (merge-blocker.flag present): $BLOCKER_FLAG"
    log_error "Use --force to remove anyway, or resolve the merge conflict first."
    exit 1
  fi

  DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||') || true
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || printf -- 'main')
  fi
  if git -C "$REPO_ROOT" rev-parse --verify -q "$BRANCH_NAME" >/dev/null 2>&1; then
    AHEAD=$(git -C "$REPO_ROOT" rev-list --count "${DEFAULT_BRANCH}..${BRANCH_NAME}" 2>/dev/null || printf -- '0')
    if [[ "${AHEAD:-0}" -gt 0 ]]; then
      log_error "Worktree branch has ${AHEAD} commit(s) not reachable from ${DEFAULT_BRANCH} (unmerged)."
      log_error "Use --force to remove anyway, or land the branch first."
      exit 1
    fi
  fi
fi

# Check for uncommitted/untracked changes unless --force.
if [[ "$FORCE" -eq 0 ]]; then
  # git status inside the worktree — use -C to target it from the main repo.
  DIRTY=$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null || true)
  if [[ -n "$DIRTY" ]]; then
    log_error "Worktree has uncommitted or untracked changes:"
    printf -- '%s\n' "$DIRTY" >&2
    log_error "Use --force to remove anyway, or commit/stash changes first."
    exit 1
  fi
fi

log_info "Removing worktree: $WORKTREE_PATH"
git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_PATH"

log_info "Deleting branch: $BRANCH_NAME"
git -C "$REPO_ROOT" branch -D "$BRANCH_NAME" 2>/dev/null || true

printf -- '\n'
printf -- 'Worktree removed: .claude/worktrees/%s\n' "$NAME"
printf -- 'Branch deleted:   worktree-%s\n' "$NAME"
printf -- '\n'
printf -- 'NOTE: If you ran this from inside the worktree, restart Claude session\n'
printf -- "with \`claude\` from %s to release session state.\n" "$REPO_ROOT"
