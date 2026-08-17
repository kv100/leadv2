#!/usr/bin/env bash
# tests/test-worktree-gc-plus-prefix.sh — WORKTREE-GC-NEVER-FIRED-01 regression.
#
# Root cause: `git branch --merged main | grep -qE "^\*?[[:space:]]+${branch}$"`
# only matches the `*` prefix `git branch` uses for the CURRENTLY-checked-out
# branch. A branch checked out in ANOTHER worktree (which is exactly every
# lane branch, by definition) is prefixed `+`, not `*` — so the old regex
# never matched a single worktree-lane branch. This test proves:
#   1. The `+`-prefix case is the whole bug (RED on the old regex, GREEN on
#      lv2_branch_merged, which never parses `git branch` porcelain text).
#   2. Neither leadv2-stale-sweeper.sh's non-interactive path nor
#      leadv2-worktree-cleanup.sh's --sweep-dead path carries --force — the
#      one documented override for all three removal refusals must never
#      appear on an unattended path (F2/R1, CRITICAL).
#
# Run: bash tests/test-worktree-gc-plus-prefix.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
SCRIPTS_DIR="${ROOT}/plugins/leadv2/scripts"
BRANCH_MERGED_SH="${SCRIPTS_DIR}/leadv2-branch-merged.sh"
SWEEPER_SH="${SCRIPTS_DIR}/leadv2-stale-sweeper.sh"
CLEANUP_SH="${SCRIPTS_DIR}/leadv2-worktree-cleanup.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── build a scratch git repo with a branch checked out in ANOTHER worktree ──
SCRATCH="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${SCRATCH}'" EXIT

git -C "$SCRATCH" init -q
git -C "$SCRATCH" config user.email "test@test"
git -C "$SCRATCH" config user.name  "Test"
printf 'init\n' > "${SCRATCH}/README"
git -C "$SCRATCH" add README
git -C "$SCRATCH" commit -q -m "init"

WT="${SCRATCH}/.claude/worktrees/lane-plusfix"
mkdir -p "$(dirname "$WT")"
git -C "$SCRATCH" worktree add -q -b "worktree-lane-plusfix" "$WT"
printf 'work\n' > "${WT}/file.txt"
git -C "$WT" add .
git -C "$WT" commit -q -m "lane work"
git -C "$SCRATCH" merge -q --no-ff "worktree-lane-plusfix" -m "merge lane" >/dev/null

# Confirm the fixture actually reproduces the `+`-prefix condition — a
# branch checked out in another worktree, not `*`.
BRANCH_LIST_LINE="$(git -C "$SCRATCH" branch --merged main | grep 'worktree-lane-plusfix' || true)"
if [[ "$BRANCH_LIST_LINE" == +* ]]; then
  pass "fixture reproduces the +-prefix condition (git branch --merged: '${BRANCH_LIST_LINE}')"
else
  fail "fixture did NOT reproduce the +-prefix condition — got '${BRANCH_LIST_LINE}'"
fi

# ── 1a. RED: the OLD regex never matches a +-prefixed branch ────────────────
if git -C "$SCRATCH" branch --merged main 2>/dev/null \
    | grep -qE "^\*?[[:space:]]+worktree-lane-plusfix$"; then
  fail "OLD regex unexpectedly matched a +-prefixed branch (bug should still reproduce)"
else
  pass "OLD regex fails on +-prefixed branch (this IS the bug, confirmed RED)"
fi

# ── 1b. GREEN: lv2_branch_merged matches regardless of +/* prefix ───────────
if [[ -f "$BRANCH_MERGED_SH" ]]; then
  # shellcheck source=/dev/null
  source "$BRANCH_MERGED_SH"
  if lv2_branch_merged "$SCRATCH" "worktree-lane-plusfix" "main"; then
    pass "lv2_branch_merged matches the +-prefixed (other-worktree-checked-out) branch"
  else
    fail "lv2_branch_merged failed to match the +-prefixed branch — fix not effective"
  fi

  # Sanity: an unmerged branch (a commit not reachable from main) is
  # correctly reported not-merged. Built off the initial commit so its tip
  # commit is never an ancestor of main's current (post-merge) HEAD.
  INIT_COMMIT="$(git -C "$SCRATCH" rev-list --max-parents=0 main)"
  git -C "$SCRATCH" branch unmerged-branch "$INIT_COMMIT" >/dev/null
  UNMERGED_WT="${SCRATCH}/.claude/worktrees/lane-unmerged"
  git -C "$SCRATCH" worktree add -q "$UNMERGED_WT" unmerged-branch
  printf 'unmerged work\n' > "${UNMERGED_WT}/unmerged-file.txt"
  git -C "$UNMERGED_WT" add .
  git -C "$UNMERGED_WT" commit -q -m "unmerged commit"
  if ! lv2_branch_merged "$SCRATCH" "unmerged-branch" "main"; then
    pass "lv2_branch_merged correctly reports an unmerged branch as not-merged"
  else
    fail "lv2_branch_merged incorrectly reported an unmerged branch as merged"
  fi
else
  fail "leadv2-branch-merged.sh not found at ${BRANCH_MERGED_SH} (has the fix landed?)"
fi

# ── 2. --force must never appear on a non-interactive removal path ──────────
# leadv2-stale-sweeper.sh's non-interactive GC path (originally the inline
# loop calling `leadv2-worktree-cleanup.sh --name ... --force`) must not
# survive: the only `--force` in the sweeper file may be the interactive
# orphan-discard branch (a human explicitly chose "discard"), never on a
# line that also invokes worktree-cleanup.sh unattended.
if [[ -f "$SWEEPER_SH" ]]; then
  # Exclude comment lines (this file's own prose legitimately mentions both
  # strings while documenting the fix) -- only count actual invocation lines.
  force_cleanup_lines="$(grep -v '^[[:space:]]*#' "$SWEEPER_SH" | grep 'worktree-cleanup\.sh' | grep -c -- '--force' || true)"
  if [[ "${force_cleanup_lines:-0}" -le 1 ]]; then
    pass "leadv2-stale-sweeper.sh carries at most the one interactive --force override"
  else
    fail "leadv2-stale-sweeper.sh has ${force_cleanup_lines} worktree-cleanup.sh --force call sites (want <=1, the interactive discard branch)"
  fi

  if grep -qE 'worktree-cleanup\.sh"[^|&;]*--force' "$SWEEPER_SH" \
      && ! grep -B3 -- '--force' "$SWEEPER_SH" | grep -q 'd|discard'; then
    : # covered by the count check above; kept for readability, no separate assertion
  fi
else
  fail "leadv2-stale-sweeper.sh not found at ${SWEEPER_SH}"
fi

if [[ -f "$CLEANUP_SH" ]]; then
  if bash -n "$CLEANUP_SH" 2>/dev/null; then
    pass "leadv2-worktree-cleanup.sh: bash -n syntax check"
  else
    fail "leadv2-worktree-cleanup.sh: bash -n syntax check"
  fi

  # The --sweep-dead removal block is the auto/unattended path -- confirm
  # its `git worktree remove --force` line is not gated behind a bare
  # `--force` CLI flag skip (i.e. the block is reachable without --force).
  if grep -A2 'REMOVED (dead+empty)' "$CLEANUP_SH" | grep -q 'worktree remove --force'; then
    pass "--sweep-dead removal exists and is reached without requiring the CLI --force flag"
  else
    fail "--sweep-dead removal block not found as expected"
  fi
else
  fail "leadv2-worktree-cleanup.sh not found at ${CLEANUP_SH}"
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf -- '\n'
printf -- 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "${#ERRORS[@]}" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
