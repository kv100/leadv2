#!/usr/bin/env bash
# leadv2-one-copy-drift.sh — SessionStart drift check for APPLY-ONE-COPY-01.
#
# Thin wrapper around leadv2-one-copy-convert.sh --check. Silent on a clean
# tree; on drift, prints the REGRESSION/BADLINK lines + tally prefixed with a
# warning marker. NEVER blocks the session — always exits 0 regardless of the
# check's own verdict (a SessionStart hook must not gate a session on this).
#
# Suppress with LEADV2_ONE_COPY_DRIFT=0.
set -uo pipefail

[[ "${LEADV2_ONE_COPY_DRIFT:-1}" == "0" ]] && exit 0

# Resolve the canonical repo. CLAUDE_PLUGIN_ROOT may point at the plugin
# CACHE (~/.claude/plugins/local/leadv2/...), not the git-tracked repo this
# hook needs to compare against — fall back to ~/Projects/leadv2 and confirm
# it's a real git checkout before trusting it (R7).
resolve_canonical_root() {
  local candidate="${CLAUDE_PLUGIN_ROOT:-}/../.."
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -d "$candidate/.git" ]]; then
    (cd "$candidate" && pwd)
    return 0
  fi
  if [[ -d "${HOME}/Projects/leadv2/.git" ]]; then
    printf '%s\n' "${HOME}/Projects/leadv2"
    return 0
  fi
  return 1
}

CANONICAL_ROOT="$(resolve_canonical_root)" || { exit 0; }
CONVERT_SCRIPT="${CANONICAL_ROOT}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh"
[[ -x "$CONVERT_SCRIPT" || -f "$CONVERT_SCRIPT" ]] || exit 0

# Shared/non-blocking lock read: if an --apply is mid-run, don't report a torn
# tally — just say so and exit clean.
LOCK_FILE="${HOME}/.claude/.one-copy.lock"
FLOCK_BIN="$(command -v flock || true)"
if [[ -n "$FLOCK_BIN" && -e "$LOCK_FILE" ]]; then
  if ! "$FLOCK_BIN" -sn 9 9>"$LOCK_FILE" 2>/dev/null; then
    printf 'one-copy: conversion in progress, skipped\n'
    exit 0
  fi
fi

output="$(bash "$CONVERT_SCRIPT" --check 2>&1)"
status=$?

if [[ "$status" -ne 0 ]]; then
  printf '\342\232\240 one-copy drift\n'
  printf '%s\n' "$output" | grep -E '^\[one-copy\] (REGRESSION|BADLINK|tally)'
fi

exit 0
