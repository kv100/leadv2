#!/usr/bin/env bash
# leadv2-one-copy-drift.sh — SessionStart + PostToolUse:Bash drift check for
# APPLY-ONE-COPY-01.
#
# SessionStart: thin wrapper around leadv2-one-copy-convert.sh --check. Silent
# on a clean tree; on drift, prints the REGRESSION/BADLINK lines + tally
# prefixed with a warning marker. NEVER blocks the session — always exits 0
# regardless of the check's own verdict (a SessionStart hook must not gate a
# session on this).
#
# PostToolUse:Bash (merged 2026-08-27, T16 §7): the retired standalone
# leadv2-plugin-sync-drift-warn.sh lives here now — single hook, one report.
# When the completed Bash command invoked leadv2-plugin-sync.sh, the same run
# ALSO re-checks leadv2-drift-guard.sh (5-way script-copy drift) and appends
# its verdict to the SAME report block. Other PostToolUse commands exit
# silently (the next SessionStart still reports them).
#
# Suppress with LEADV2_ONE_COPY_DRIFT=0.
set -uo pipefail

[[ "${LEADV2_ONE_COPY_DRIFT:-1}" == "0" ]] && exit 0

# Read stdin ONCE up front. A PostToolUse payload (tool_name set) whose
# tool_input.command ran the plugin sync switches this invocation into
# post-sync mode. SessionStart payloads and empty stdin leave it at 0, and a
# PostToolUse event that did NOT run the sync exits before any check.
INPUT="$(cat 2>/dev/null || true)"
POST_SYNC=0
POST_TOOL=0
if [[ -n "$INPUT" ]]; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
    print('')
" 2>/dev/null || true)"
  POST_TOOL="$(printf '%s' "$PARSED" | sed -n '1p')"
  _SYNC_CMD="$(printf '%s' "$PARSED" | sed -n '2p')"
  if [[ -n "$POST_TOOL" ]]; then
    case "$_SYNC_CMD" in
      *leadv2-plugin-sync.sh*) POST_SYNC=1 ;;
      *) exit 0 ;;
    esac
  fi
fi

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

# Output cap (HOOK-OUTPUT-CAP-PLUGIN-01): a drifted tree can emit hundreds of
# REGRESSION/BADLINK lines (measured 46257 B at 2026-08-30 baseline) which is
# re-sent on every later turn once injected at SessionStart. A session needs
# the FACT (drifted, how many) and a path to the full list, not the list
# itself. The full detail is always written to disk regardless of size.
report=""
if [[ "$status" -ne 0 ]]; then
  DETAIL_LOG="${TMPDIR:-/tmp}/leadv2-one-copy-drift-detail.log"
  printf '%s' "$output" | grep -E '^\[one-copy\] (REGRESSION|BADLINK|tally)' > "$DETAIL_LOG" 2>/dev/null || true
  ITEM_COUNT="$(grep -cE '^\[one-copy\] (REGRESSION|BADLINK)' "$DETAIL_LOG" 2>/dev/null || true)"
  [[ -z "$ITEM_COUNT" ]] && ITEM_COUNT=0
  TALLY_LINE="$(grep -E '^\[one-copy\] tally' "$DETAIL_LOG" 2>/dev/null | head -1)"
  report='\342\232\240 one-copy drift'
  report="$report"$'\n'"${ITEM_COUNT} regression(s)/badlink(s). ${TALLY_LINE}"
  report="$report"$'\n'"Full list: ${DETAIL_LOG}"
fi

# Post-sync leg of the T16 §7 merge (was leadv2-plugin-sync-drift-warn.sh):
# a sync just ran, so the 5 script copies must agree too. --quiet = verdict
# only; the divergence detail lands in the log named in the warning. Absent
# drift-guard (older checkout) silently skips this leg.
if [[ "$POST_SYNC" == "1" ]]; then
  DRIFT_GUARD="${CANONICAL_ROOT}/plugins/leadv2/scripts/leadv2-drift-guard.sh"
  if [[ -f "$DRIFT_GUARD" ]]; then
    if ! bash "$DRIFT_GUARD" --quiet 2>/tmp/leadv2-drift-warn-detail.log; then
      warn="[drift-guard] WARNING: leadv2-plugin-sync.sh just ran but the 5 script copies still diverge. Details: /tmp/leadv2-drift-warn-detail.log (re-run: bash ${DRIFT_GUARD})"
      # The base report is SessionStart context, so it must remain on stdout.
      # This additional post-sync advisory belongs to the Bash hook diagnostic
      # channel and must not swallow that context.
      printf '%s\n' "$warn" >&2
    fi
  fi
fi

[[ -n "$report" ]] && printf '%b\n' "$report"

exit 0
