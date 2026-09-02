#!/usr/bin/env bash
# leadv2-hook-fork-guard.sh — PULSE-HOOK-IS-A-FORKED-COPY-01 deliverable 3.
#
# Fails while any real (non-symlink) copy of a plugin-owned hook exists under a
# consumer repo's .claude/hooks/. The 2026-07-29 defect class: a real copy of
# plugins/leadv2/hooks/leadv2-pulse-json.sh sat in persona-engine and drifted
# silently from canonical. Hooks must be symlinks into plugins/leadv2/hooks/
# (see leadv2-hook-materialized-core-gotcha for the separate plugin-cache case,
# which is out of scope here).
#
# Scan is one level deep over $LEADV2_HOOK_FORK_SCAN_ROOT (default
# $HOME/Projects): <root>/<repo>/.claude/hooks/<plugin-hook-name>. Repos that
# carry plugins/leadv2/hooks/ themselves are canonical checkouts (leadv2 or its
# worktrees), not consumers, and are skipped.
#
# Env:
#   LEADV2_HOOK_FORK_SCAN_ROOT   scan root (default $HOME/Projects)
#   LEADV2_HOOK_FORK_CANONICAL   canonical hooks dir (default ../hooks)
# Run: bash plugins/leadv2/scripts/leadv2-hook-fork-guard.sh
set -uo pipefail

GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
CANONICAL_HOOKS="${LEADV2_HOOK_FORK_CANONICAL:-${GUARD_DIR}/../hooks}"
SCAN_ROOT="${LEADV2_HOOK_FORK_SCAN_ROOT:-${HOME}/Projects}"

if [ ! -d "$CANONICAL_HOOKS" ]; then
  printf 'FORK-GUARD FATAL: canonical hooks dir not found: %s\n' "$CANONICAL_HOOKS" >&2
  exit 2
fi
if [ ! -d "$SCAN_ROOT" ]; then
  printf 'FORK-GUARD FATAL: scan root not found: %s\n' "$SCAN_ROOT" >&2
  exit 2
fi

violations=0
checked=0
for hook_path in "$CANONICAL_HOOKS"/*; do
  [ -e "$hook_path" ] || continue
  hook_name="$(basename "$hook_path")"
  for hooks_dir in "$SCAN_ROOT"/*/.claude/hooks; do
    [ -d "$hooks_dir" ] || continue
    repo_dir="$(dirname "$(dirname "$hooks_dir")")"
    # Canonical checkouts of the plugin itself are not consumers.
    [ -d "${repo_dir}/plugins/leadv2/hooks" ] && continue
    candidate="${hooks_dir}/${hook_name}"
    [ -e "$candidate" ] || continue
    checked=$((checked + 1))
    if [ ! -L "$candidate" ]; then
      printf 'FORK-GUARD FAIL: real copy of plugin-owned hook: %s\n' "$candidate"
      printf '  fix: rm %s && ln -s <leadv2>/plugins/leadv2/hooks/%s %s\n' \
        "$candidate" "$hook_name" "$candidate"
      violations=$((violations + 1))
    fi
  done
done

printf 'FORK-GUARD: %d hook-installation(s) checked, %d violation(s)\n' \
  "$checked" "$violations"
[ "$violations" -eq 0 ] || exit 1
exit 0
