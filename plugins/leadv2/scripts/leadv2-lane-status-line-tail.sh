#!/usr/bin/env bash
# leadv2-lane-status-line-tail.sh — the ENTIRE budget-relevant half of the
# status line render (both jq reads + wrapped user command + git branch
# fallback + lane segment), factored out of leadv2-lane-status-line.sh so
# the caller can wrap the WHOLE thing under one outer `timeout`.
#
# B13 fix-round-3 (SUPERVISOR-AUDIT-01, review-verdict-3.md): fix-round-2 ran
# the two jq reads (settings.json lookup + stdin field extraction) in the
# CALLER, un-timed, before invoking this script — the reviewer measured 5 of
# 6 realistic cache-hit calls still over 300ms (up to 355ms) with that split,
# proof that leaving ANY step outside the timeout defeats an "end-to-end"
# budget no matter how cheap that step looks standalone (a jq spawn here is
# normally ~8ms, but "normally" is not a bound). Both jq reads now happen IN
# HERE, under the caller's single outer `timeout`, alongside the wrapped user
# command, git-branch fallback, and lane-segment calc that fix-round-2
# already bounded together. Six independent per-source timeouts (wrapped cmd
# 0.08 + branch 0.05 + resolver 0.08 + lane-calc python 0.1, plus this-
# machine process-spawn overhead of ~60-90ms/spawn) still would not bound the
# TOTAL on their own — only the caller's single deadline around this entire
# script does that.
#
# args: <input_json> <settings_json_path> <script_dir> <lane_cache_ttl_s> [out_file]
# stdout (only on full success): "<BASE> | <LANES>\n"
#
# B13 FIX-ROUND-4: caller now always invokes this DETACHED in the background
# (never synchronously, never under a caller-imposed timeout) — see
# leadv2-lane-status-line.sh. The optional 5th arg, when given, is the
# statusline's last-known-good cache file; this script writes its result
# there itself, atomically (tmp file + `mv`), so a concurrent foreground
# `cat` of that file never observes a partial write.
set -uo pipefail

INPUT="$1"; SETTINGS_JSON="$2"; SCRIPT_DIR="$3"; LANE_CACHE_TTL_S="$4"; OUT_FILE="${5:-}"

USER_CMD="$(jq -r '(.statusLine.command // "")' "$SETTINGS_JSON" 2>/dev/null || true)"

PARSED="$(printf '%s' "$INPUT" | jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // "?"),
  ((.context_window.remaining_percentage // "") | tostring)
' 2>/dev/null || true)"
CWD_FROM_INPUT="$(printf -- '%s' "$PARSED" | sed -n '1p')"
[[ -z "$CWD_FROM_INPUT" ]] && CWD_FROM_INPUT="$PWD"
MODEL="$(printf -- '%s' "$PARSED" | sed -n '2p')"
REMAINING="$(printf -- '%s' "$PARSED" | sed -n '3p')"

# Fallback is ALWAYS computed (a CONFIGURED-but-failing/timed-out user
# command must fall back here too, not regress to a bare "?").
DISP_CWD="${CWD_FROM_INPUT:-?}"
DISP_CWD="${DISP_CWD/#$HOME/~}"
FALLBACK_BASE="${MODEL:-?} in ${DISP_CWD}"
[[ -n "$REMAINING" && "$REMAINING" != "null" ]] && FALLBACK_BASE="${FALLBACK_BASE} ${REMAINING}% ctx"

BASE="" WRAPPED_OK=0
if [[ -n "$USER_CMD" ]]; then
  BASE="$(printf '%s' "$INPUT" | timeout -k 0.05 0.08 bash -c "$USER_CMD" 2>/dev/null || true)"
  [[ -n "$BASE" ]] && WRAPPED_OK=1
fi
[[ -z "$BASE" ]] && BASE="$FALLBACK_BASE"
[[ -z "$BASE" ]] && BASE="?"

if [[ "$WRAPPED_OK" != "1" ]]; then
  BRANCH="$(timeout 0.05 git -C "$CWD_FROM_INPUT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] && BASE="${BASE} (${BRANCH})"
fi

LANES="lanes ?"
CACHE_KEY="${CWD_FROM_INPUT//\//_}"
[[ -z "$CACHE_KEY" ]] && CACHE_KEY="default"
LANE_CACHE_FILE="${TMPDIR:-/tmp}/leadv2-statusline-lane-${CACHE_KEY}"

CACHE_FRESH=0
if [[ -f "$LANE_CACHE_FILE" ]]; then
  CACHE_MTIME="$(timeout 0.05 stat -f %m "$LANE_CACHE_FILE" 2>/dev/null || timeout 0.05 stat -c %Y "$LANE_CACHE_FILE" 2>/dev/null || echo 0)"
  NOW_S="${EPOCHSECONDS:-$(date +%s)}"
  CACHE_AGE=$(( NOW_S - CACHE_MTIME ))
  (( CACHE_AGE < LANE_CACHE_TTL_S )) && CACHE_FRESH=1
fi

if [[ "$CACHE_FRESH" == "1" ]]; then
  LANES="$(cat "$LANE_CACHE_FILE" 2>/dev/null || true)"
  [[ -z "$LANES" ]] && LANES="lanes ?"
else
  RESOLVER="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}/scripts/leadv2-state-path.sh"
  [[ -x "$RESOLVER" ]] || RESOLVER="${SCRIPT_DIR}/leadv2-state-path.sh"
  if [[ -x "$RESOLVER" ]]; then
    ACTIVE_YAML="$(PROJECT_ROOT="$CWD_FROM_INPUT" timeout 0.08 "$RESOLVER" --no-link active.yaml 2>/dev/null || true)"
    if [[ -n "$ACTIVE_YAML" && -f "$ACTIVE_YAML" ]]; then
      LANES="$(timeout 0.1 python3 -c "
import sys, os, time, glob
try:
    import yaml
except Exception:
    print('lanes ?'); sys.exit(0)

path, root, cache_file = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding='utf-8') as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    print('lanes ?'); sys.exit(0)

