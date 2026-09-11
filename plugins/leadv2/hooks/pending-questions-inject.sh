#!/usr/bin/env bash
# pending-questions-inject.sh — put unanswered lane questions in front of the supervisor
# automatically, at zero extra turns.
#
# WHY THIS EXISTS (2026-07-29, founder): the question channel delivers into the background
# supervise LOOP. When the supervisor is driven by hand there is no loop, so a lane could ask
# and then sit until its timeout while nobody ever saw it — 13 questions accumulated this way,
# some over a day old, and three live lanes stalled 30-50 minutes each. A background Monitor
# was tried and rejected: it costs a turn per event. A hook costs nothing — it rides on a
# message the supervisor was already going to receive.
#
# Wired as a UserPromptSubmit hook. Prints nothing when there is nothing pending, so it is
# silent on the overwhelming majority of turns.
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

# --- delta-gate (TOKEN-ECONOMY-ACTIONS-01) -------------------------------
# This block re-injected byte-identical text on EVERY prompt, breaking the
# prompt-cache prefix (identical anchor text should be a cache hit, not a
# fresh re-send). Session id comes from stdin JSON; fall back to $PPID.
# Fail-open by construction: the ONLY way to suppress output below is the
# explicit hash-match branch — any error, missing tool, or missing cache
# file falls through to printing + (best-effort) caching the output.
INPUT_JSON="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT_JSON" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || SESSION_ID="$PPID"
CACHE_FILE="/tmp/pe-inject-cache-pending-questions-${SESSION_ID}"

pending=()

# Legacy per-task store: a question is open when no *-answered.yaml sibling exists.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "${f%-pending.yaml}-answered.yaml" ] && continue
  pending+=("$f")
done < <(ls -1 docs/handoff/*/questions-async/*-pending.yaml 2>/dev/null)

# Control-plane store: status field carries the state.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qs '^status: pending' "$f" 2>/dev/null && pending+=("$f")
done < <(ls -1 docs/leadv2/questions/*.yaml 2>/dev/null)

[ "${#pending[@]}" -eq 0 ] && exit 0

OUTPUT="$(
  echo "<pending-lane-questions>"
  echo "Лейны ждут ответа. Пока вопрос без ответа, лейн стоит — ответь через"
  echo "\`bash .claude/scripts/leadv2-reply-router.sh <qid> <вариант>\` в этом же ходу."
  n=0
  for f in "${pending[@]}"; do
    n=$((n+1))
    [ "$n" -gt 8 ] && { echo "… и ещё $(( ${#pending[@]} - 8 ))"; break; }
    qid=$(grep -m1 '^qid:' "$f" 2>/dev/null | awk '{print $2}')
    q=$(grep -m1 '^question:' "$f" 2>/dev/null | cut -c1-200)
    opts=$(grep -A1 '^- label:' "$f" 2>/dev/null | grep -E 'label:|text:' | tr '\n' ' ' | cut -c1-160)
    echo "- ${qid:-?} :: ${q}"
    [ -n "$opts" ] && echo "    варианты: ${opts}"
  done
  echo "</pending-lane-questions>"
)"

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

printf '%s\n' "$OUTPUT"
[ -n "$HASH" ] && printf '%s\n' "$HASH" > "$CACHE_FILE" 2>/dev/null
exit 0
