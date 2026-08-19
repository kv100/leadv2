#!/usr/bin/env bash
# UserPromptSubmit hook — hard turn-cap gate (TOKEN-ECONOMY-ACTIONS-01).
#
# Counts real user turns SINCE THE LAST /compact boundary in the live
# transcript (byte-offset scan, not a full-file parse — stays fast even on a
# 200MB+ transcript). >=70 turns since last compact -> WARN (stdout, exit 0).
# >=80 -> BLOCK (exit 2, stderr) with two escape hatches so a false-positive
# can never lock out a session.
#
# Counting method:
#   1. Find the byte offset of the LAST compact_boundary system line via
#      `grep -abo` (a single linear scan, ~O(file size) but grep is fast
#      enough to stay well under 300ms even on 200-300MB transcripts — see
#      timing notes in the report).
#   2. tail -c +OFFSET streams only the bytes AFTER that boundary; grep -c
#      counts lines that look like a real user prompt (type":"user", not a
#      tool_result echo, not isMeta).
#   3. If no boundary exists yet (fresh session, never compacted), count
#      user turns over the whole file — same filter.
#
# Escape hatches (mandatory — a mis-tuned counter must never cause a lockout):
#   LEADV2_TURNCAP_OFF=1                       -> exit 0 unconditionally
#   /tmp/leadv2-turncap-off-<session_id>        -> exit 0 unconditionally
#
# bash 3.2 (macOS) compatible: no associative arrays, no ${x,,}.

set -euo pipefail
trap 'echo "[$0] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_TURNCAP_OFF:-0}" == "1" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

SESSION_ID="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    print(r.get('session_id', ''))
except Exception:
    pass
" 2>/dev/null || true)"

if [[ -n "$SESSION_ID" ]] && [[ -f "/tmp/leadv2-turncap-off-${SESSION_ID}" ]]; then
    exit 0
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    print(r.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null || true)"

[[ -z "$TRANSCRIPT" ]] && exit 0
[[ ! -r "$TRANSCRIPT" ]] && exit 0

WARN_THRESHOLD="${LEADV2_TURNCAP_WARN:-70}"
HARD_THRESHOLD="${LEADV2_TURNCAP_HARD:-80}"
[[ "$WARN_THRESHOLD" =~ ^[0-9]+$ ]] || WARN_THRESHOLD=70
[[ "$HARD_THRESHOLD" =~ ^[0-9]+$ ]] || HARD_THRESHOLD=80

# --- find byte offset of the LAST compact boundary ----------------------------
# A plain `grep -abo` over the whole file must scan it all to be sure it found
# the LAST match, which is ~4s on a 260MB transcript — too slow for a
# per-prompt gate. Instead we search backward-from-EOF in doubling windows
# (2MB, 16MB, 128MB, ... whole file): the common case (a compact somewhere in
# the recent tail) resolves in the first 1-2 iterations, and only a
# never-compacted multi-hundred-MB session falls through to a full scan.
FILE_SIZE="$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)"
FILE_SIZE="${FILE_SIZE//[$'\n\r ']/}"
[[ "$FILE_SIZE" =~ ^[0-9]+$ ]] || FILE_SIZE=0

OFFSET=""
WINDOW=40000000
while :; do
    if [[ "$WINDOW" -ge "$FILE_SIZE" ]]; then
        CHUNK_START=0
        CAND="$(grep -abo '"subtype":"compact_boundary"' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
        [[ -n "$CAND" ]] && OFFSET="$CAND"
        break
    fi
    CHUNK_START=$(( FILE_SIZE - WINDOW ))
    CAND="$(tail -c "$WINDOW" "$TRANSCRIPT" 2>/dev/null | grep -abo '"subtype":"compact_boundary"' | tail -1 | cut -d: -f1 || true)"
    if [[ -n "$CAND" ]] && [[ "$CAND" =~ ^[0-9]+$ ]]; then
        OFFSET=$(( CHUNK_START + CAND ))
        break
    fi
    WINDOW=$(( WINDOW * 8 ))
done

count_user_turns() {  # $1 = stream (stdin)
    grep '"type":"user"' \
    | grep -v '"isMeta":true' \
    | grep -vc '"toolUseResult"'
}

if [[ -n "$OFFSET" ]] && [[ "$OFFSET" =~ ^[0-9]+$ ]]; then
    # tail -c +N is 1-indexed FROM the offset; +1 to skip the boundary line's
    # own start (harmless either way since it's type":"system", not "user").
    COUNT="$(tail -c +"$((OFFSET + 1))" "$TRANSCRIPT" 2>/dev/null | count_user_turns || echo 0)"
else
    COUNT="$(count_user_turns < "$TRANSCRIPT" || echo 0)"
fi
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -ge "$HARD_THRESHOLD" ]]; then
    echo "TURN-CAP-GATE: 80+ turns since last compact. Run /compact (or set LEADV2_TURNCAP_OFF=1 to bypass)." >&2
    exit 2
fi

if [[ "$COUNT" -ge "$WARN_THRESHOLD" ]]; then
    echo "TURN-CAP: ${COUNT} turns since last compact — run /compact within 10 turns"
fi

exit 0
