#!/usr/bin/env bash
# leadv2-status-projects.sh — SWIFTBAR-LIVE-01 cwd-independent project enumeration.
#
# Pure-read TSV producer: one row per project that has BOTH a live
# active.yaml under the control-plane state base AND a resolvable repo root.
# Zero git dependency, zero writes, zero network -- safe to call from any
# cwd (including "/" under a stripped SwiftBar env with no PATH git).
#
# Usage:
#   leadv2-status-projects.sh            # slug \t state_dir \t repo_root  (TSV, no header)
#   leadv2-status-projects.sh --slugs    # slug per line
#
# Repo-root resolution per slug, first hit wins:
#   1. <state_dir>/.repo-root   (written by leadv2-state-path.sh)
#   2. $HOME/Projects/<slug>/.git exists -> $HOME/Projects/<slug>
# A slug with neither is dropped -- no name deny-list needed (sandbox/
# throwaway dirs under the state base simply fail this check).
#
# Ordering: "persona-engine" first if present, then remaining slugs
# LC_ALL=C sort (stable output for tests).
#
# Exit: 0 always when the base dir is readable (0 rows is a legal answer).
#       2 if the base dir does not exist / is not readable.
#
# Env:
#   LEADV2_STATE_BASE   default: $HOME/.claude/leadv2-state

set -euo pipefail

BASE="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"

SLUGS_ONLY=0
if [ "${1:-}" = "--slugs" ]; then
  SLUGS_ONLY=1
  shift
fi

if [ ! -d "$BASE" ]; then
  exit 2
fi
if [ ! -r "$BASE" ]; then
  exit 2
fi

_repo_root_for() {
  local slug="$1" state_dir="$2" marker root
  marker="${state_dir}/.repo-root"
  if [ -f "$marker" ] && [ -r "$marker" ]; then
    root="$(cat "$marker" 2>/dev/null || true)"
    if [ -n "$root" ] && [ -d "$root" ]; then
      printf '%s' "$root"
      return 0
    fi
  fi
  root="${HOME}/Projects/${slug}"
  if [ -d "${root}/.git" ]; then
    printf '%s' "$root"
    return 0
  fi
  return 1
}

# Collect qualifying slugs into a temp list, then order.
TMP_LIST="$(mktemp 2>/dev/null || printf '/tmp/leadv2-status-projects.%s' "$$")"
trap 'rm -f "$TMP_LIST"' EXIT

for entry in "$BASE"/*/; do
  [ -d "$entry" ] || continue
  slug="$(basename "$entry")"
  state_dir="${BASE}/${slug}"
  [ -f "${state_dir}/active.yaml" ] || continue
  repo_root="$(_repo_root_for "$slug" "$state_dir" 2>/dev/null)" || continue
  [ -n "$repo_root" ] || continue
  printf '%s\t%s\t%s\n' "$slug" "$state_dir" "$repo_root" >> "$TMP_LIST"
done

if [ ! -s "$TMP_LIST" ]; then
  exit 0
fi

TAB="$(printf '\t')"
{
  grep "^persona-engine${TAB}" "$TMP_LIST" || true
  grep -v "^persona-engine${TAB}" "$TMP_LIST" | LC_ALL=C sort
} | awk -F'\t' '!seen[$1]++' | while IFS=$'\t' read -r slug state_dir repo_root; do
  if [ "$SLUGS_ONLY" -eq 1 ]; then
    printf '%s\n' "$slug"
  else
    printf '%s\t%s\t%s\n' "$slug" "$state_dir" "$repo_root"
  fi
done
