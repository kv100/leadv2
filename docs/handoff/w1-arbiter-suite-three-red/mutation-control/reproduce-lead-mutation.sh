#!/usr/bin/env bash
# W1-ARBITER-SUITE-THREE-RED-01 round 2 — one-command reproduction of the
# lead's acceptance mutation, runnable in ANY checkout that contains this
# file (canonical main after merge, or the lane worktree). Applies the
# lead's exact substitution to THAT checkout's real lib, runs THAT
# checkout's suite, restores. The suite's own first line names the arbiter
# it sourced (path + sha256 prefix) — if that hash does not change between
# the green and red halves, the mutation landed in a different tree, which
# is exactly how round 2 was falsely accepted green on 2026-09-10.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SELF_DIR" rev-parse --show-toplevel)" || exit 2
LIB=plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
SUITE=plugins/leadv2/scripts/tests/test-route-arbiter.sh
cd "$ROOT" || exit 2
LOG="$SELF_DIR/$(date -u +%Y%m%dT%H%M%SZ)-reproduce.txt"
git diff --quiet -- "$LIB" || { echo "REFUSE: $LIB is dirty; commit or restore first" | tee "$LOG"; exit 2; }
{
  echo "root=$ROOT"
  echo "== GREEN half (unmutated) =="
  bash "$SUITE"
  echo "green_rc=$?"
  echo "== apply lead's substitution: no_capable_cell emit -> pool_empty_all_excluded =="
  sed -i '' "s/_record('refuse','none','none','no_capable_cell')/_record('refuse','none','none','pool_empty_all_excluded')/; s/reason=no_capable_cell kind=%s/reason=pool_empty_all_excluded kind=%s/" "$LIB"
  echo "grep -c no_capable_cell: $(grep -c no_capable_cell "$LIB") (expected: baseline minus 2)"
  echo "== RED half (mutated real file) =="
  bash "$SUITE"
  echo "red_rc=$?"
  echo "== restore =="
  git checkout -- "$LIB"
  git diff --quiet -- "$LIB" && echo "restore OK: lib byte-identical to HEAD"
} 2>&1 | tee "$LOG"