meta = data.get('meta') or {}
cap = meta.get('hard_limit', '?')
sessions = data.get('sessions') or []
n = len(sessions)

def lane_log(s):
    # B14 fix: consult the row's own log_path first (dispatch-code.sh
    # funnel lanes never write under docs/handoff/<task_id>/) — same
    # precedence as leadv2-lane-liveness.sh's resolve(). Never falls back to
    # the self-reported pulse_log field.
    tid = str(s.get('task_id', '?'))
    raw_log_path = s.get('log_path')
    if raw_log_path:
        candidate = raw_log_path if os.path.isabs(raw_log_path) else os.path.join(root, raw_log_path)
        if os.path.isfile(candidate):
            return candidate
    lane_dir = os.path.join(root, 'docs', 'handoff', tid)
    candidates = [os.path.join(lane_dir, 'session.log'), os.path.join(lane_dir, 'fanout.log')]
    existing = [p for p in candidates if os.path.isfile(p)]
    if existing:
        return max(existing, key=lambda p: os.path.getmtime(p))
    try:
        files = [p for p in glob.glob(os.path.join(lane_dir, '*')) if os.path.isfile(p)]
    except Exception:
        files = []
    return max(files, key=lambda p: os.path.getmtime(p)) if files else None

parts = [f'lanes {n}/{cap}']
now = time.time()
for s in sessions[:8]:  # bound render width
    tid = str(s.get('task_id', '?'))
    phase = str(s.get('phase', '?'))
    log = lane_log(s)
    age_s = None
    if log:
        try:
            age_s = int(now - os.path.getmtime(log))
        except Exception:
            age_s = None
    if age_s is None:
        age = '?'
    elif age_s < 60:
        age = f'{age_s}s'
    elif age_s < 3600:
        age = f'{age_s // 60}m'
    else:
        age = f'{age_s // 3600}h'
    parts.append(f'{tid[:12]}:{phase}:{age}')

out = ' | '.join(parts)
print(out)
try:
    with open(cache_file, 'w', encoding='utf-8') as fh:
        fh.write(out)
except Exception:
    pass
" "$ACTIVE_YAML" "$CWD_FROM_INPUT" "$LANE_CACHE_FILE" 2>/dev/null || true)"
      [[ -z "$LANES" ]] && LANES="lanes ?"
    fi
  fi
  [[ -f "$LANE_CACHE_FILE" ]] || printf '%s' "$LANES" > "$LANE_CACHE_FILE" 2>/dev/null || true
fi

FINAL_LINE="$(printf '%s | %s' "$BASE" "$LANES")"
printf '%s\n' "$FINAL_LINE"

if [[ -n "$OUT_FILE" ]]; then
  OUT_TMP="${OUT_FILE}.tmp.$$"
  if printf '%s' "$FINAL_LINE" > "$OUT_TMP" 2>/dev/null; then
    mv -f "$OUT_TMP" "$OUT_FILE" 2>/dev/null || rm -f "$OUT_TMP" 2>/dev/null
  fi
fi
