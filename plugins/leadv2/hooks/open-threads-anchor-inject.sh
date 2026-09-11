#!/usr/bin/env bash
# open-threads-anchor-inject.sh — D-4 ANCHOR-ROT.
#
# WHY THIS EXISTS: the plugin's <task-anchor> block
# (~/Projects/leadv2/plugins/leadv2/hooks/leadv2-task-anchor.sh) reads the
# LAST 8 non-blank lines of docs/leadv2/open-threads.md verbatim — an
# arbitrary tail window that whatever a writer last appended controls, with
# no recency ranking, no staleness marking, and no omitted-count. Editing
# that plugin file is off limits (three plugin lanes in flight; the file is
# also shared across 3 other repos). This hook satisfies the plugin's
# existing contract from OUR side instead: it regenerates the file so its
# physical tail non-blank lines ARE a curated digest
# (.claude/scripts/open-threads-digest.py), then prints that same digest
# itself as belt-and-braces (Lever B) in case hook ordering races the
# plugin's read in the same UserPromptSubmit batch — worst case then is a
# one-turn-stale plugin block next to a current <thread-digest>, never a
# silent lie.
#
# Fail-open: the anchor is context, not a gate. Any failure (missing
# python3, non-zero exit, timeout) must never block prompt submit.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

DIGEST="${ROOT}/.claude/scripts/open-threads-digest.py"
[ -f "$DIGEST" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "${ROOT}/docs/leadv2/open-threads.md" ] || exit 0

timeout 3 python3 "$DIGEST" --apply >/dev/null 2>/dev/null

# OPEN-THREADS-BOARD-GUARD-01: the digest refuses to write (and stops
# updating) when it finds duplicate/unbalanced HEAD or TAIL markers, or a
# shrink it can't explain from archived entries. That refusal is otherwise
# invisible -- this caller discards both stdout and stderr above, fail-open
# by design. Surface it as one line so the board doesn't silently go stale.
BLOCKED_BREADCRUMB="${ROOT}/docs/leadv2/.open-threads-digest-blocked"
if [ -f "$BLOCKED_BREADCRUMB" ]; then
  printf '<thread-digest>\nWARNING: open-threads.md digest is BLOCKED (not updating) -- %s\n</thread-digest>\n' \
    "$(cat "$BLOCKED_BREADCRUMB" 2>/dev/null | head -1)"
  exit 0
fi

tail_block="$(timeout 2 python3 "$DIGEST" --render-tail 2>/dev/null)"
[ -n "$tail_block" ] || exit 0

OUTPUT="$(printf '<thread-digest>\n%s\n</thread-digest>\n' "$tail_block")"

# --- delta-gate (TOKEN-ECONOMY-ACTIONS-01) -------------------------------
# The digest re-rendered byte-identical text on EVERY prompt when nothing in
# open-threads.md changed, breaking the prompt-cache prefix. Fail-open by
# construction: the ONLY way to suppress printing below is the explicit
# hash-match branch — any error, missing tool, or missing cache falls
# through to printing (+ best-effort caching).
INPUT_JSON="${INPUT_JSON:-}"
[ -n "$INPUT_JSON" ] || INPUT_JSON="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT_JSON" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || SESSION_ID="$PPID"
CACHE_FILE="/tmp/pe-inject-cache-open-threads-${SESSION_ID}"

HASH=""
if command -v md5 >/dev/null 2>&1; then
  HASH="$(printf '%s' "$OUTPUT" | md5 2>/dev/null || true)"
elif command -v md5sum >/dev/null 2>&1; then
  HASH="$(printf '%s' "$OUTPUT" | md5sum 2>/dev/null | awk '{print $1}')"
fi

if [ -n "$HASH" ] && [ -f "$CACHE_FILE" ]; then
  PREV_HASH="$(head -1 "$CACHE_FILE" 2>/dev/null || true)"
  MTIME="$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
  NOW="$(date +%s 2>/dev/null || echo 0)"
  AGE=$(( NOW - MTIME ))
  if [ "$PREV_HASH" = "$HASH" ] && [ "$AGE" -lt 1800 ] && [ "$AGE" -ge 0 ]; then
    exit 0
  fi
fi

printf '%s' "$OUTPUT"
[ -n "$HASH" ] && printf '%s\n' "$HASH" > "$CACHE_FILE" 2>/dev/null
exit 0
