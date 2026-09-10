#!/usr/bin/env bash
# leadv2-merge-safety-gate.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
#
# Refuses to land a lane whose MERGE would delete or revert paths on the
# default branch that no lane commit ever named. Five measured occurrences
# on 2026-09-03 -- all caught only because a human happened to run
# `git diff --stat main..HEAD` by hand before merging; the worst would have
# silently dropped 221 lines of a production test suite another lane had
# landed an hour earlier -- merge exit 0, no conflict, no warning.
#
# Incident mechanism (reproduced on git 2.50.1 before this discriminator
# was trusted): a lane merges main mid-flight with a wholesale resolution
# (`git merge -s ours main`). That merge commit carries main's ANCESTRY
# but the lane's TREE, so every path main gained after the fork is now the
# merge-base's content -- and the lane tip's absence of it reads as a
# lane-side deletion. The eventual merge is clean, exits 0, and deletes
# the path. `git log --name-only` emits no patch for merge commits, so no
# lane commit ever NAMES the reverted path: that is exactly the shape this
# gate refuses, and why the trust boundary is "named by a lane commit",
# not "touched by the lane's tree diff" (a tree diff sees the wholesale
# resolution as the lane's own edit and trusts it -- the 2026-09-03
# incidents all passed that older check).
#
# Discriminator (the only sound test -- branch-tip comparisons mislead):
# compute the would-be merge TREE (`git merge-tree --write-tree`) and diff
# IT against the default branch. A path that differs between the merge
# result and the default branch, on a path no lane commit ever named, is a
# main regression: the lane had no opinion on the path, so the merge
# result should match the default branch byte-for-byte. A path a lane
# commit DID name is the lane's decision and lands (an intended deletion
# must never be refused). Residual, known: a revert baked into a
# REBASE-replayed commit names the path and is trusted (the replay is
# indistinguishable from a deliberate edit at this point).
#
# Single source of truth: leadv2-deploy-merge.sh sources the core function
# below (lv2_merge_tree_regressions); leadv2-land.sh and the product-close
# T11 merge run this file's CLI. The discriminator lives HERE and nowhere
# else -- a second copy is how the 2026-07-29 one-inode defect happened.
#
# Fail CLOSED: anything that prevents the check from running (missing
# branch, no merge base, conflicted merge tree, git failure) refuses --
# never assume clean.
#
# Usage (CLI):
#   leadv2-merge-safety-gate.sh <repo_root> <lane_branch> [<default_branch>]
# Exit codes (CLI and core function agree):
#   0 = safe to merge -- the merge tree regresses nothing on the default
#       branch that the lane did not name itself
#   1 = REFUSED -- offending paths on stdout (function) / named in the
#       refusal block on stderr (CLI)
#   2 = cannot verify -- fail closed, see stderr
set -uo pipefail

# ── core: the merged-tree discriminator (sourceable) ────────────────────────
lv2_merge_tree_regressions() {
  # $1 = repo_root, $2 = default_branch, $3 = lane_branch.
  # Prints offending paths to stdout (one per line) when rc=1; diagnostics
  # to stderr. rc 0 = clean; 1 = regression; 2 = cannot verify.
  local repo_root="$1" default_branch="$2" lane_branch="$3"
  local merged_tree lane_named merged_changed offenders

  git -C "${repo_root}" rev-parse --verify --quiet "${default_branch}^{commit}" >/dev/null 2>&1 || {
    printf 'leadv2-merge-safety-gate: cannot resolve default branch %s\n' "${default_branch}" >&2
    return 2
  }
  git -C "${repo_root}" rev-parse --verify --quiet "${lane_branch}^{commit}" >/dev/null 2>&1 || {
    printf 'leadv2-merge-safety-gate: cannot resolve lane branch %s\n' "${lane_branch}" >&2
    return 2
  }
# bash-guard: allow

  # The would-be merge result. Any failure -- conflicted tree, no merge
  # base (unrelated histories), git error -- is "cannot verify" (rc 2),
  # never a pass.
  if ! merged_tree="$(git -C "${repo_root}" merge-tree --write-tree "${default_branch}" "${lane_branch}" 2>/dev/null)" \
     || [[ -z "${merged_tree}" ]]; then
    printf 'leadv2-merge-safety-gate: cannot compute merge tree for %s into %s (conflict, no merge base, or git failure)\n' \
      "${lane_branch}" "${default_branch}" >&2
    return 2
  fi

  # Paths the lane's OWN commits name -- default..lane, patch-based, so
  # merge commits contribute nothing (a wholesale -s ours resolution stays
  # unnamed -- exactly the accidental-revert shape). This is the trust
  # boundary: a named path is the lane's decision, named or not.
  lane_named="$(git -C "${repo_root}" log --name-only --no-renames --pretty=format: \
    "${default_branch}..${lane_branch}" 2>/dev/null | sort -u | grep -v '^$' || true)"

  # Everything the merge result would change on the default branch.
  merged_changed="$(git -C "${repo_root}" diff --name-only --no-renames \
    "${default_branch}" "${merged_tree}" 2>/dev/null | sort -u | grep -v '^$' || true)"
  [[ -z "${merged_changed}" ]] && return 0

  # Changed by the merge, never named by the lane = main regression.
  offenders="$(comm -13 <(printf '%s\n' "${lane_named}") <(printf '%s\n' "${merged_changed}"))"
  if [[ -n "$(printf '%s' "${offenders}" | tr -d '[:space:]')" ]]; then
    printf '%s\n' "${offenders}"
    return 1
  fi
  return 0
}

# ── CLI (land.sh, product-close T11; deploy-merge sources the core above) ───
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  REPO_ROOT="${1:-}"
  LANE_BRANCH="${2:-}"
  DEFAULT_BRANCH="${3:-}"

  if [[ -z "${REPO_ROOT}" || -z "${LANE_BRANCH}" ]]; then
    printf 'Usage: %s <repo_root> <lane_branch> [<default_branch>]\n' "$(basename "$0")" >&2
    exit 2
  fi

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=leadv2-branch-merged.sh
  source "${SCRIPT_DIR}/leadv2-branch-merged.sh"

  if [[ -z "${DEFAULT_BRANCH}" ]]; then
    # Unresolvable default -> empty -> the core's rev-parse refuses (rc 2).
    DEFAULT_BRANCH="$(lv2_default_branch "${REPO_ROOT}" 2>/dev/null || true)"
  fi

  GATE_RC=0
  OFFENDERS="$(lv2_merge_tree_regressions "${REPO_ROOT}" "${DEFAULT_BRANCH}" "${LANE_BRANCH}")" || GATE_RC=$?

  if [[ "${GATE_RC}" -eq 1 ]]; then
    printf 'MERGE_REFUSED: merging %s into %s would delete or revert %d path(s) present on %s that no lane commit ever named:\n' \
      "${LANE_BRANCH}" "${DEFAULT_BRANCH}" "$(printf '%s\n' "${OFFENDERS}" | grep -c . || true)" "${DEFAULT_BRANCH}" >&2
    printf '%s\n' "${OFFENDERS}" | sed 's/^/  /' >&2
    printf 'FIX: merge %s into the lane with a REAL resolution (not -s ours), then retry.\n' "${DEFAULT_BRANCH}" >&2
  fi
  exit "${GATE_RC}"
fi
# bash-guard: allow
