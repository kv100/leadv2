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
# Scan is one level deep over each root in $LEADV2_HOOK_FORK_SCAN_ROOTS
# (colon-separated; default $HOME/Projects:$HOME/MythicalGames — repos on this
# machine live under BOTH trees; m3-market sat invisible under MythicalGames
# until 2026-09-03, HOOKS-PARITY-ACROSS-REPOS-01): <root>/<repo>/.claude/hooks/
# <plugin-hook-name>. Repos that
# carry plugins/leadv2/hooks/ themselves are canonical checkouts (leadv2 or its
# worktrees), not consumers, and are skipped.
#
# Env:
#   LEADV2_HOOK_FORK_SCAN_ROOTS  scan roots, colon-separated
#                                (default $HOME/Projects:$HOME/MythicalGames)
#   LEADV2_HOOK_FORK_SCAN_ROOT   legacy singular form: if set, it wins and is
#                                the only root scanned (back-compat, tests)
#   LEADV2_HOOK_FORK_CANONICAL   canonical hooks dir (default ../hooks)
# Run: bash plugins/leadv2/scripts/leadv2-hook-fork-guard.sh
set -uo pipefail

GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
CANONICAL_HOOKS="${LEADV2_HOOK_FORK_CANONICAL:-${GUARD_DIR}/../hooks}"
if [ -n "${LEADV2_HOOK_FORK_SCAN_ROOT:-}" ]; then
  SCAN_ROOTS="$LEADV2_HOOK_FORK_SCAN_ROOT"
else
  SCAN_ROOTS="${LEADV2_HOOK_FORK_SCAN_ROOTS:-${HOME}/Projects:${HOME}/MythicalGames}"
fi

if [ ! -d "$CANONICAL_HOOKS" ]; then
  printf 'FORK-GUARD FATAL: canonical hooks dir not found: %s\n' "$CANONICAL_HOOKS" >&2
  exit 2
fi
SCAN_ROOTS="${SCAN_ROOTS//:/ }"
for root in $SCAN_ROOTS; do
  if [ ! -d "$root" ]; then
    printf 'FORK-GUARD FATAL: scan root not found: %s\n' "$root" >&2
    exit 2
  fi
done

violations=0
checked=0
for hook_path in "$CANONICAL_HOOKS"/*; do
  [ -e "$hook_path" ] || continue
  hook_name="$(basename "$hook_path")"
  for root in $SCAN_ROOTS; do
  for hooks_dir in "$root"/*/.claude/hooks; do
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
done

printf 'FORK-GUARD: %d hook-installation(s) checked, %d violation(s)\n' \
  "$checked" "$violations"
[ "$violations" -eq 0 ] || exit 1
exit 0
