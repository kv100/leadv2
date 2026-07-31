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

# FIX5c: fallback is ALWAYS computed (a CONFIGURED-but-failing/timed-out
# user command must fall back here too, not regress to a bare "?") — and it
# must share leadv2-lane-status-line.sh's own colorized renderer, not a
# hand-copy, so this fallback and the hot path's cache-miss fallback can
# never drift into two different palettes (or the same tilde-escaping bug)
# again. One extra bash fork to source it is negligible on this already-
# detached, multi-spawn path.
# shellcheck source=leadv2-lane-status-line.sh
source "${SCRIPT_DIR}/leadv2-lane-status-line.sh" 2>/dev/null || true
if declare -F _leadv2_render_colored_base >/dev/null 2>&1; then
  FALLBACK_BASE="$(_leadv2_render_colored_base "${MODEL:-?}" "$CWD_FROM_INPUT" "" "$REMAINING")"
else
  FALLBACK_BASE="${MODEL:-?} in ${CWD_FROM_INPUT}"
fi

# FIX5c (SUPERVISOR-AUDIT-01): B13 fix-round-4 made this ENTIRE script run
# detached and awaited by NOTHING (see leadv2-lane-status-line.sh) — so
# these per-step timeouts are no longer a UI-latency budget, only a
# hang-safety-net. They were still left at their old fix-round-3 values
# (0.05-0.1s) from when a caller-imposed outer timeout made every millisecond
# count. On THIS machine a single jq/git/python3 fork+exec alone costs
# 60-150ms (measured directly: the wrapped user command takes 110-150ms,
# the state-path resolver 100-110ms) — comfortably over every one of those
# budgets — so USER_CMD, the git-branch fallback, and the lane resolver were
# timing out on 100% of calls, not occasionally. Generous now that nothing
# downstream waits on this script.
BASE="" WRAPPED_OK=0
if [[ -n "$USER_CMD" ]]; then
  BASE="$(printf '%s' "$INPUT" | timeout -k 0.2 2 bash -c "$USER_CMD" 2>/dev/null || true)"
  [[ -n "$BASE" ]] && WRAPPED_OK=1
fi
[[ -z "$BASE" ]] && BASE="$FALLBACK_BASE"
[[ -z "$BASE" ]] && BASE="?"

if [[ "$WRAPPED_OK" != "1" ]]; then
  BRANCH="$(timeout 1 git -C "$CWD_FROM_INPUT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] && BASE="${BASE} (${BRANCH})"
fi

# D4 (dispatch-98cc5cf7, founder ask): the founder's own burn statusline.sh
# appends " | 5h:<used> ↑<pct>%" after the FIRST " | " in its own output --
# that segment's width belongs to the lanes now. Flag-gated (not a mutation
# of the founder's own script) so `=0` restores it in one flip.
if [[ "${LEADV2_STATUSLINE_DROP_BURN:-1}" == "1" ]]; then
  BASE="${BASE%% | *}"
fi

# D6 (STATUSLINE fix round 2): the WHOLE line must fit, not just the lane
# segment -- DIGEST_BUDGET used to be a flat default (100) with no relation
# to how much width BASE itself already consumed, so a real BASE (colorized
# model/cwd/ctx%) plus a "full-budget" lane digest routinely wrapped past 80
# cols. Width precedence: an explicit override, else the terminal's own
# COLUMNS (set by the shell that invoked this render), else 80 -- no `tput`
# fork; this script always runs detached with no tty, and `tput` would
# report 80 there anyway. BASE_VISIBLE_LEN strips ANSI color codes before
# measuring -- an escape sequence costs stdin bytes but zero terminal cells.
STATUSLINE_WIDTH="${LEADV2_STATUSLINE_WIDTH:-${COLUMNS:-80}}"
BASE_VISIBLE_LEN="$(printf '%s' "$BASE" | sed -E $'s/\x1b\\[[0-9;]*m//g' | awk '{print length}')"
[[ -z "$BASE_VISIBLE_LEN" ]] && BASE_VISIBLE_LEN=0

LANES="lanes ?"
# STATUSLINE-DESTROYS-PROBER-01: every cache/memo path this script can ever
# write is derived from this ONE dir, never from a binary's own path -- the
# structural guard below (safe_replace / _leadv2_statusline_safe_write)
# allowlists writes against exactly this resolved dir.
CACHE_DIR="${TMPDIR:-/tmp}"

# STATUSLINE-DESTROYS-PROBER-01 Step 1: bash-side mirror of the python
# safe_replace guard, for the one write this script performs outside the
# embedded python block (line ~748 below). Refuses the same four ways.
_leadv2_statusline_safe_write() {
  local dest="$1" content="$2"
  case "$dest" in
    "$CACHE_DIR"/*) ;;
    *) return 1 ;;
  esac
  [[ -x "$dest" ]] && return 1
  case "$(basename -- "$dest")" in
    *.sh|*.py|*.js) return 1 ;;
  esac
  [[ "$(basename -- "$(dirname -- "$dest")")" == "scripts" ]] && return 1
  printf '%s' "$content" > "$dest" 2>/dev/null
}

CACHE_KEY="${CWD_FROM_INPUT//\//_}"
[[ -z "$CACHE_KEY" ]] && CACHE_KEY="default"
LANE_CACHE_FILE="${CACHE_DIR}/leadv2-statusline-lane-${CACHE_KEY}"
# D1.5/R6 (dispatch-98cc5cf7): same CACHE_KEY formula as the hot path
# (leadv2-lane-status-line.sh derives its own key from `${PWD//\//_}`) --
# load-bearing: if the two ever diverge, the sidecar is written under a key
# the hot path never reads and it falls back to "lanes ?" forever. Verified
# by test-leadv2-lane-status-line.sh (both scripts invoked against the same
# CWD_FROM_INPUT/$PWD in the fixture).
COUNT_SIDECAR_FILE="${CACHE_DIR}/leadv2-statusline-lanecount-${CACHE_KEY}"

RESOLVER="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}/scripts/leadv2-state-path.sh"
[[ -x "$RESOLVER" ]] || RESOLVER="${SCRIPT_DIR}/leadv2-state-path.sh"

# FIX5d (SUPERVISOR-AUDIT-01 follow-up): task-name digest instead of raw id.
# id→label memo lives alongside the lane cache so a resolved label is never
# re-fetched on the next paint (only a NEW task_id costs a tasks-lib call).
TASKS_LIB="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}/scripts/leadv2-tasks-lib.sh"
[[ -f "$TASKS_LIB" ]] || TASKS_LIB="${SCRIPT_DIR}/leadv2-tasks-lib.sh"
LABEL_MEMO_FILE="${LANE_CACHE_FILE}.labels"

# FIX5e (SUPERVISOR-AUDIT-01): a "review:35m" digest entry looks alive even
# when the worker behind it already exited (review FAIL, no restart yet) --
# the founder's live repro was exactly this: age from the phase's own log
# mtime kept ticking harmlessly while the process was gone. Append the
# authoritative leadv2-lane-liveness.sh verdict (never a hand-rolled PID/age
# guess here, so this can never drift from supervise.sh's own prune logic)
# for the SAME top-2 lanes already selected below. Memo-cached ~10s (own
# file, not folded into LANE_CACHE_FILE/LABEL_MEMO_FILE's TTLs) because the
# liveness script forks python3 + stat + an optional codex-task.sh call per
# lane, and this tail script can repaint far more often than a lane's true
# liveness changes.
LIVENESS_BIN="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}/scripts/leadv2-lane-liveness.sh"
[[ -x "$LIVENESS_BIN" ]] || LIVENESS_BIN="${SCRIPT_DIR}/leadv2-lane-liveness.sh"
# STATUSLINE-DESTROYS-PROBER-01 E6: a corpse (JSON overwrite, mode 0644)
# leaves neither candidate executable -- fail CLOSED instead of handing a
# non-executable path to `bash` on every single repaint forever. Empty
# LIVENESS_BIN means "skip the subprocess entirely" below.
[[ -x "$LIVENESS_BIN" ]] || LIVENESS_BIN=""
LIVENESS_MEMO_FILE="${LANE_CACHE_FILE}.liveness"
LIVENESS_MEMO_TTL_S="${LEADV2_LANE_LIVENESS_MEMO_TTL_S:-10}"

# STATUSLINE-DESTROYS-PROBER-01 Step 0: opt-in repaint trace, never on by
# default (this script repaints far too often to log unconditionally).
if [[ "${LEADV2_STATUSLINE_TRACE:-0}" == "1" ]]; then
  printf '%s %s %s %s %s %s %s %s\n' \
    "$$" "${PPID:-?}" "${CLAUDE_PLUGIN_ROOT:-}" "$SCRIPT_DIR" \
    "$LANE_CACHE_FILE" "$LIVENESS_BIN" "$LIVENESS_MEMO_FILE" "$(date +%s 2>/dev/null || echo 0)" \
    >> "${CACHE_DIR}/leadv2-statusline-trace.log" 2>/dev/null || true
fi

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
  # FIX5c: `-f "$ACTIVE_YAML"` used to gate the WHOLE lane calc — but the
  # resolver ALWAYS returns a path (it constructs one even for a file that
  # doesn't exist yet), so "no /leadv2 session has ever run in this repo" is
  # a completely normal state, not an error, and must still render "lanes
  # 0/<cap>", never "lanes ?". Gate only on the resolver call itself having
  # produced a path at all (a true resolve failure/timeout).
  LIMITS_YAML="${CWD_FROM_INPUT}/.claude/leadv2-overrides/active-limits.yaml"
  if [[ -x "$RESOLVER" ]]; then
    ACTIVE_YAML="$(PROJECT_ROOT="$CWD_FROM_INPUT" timeout 1 "$RESOLVER" --no-link active.yaml 2>/dev/null || true)"
    if [[ -n "$ACTIVE_YAML" ]]; then
      # FIX5e: this python block now shells out to leadv2-lane-liveness.sh
      # for up to 2 lanes (its own subprocess.run each budgeted at 2s below)
      # -- measured standalone at ~0.9s per call (python3 + stat + an
      # optional codex-task.sh probe), so the pre-fix5e outer `timeout 1`
      # killed the WHOLE lane calc on every cache-miss run that hit an
      # uncached lane, not just the liveness lookup (confirmed: 2 of 3 live
      # runs regressed all the way to "lanes ?"). Same FIX5c reasoning
      # applies: this script only ever runs detached in the background, so a
      # generous outer bound here costs nothing downstream.
      LANES="$(PROJECT_ROOT="$CWD_FROM_INPUT" timeout "${LEADV2_LANE_CALC_TIMEOUT_S:-10}" python3 -c "
import json, sys, os, time, glob, subprocess
try:
    import yaml
except Exception:
    print('lanes ?'); sys.exit(0)

path, root, cache_file, limits_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = {}
if os.path.isfile(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = yaml.safe_load(fh) or {}
    except Exception:
        # A file that EXISTS but fails to parse is a true read error.
        print('lanes ?'); sys.exit(0)
# A file that does not exist yet (no /leadv2 session ever ran here) is a
# normal empty state, not an error — data stays {} and n resolves to 0 below.

meta = data.get('meta') or {}
sessions = data.get('sessions') or []
# D2 (dispatch-98cc5cf7): n is now recomputed below from the authoritative
# liveness payload's count_live once it is fetched -- len(sessions) is only
# the pre-liveness-call placeholder/fallback.
n = len(sessions)

# Cap precedence: active.yaml's own meta.hard_limit (set by the last real
# session) -> this repo's active-limits.yaml override -> the schema-
# documented default of 3 (see active-limits.yaml's own header comment).
cap = meta.get('hard_limit')
if cap is None and os.path.isfile(limits_path):
    try:
        with open(limits_path, encoding='utf-8') as fh:
            limits = yaml.safe_load(fh) or {}
        cap = limits.get('hard_limit')
    except Exception:
        cap = None
if cap is None:
    cap = 3

# ---- authoritative liveness: ONE batch call for ALL lanes ----
# C5 (STATUSLINE-SHOWS-LANES-QUESTIONMARK-01): lane_log() (a hand-rolled
# duplicate of leadv2-lane-liveness.sh's own path precedence) and a
# per-lane lane_verdict() subprocess are BOTH gone. This script now shells
# out to leadv2-lane-liveness.sh exactly ONCE per repaint (--all --json
# --no-codex), and that single authoritative payload is the sole source of
# BOTH age_s (sort order below) and verdict (digest suffix further down)
# for every lane -- N lanes now cost one process, not N, and there is only
# ONE place left that knows how to find a lane's artifact across its six
# possible shapes.
liveness_bin, liveness_memo_file, liveness_ttl_raw = sys.argv[7], sys.argv[8], sys.argv[9]
count_sidecar_file = sys.argv[10]
width_raw, base_visible_len_raw = sys.argv[11], sys.argv[12]
cache_dir_raw = sys.argv[13] if len(sys.argv) > 13 else ''
try:
    liveness_ttl = float(liveness_ttl_raw)
except ValueError:
    liveness_ttl = 10.0

# STATUSLINE-DESTROYS-PROBER-01: single chokepoint for every write this
# script performs. Refuses (never raises -- every caller below already
# swallows exceptions, so a raise here would be invisible) when the
# resolved destination is not under the resolved cache dir, is already an
# executable, looks like a script by extension, or lives in a directory
# named 'scripts'. A refusal is unconditionally traced -- it should never
# fire in normal operation, so the cost of always logging it is zero.
_CACHE_DIR_ABS = os.path.abspath(cache_dir_raw) if cache_dir_raw else None
_TRACE_ON = os.environ.get('LEADV2_STATUSLINE_TRACE') == '1'
_TRACE_LOG = os.path.join(_CACHE_DIR_ABS or '/tmp', 'leadv2-statusline-trace.log')

def _trace(msg):
    try:
        with open(_TRACE_LOG, 'a', encoding='utf-8') as tf:
            tf.write(f'{time.time()} {msg}\n')
    except Exception:
        pass

def safe_replace(tmp_path, dest_path):
    dest_abs = os.path.abspath(dest_path)
    refuse_reason = None
    if _CACHE_DIR_ABS is None or not (
        dest_abs == _CACHE_DIR_ABS or dest_abs.startswith(_CACHE_DIR_ABS + os.sep)
    ):
        refuse_reason = 'outside-cache-dir'
    elif os.path.exists(dest_abs) and os.access(dest_abs, os.X_OK):
        refuse_reason = 'target-executable'
    elif os.path.basename(dest_abs).endswith(('.sh', '.py', '.js')):
        refuse_reason = 'script-extension'
    elif os.path.basename(os.path.dirname(dest_abs)) == 'scripts':
        refuse_reason = 'scripts-dir'
    if refuse_reason:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        _trace(f'REFUSE {refuse_reason} dest={dest_abs}')
        return False
    if _TRACE_ON:
        _trace(f'safe_replace dest={dest_abs}')
    os.replace(tmp_path, dest_abs)
    return True

liveness_by_tid = {}
count_live = None
memo_fresh = False
if os.path.isfile(liveness_memo_file):
    try:
        if (time.time() - os.path.getmtime(liveness_memo_file)) < liveness_ttl:
            with open(liveness_memo_file, encoding='utf-8') as fh:
                memo_payload = json.load(fh)
            liveness_by_tid = memo_payload.get('lanes') or {}
            count_live = memo_payload.get('count_live')
            memo_fresh = True
    except Exception:
        liveness_by_tid = {}
        count_live = None
        memo_fresh = False
if not memo_fresh and liveness_bin:
    try:
        proc = subprocess.run(
            ['bash', liveness_bin, '--project-root', root, '--all', '--json', '--no-codex'],
            capture_output=True, text=True, timeout=8,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            payload = json.loads(proc.stdout)
            liveness_by_tid = {str(row.get('lane')): row for row in (payload.get('lanes') or [])
                                if isinstance(row, dict) and row.get('lane')}
            count_live = payload.get('count_live')
    except Exception:
        liveness_by_tid = {}
        count_live = None
    # C8: tmp + safe_replace so a concurrent repaint's read of this file
    # never observes a partial write (repaints are throttled to every ~2s
    # but run detached, so two can overlap).
    try:
        tmp_path = f'{liveness_memo_file}.tmp.{os.getpid()}'
        with open(tmp_path, 'w', encoding='utf-8') as fh:
            json.dump({'lanes': liveness_by_tid, 'count_live': count_live}, fh)
        safe_replace(tmp_path, liveness_memo_file)
    except Exception:
        pass

# D1.5 (dispatch-98cc5cf7): count sidecar written IMMEDIATELY after a
# successful liveness read, before any label/digest work below -- a later
# digest failure (PyYAML missing, tasks-lib timeout, ...) can no longer
# erase a count that was already computable. The hot path
# (leadv2-lane-status-line.sh) reads this file as its cache-miss fallback
# instead of a bare 'lanes ?'.
# STATUSLINE-DESTROYS-PROBER-01 Step 3: additionally gated on liveness_bin
# -- an unusable prober must never let a stale sidecar masquerade as a
# freshly-confirmed count (the hot path treats this file's mere presence as
# fresh-enough, so refreshing its mtime from a dead source is a lie).
if count_live is not None and liveness_bin:
    try:
        tmp_path = f'{count_sidecar_file}.tmp.{os.getpid()}'
        with open(tmp_path, 'w', encoding='utf-8') as fh:
            fh.write(f'lanes {count_live}/{cap}')
        safe_replace(tmp_path, count_sidecar_file)
    except Exception:
        pass

# D2 (dispatch-98cc5cf7): the count and the row set now come straight from
# the authoritative liveness payload -- NOT from active.yaml's own
# sessions list, which misses every lane launched outside
# leadv2-fanout.sh's registration path (the direct-dispatch-code gap this
# task exists to fix). sessions_by_tid is kept as a DECORATION lookup only
# (kind/model/title), never as the source of which lanes exist or how many.
now = time.time()
sessions_by_tid = {str(s.get('task_id', '?')): s for s in sessions if isinstance(s, dict)}
# D4 (STATUSLINE fix round 2): len(sessions) as a fallback here rendered a
# CONFIDENT lanes 0/5 whenever the liveness read failed (subprocess
# timeout/crash/bad JSON) and active.yaml's own sessions list was also empty
# or absent -- indistinguishable, on the line, from genuinely zero lanes
# running. An unreadable count and an empty count are not the same fact;
# only one of them is true. Render the honest unknown instead.
n = count_live if count_live is not None else '?'

def _is_live_verdict(verdict):
    # D3/D6 (STATUSLINE fix round 2): the --all id set was deliberately
    # widened (silent_max -> discovery_max) to fix the --lane vs --all
    # flicker -- but that widened set now also carries lanes past
    # abandon_max, which leadv2-lane-liveness.sh itself already resolves to
    # a 'dead:*' verdict. Rendering EVERY id the widened set surfaces would
    # put hours/days-old dead lanes back on the line permanently -- the same
    # disease D1 just fixed for the count. Only alive/starting/silent
    # (silent:* is only ever emitted for age <= abandon_max, see
    # leadv2-lane-liveness.sh resolve()) reach the digest.
    if not isinstance(verdict, str):
        return False
    return verdict == 'alive' or verdict.startswith('starting:') or verdict.startswith('silent:')

rows = []
for lane_id, lrow in liveness_by_tid.items():
    verdict = lrow.get('verdict')
    if not _is_live_verdict(verdict):
        continue
    rows.append((lrow.get('age_s'), lane_id, verdict))

# Pulse digest (founder ask, fix5 attempt 2): only the top-2 MOST
# recently-active lanes, not the first 8 in file order — smallest age_s
# first; unknown-age lanes (no discoverable log) sort last, never first.
# STATUSLINE-COUNT-TRUTH-01 (3.4): stale (silent:*) rows stay visible but
# sort AFTER every counted (alive/starting) row, so the digest reads as
# "what's actually working" followed by "what's stale", never interleaved --
# separated, not deleted. Verdict is still on each token as a '·silent'
# suffix (unchanged, below), so which group a row is in stays legible.
rows.sort(key=lambda r: (
    isinstance(r[2], str) and r[2].startswith('silent:'),
    r[0] is None,
    r[0] if r[0] is not None else 0,
))

# FIX5d: task-name digest instead of a raw id. Precedence: the active.yaml
# row's own title/mission field (not populated by any current schema, but
# a cheap free win if a future writer adds one) -> the label memo (a prior
# tail-script run already resolved this task_id) -> docs/tasks.yaml via
# leadv2-tasks-lib.sh's own locked by_id op (never a raw yaml parse here —
# tasks.yaml can be mid-write by a concurrent lane). Falls back to the raw
# id if every source comes up empty, so the digest never renders blank.
LABEL_CAP = 24
label_memo_file, tasks_lib_path = sys.argv[5], sys.argv[6]
label_memo = {}
if os.path.isfile(label_memo_file):
    try:
        with open(label_memo_file, encoding='utf-8') as fh:
            for line in fh:
                line = line.rstrip('\n')
                if '\t' in line:
                    k, v = line.split('\t', 1)
                    label_memo[k] = v
    except Exception:
        label_memo = {}

def cap_label(text, label_cap):
    text = text.strip()
    label_cap = max(label_cap, 1)
    if len(text) <= label_cap:
        return text
    return text[:label_cap - 1] + '…' if label_cap > 1 else '…'

def prepass_label(tid):
    # D5 (STATUSLINE fix round 2), step 3: a lane doing its own architect
    # prepass names ITSELF far better than any hash -- read it with a plain
    # open(), no fork, so this costs nothing against the label-resolution
    # budget below. First markdown heading wins; else the first non-empty
    # line. Collapsed to <=4 words so one long sentence never dominates the
    # digest the way a raw id used to.
    path = os.path.join(root, 'docs', 'handoff', tid, 'architect-prepass.md')
    try:
        with open(path, encoding='utf-8') as fh:
            lines = fh.readlines()
    except Exception:
        return None
    heading, first_line = None, None
    for raw_line in lines:
        stripped = raw_line.strip()
        if not stripped:
            continue
        if first_line is None:
            first_line = stripped
        if stripped.startswith('# '):
            heading = stripped[2:].strip()
            break
    text = heading or first_line
    if not text:
        return None
    for marker in ('#', '*', '_'):
        text = text.replace(marker, '')
    # Every architect-prepass.md heading observed in this repo follows the
    # same boilerplate shape ('Architect prepass -- fix round for
    # <TASK-NAME>') -- the first 4 words of THAT is 'Architect prepass --
    # fix' for every single lane, which is the exact indistinguishable-label
    # defect this fix exists to remove, just relocated from the hash to the
    # heading. The task name is the part that actually varies, and it always
    # follows the last ' for '/' FOR ' -- prefer that tail when present.
    lower = text.lower()
    marker_pos = lower.rfind(' for ')
    if marker_pos != -1:
        text = text[marker_pos + len(' for '):].strip()
    words = text.split()
    return ' '.join(words[:4]) if words else None

# D5 step 4: tasks-lib resolution is a subprocess per uncached lane -- cheap
# for one lane, unbounded for N. Cap it so a cold repaint with many lanes
# degrades to the raw-id fallback (step 5) for the overflow instead of
# blowing the whole tail script past its own timeout -- the exact
# 'cap the label work, not the id set' half of the D3 fix.
LABEL_RESOLVE_MAX = int(os.environ.get('LEADV2_STATUSLINE_LABEL_RESOLVE_MAX', '') or 4)
label_resolve_budget = [LABEL_RESOLVE_MAX]

def raw_label(tid, s):
    # Returns the UNCAPPED label text; capping is applied later, per-row,
    # once the digest-wide length budget is known (fix5d-addendum).
    # Precedence (D5): active.yaml title/mission -> label memo -> this
    # lane's own architect-prepass.md -> tasks-lib intent tag (rate-capped)
    # -> raw id (de-prefixed against its siblings in a later pass below).
    for key in ('title', 'mission'):
        val = s.get(key)
        if val:
            return str(val)
    if tid in label_memo:
        return label_memo[tid]
    prepass = prepass_label(tid)
    if prepass:
        label_memo[tid] = prepass
        return prepass
    label = tid
    if label_resolve_budget[0] > 0:
        label_resolve_budget[0] -= 1
        try:
            import subprocess
            proc = subprocess.run(
                ['bash', '-c', 'source "\$1" 2>/dev/null && leadv2_tasks_by_id "\$2"',
                 '_', tasks_lib_path, tid],
                capture_output=True, text=True, timeout=1,
            )
            if proc.returncode == 0 and proc.stdout.strip():
                item = (yaml.safe_load(proc.stdout) or [{}])[0]
                intent = str(item.get('intent', '') or '')
                tag = intent.split(':', 1)[0].strip()
                if tag:
                    label = tag
        except Exception:
            pass
    label_memo[tid] = label
    return label

def strip_common_affix(ids):
    # D5 step 5: labels that reached here are still bare lane ids -- every
    # dispatch-code lane shares the 'dispatch-' prefix, which is exactly why
    # every digest token rendered as the same 'dispa...' before this fix.
    # Strip the longest common prefix AND suffix across this batch of ids
    # together (not per-id), so distinguishing characters survive instead of
    # being truncated away one at a time by cap_label's head-preserving cut.
    if len(ids) < 2:
        return {tid: tid for tid in ids}

    def common_prefix(strs):
        if not strs:
            return ''
        p = strs[0]
        for s in strs[1:]:
            while p and not s.startswith(p):
                p = p[:-1]
        return p

    def common_suffix(strs):
        return common_prefix([s[::-1] for s in strs])[::-1]

    def apply(prefix, suffix):
        out = {}
        for tid in ids:
            s = tid
            if prefix and s.startswith(prefix):
                s = s[len(prefix):]
            if suffix and s.endswith(suffix) and len(s) > len(suffix):
                s = s[:len(s) - len(suffix)]
            out[tid] = s or tid
        return out

    prefix = common_prefix(ids)
    suffix = common_suffix(ids)
    stripped = apply(prefix, suffix)
    if len(set(stripped.values())) == len(ids):
        return stripped
    # Collision guard: back the prefix off one '-'-segment and retry once.
    segments = prefix.split('-')
    if len(segments) > 1:
        shorter_prefix = '-'.join(segments[:-1])
        if shorter_prefix and shorter_prefix != prefix:
            retry = apply(shorter_prefix, suffix)
            if len(set(retry.values())) == len(ids):
                return retry
    # Floor: stripping cannot distinguish these ids -- render the raw id.
    return {tid: tid for tid in ids}

# D4 (dispatch-98cc5cf7): ALL live lanes, never just the first 2 -- rows[:2]
# was the direct cause of a founder-visible lane going missing from the
# digest. kind/model are now a strictly-optional tail appended only if width
# remains after every lane already has its full label (never a fixed cost).
lane_meta = []
for age_s, lane_id, verdict in rows:
    if age_s is None:
        age = '?'
    elif age_s < 60:
        age = f'{age_s}s'
    elif age_s < 3600:
        age = f'{age_s // 60}m'
    else:
        age = f'{age_s // 3600}h'
    s = sessions_by_tid.get(lane_id, {})
    if s:
        kind = 'sw' if str(s.get('backend') or s.get('where') or '') == 'dispatch-code' else 'full'
    else:
        # A lane surfaced only via the widened id union (D2 Gap B) has no
        # active.yaml session row to read backend/where from -- a bare
        # dispatch-<hash> id IS by construction a dispatch-code funnel lane.
        kind = 'sw' if lane_id.startswith('dispatch-') else 'full'
    model = str(s.get('lead_model') or s.get('provider') or '?')
    label = raw_label(lane_id, s)
    # FIX5e: a '·verdict-prefix' suffix only when the authoritative verdict
    # is NOT 'alive' -- the prefix (everything before the first ':') is whatever
    # leadv2-lane-liveness.sh itself returns ('dead', 'silent', 'starting', ...),
    # never a hand-kept enum here, so a future verdict category renders
    # correctly with no code change. A lookup failure (no verdict resolved at
    # all) renders no suffix -- absence of evidence is not evidence of death.
    vsuffix = ''
    if verdict and not str(verdict).startswith('alive'):
        vprefix = str(verdict).split(':', 1)[0].strip()
        if vprefix:
            vsuffix = '·' + vprefix
    # NB: tuples, not a dict-with-string-keys -- this whole heredoc-style
    # block is embedded inside the OUTER bash script's double-quoted
    # 'python3 -c \"...\"' string, so a python double-quoted f-string (or
    # any bracket lookup needing its OWN quotes inside an f-string) would
    # prematurely close the outer bash quoting. Every line in this block
    # stays single-quote-only for that reason.
    lane_meta.append((label, kind, model, age, vsuffix, lane_id))

# D5 step 5: apply the batch-wide common-affix strip to every lane whose
# label never resolved past the raw id (title/memo/prepass/tasks-lib all
# came up empty) -- computed together so 'dispatch-3d46872c' and
# 'dispatch-8a9177d7-architect' become distinguishable stems instead of both
# still starting with the same 'dispatch-' that caused every label to render
# identically before this fix.
_unresolved_ids = [lid for lbl, _k, _mo, _ag, _vs, lid in lane_meta if lbl == lid]
if _unresolved_ids:
    _stems = strip_common_affix(_unresolved_ids)
    lane_meta = [
        ((_stems.get(lid, lbl) if lbl == lid else lbl), k, mo, ag, vs, lid)
        for lbl, k, mo, ag, vs, lid in lane_meta
    ]

# D4 degradation ladder: shorten, NEVER drop a lane. D6: budget is now
# derived from the ACTUAL remaining terminal width after BASE, not a flat
# guess -- an explicit LEADV2_STATUSLINE_LANE_BUDGET override still wins.
try:
    _width = max(1, int(width_raw))
except ValueError:
    _width = 80
try:
    _base_visible_len = max(0, int(base_visible_len_raw))
except ValueError:
    _base_visible_len = 0
_explicit_budget = os.environ.get('LEADV2_STATUSLINE_LANE_BUDGET', '')
if _explicit_budget:
    try:
        DIGEST_BUDGET = int(_explicit_budget)
    except ValueError:
        DIGEST_BUDGET = max(20, _width - _base_visible_len - len(' | '))
else:
    DIGEST_BUDGET = max(20, _width - _base_visible_len - len(' | '))
base_prefix = f'lanes {n}/{cap}'

def digest_len(tokens):
    if not tokens:
        return len(base_prefix)
    return len(base_prefix) + len(' | ') + sum(len(t) for t in tokens) + (len(tokens) - 1)

def render_step12(label_cap, with_meta):
    toks = []
    for lbl, k, mo, ag, vs, _lid in lane_meta:
        tok = f'{cap_label(lbl, label_cap)}·{ag}{vs}'
        if with_meta:
            tok += f'·{k}·{mo}'
        toks.append(tok)
    return toks

def render_step3(label_cap):
    return [f'{cap_label(lbl, label_cap)}:{ag}{vs}' for lbl, _k, _mo, ag, vs, _lid in lane_meta]

def render_step5_floor():
    # D6 floor: 2-char (already de-prefixed, per D5 step 5) stems + age.
    # Verdict suffix dropped here only, age always kept -- unlike the old
    # id-only floor this replaces, this is never a bare hash with zero
    # information about how stale the lane is. cap_label's own budget is 3,
    # not 2: with an ellipsis costing one of the two, a literal cap of 2
    # shows only ONE real character (the other char slot spent on '…'),
    # which is exactly what made distinct stems collide under heavy load --
    # 3 keeps both stem characters visible.
    return [f'{cap_label(lbl, 3)}·{ag}' for lbl, _k, _mo, ag, _vs, _lid in lane_meta]

id_parts = None
if lane_meta:
    # Step 1: full labels (cap 24), meta appended only while it still fits.
    for with_meta in (True, False):
        cand = render_step12(LABEL_CAP, with_meta)
        if digest_len(cand) <= DIGEST_BUDGET:
            id_parts = cand
            break
    # Step 2: shrink the per-label cap, no meta.
    if id_parts is None:
        for label_cap in (16, 12, 9, 6):
            cand = render_step12(label_cap, False)
            if digest_len(cand) <= DIGEST_BUDGET:
                id_parts = cand
                break
    # Step 3: compact 'lbl:age' form, cap 4 -- verdict suffix retained.
    if id_parts is None:
        cand = render_step3(4)
        if digest_len(cand) <= DIGEST_BUDGET:
            id_parts = cand
    # Step 5 floor: 2-char de-prefixed stem + age, verdict suffix dropped.
    # There is no step that removes a lane -- if this still overflows, width
    # is released by shortening BASE's own cwd instead (see the bash tail
    # below this heredoc).
    if id_parts is None:
        id_parts = render_step5_floor()

out = base_prefix
if id_parts:
    out += ' | ' + ' '.join(id_parts)
print(out)
# C8 (STATUSLINE-SHOWS-LANES-QUESTIONMARK-01): tmp + os.replace for every
# shared cache file this script writes -- concurrent detached refreshers
# (one per repaint, throttled to ~2s) can interleave a plain open(...,'w')
# with the NEXT run's read of the same file. A rename is atomic; a
# truncate-then-write is not. (The liveness memo above already uses this
# same pattern at its own write site.)
def atomic_write_text(path, text):
    tmp_path = f'{path}.tmp.{os.getpid()}'
    with open(tmp_path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    safe_replace(tmp_path, path)

try:
    atomic_write_text(cache_file, out)
except Exception:
    pass
try:
    atomic_write_text(label_memo_file, ''.join(f'{k}\t{v}\n' for k, v in label_memo.items()))
except Exception:
    pass
" "$ACTIVE_YAML" "$CWD_FROM_INPUT" "$LANE_CACHE_FILE" "$LIMITS_YAML" "$LABEL_MEMO_FILE" "$TASKS_LIB" "$LIVENESS_BIN" "$LIVENESS_MEMO_FILE" "$LIVENESS_MEMO_TTL_S" "$COUNT_SIDECAR_FILE" "$STATUSLINE_WIDTH" "$BASE_VISIBLE_LEN" "$CACHE_DIR" 2>/dev/null || true)"
      # C7: a real prior number beats a fresh "lanes ?" -- an empty result
      # (timeout/crash) or an explicit "lanes ?" from the calc itself no
      # longer overwrites a good cached digest; it only falls back to "lanes
      # ?" when there is truly no prior value to fall back to. D4 extends the
      # match to "lanes ?/<cap>" too -- n now renders as the literal string
      # '?' inside base_prefix (e.g. "lanes ?/5"), not just the bare "lanes
      # ?", so the guard must recognize both shapes as "the reader failed",
      # never overwrite a good cache with either.
      if [[ -z "$LANES" || "$LANES" == "lanes ?" || "$LANES" == "lanes ?"/* ]]; then
        STALE_LANES=""
        [[ -f "$LANE_CACHE_FILE" ]] && STALE_LANES="$(cat "$LANE_CACHE_FILE" 2>/dev/null || true)"
        if [[ -n "$STALE_LANES" && "$STALE_LANES" != "lanes ?" ]]; then
          LANES="$STALE_LANES"
        else
          LANES="lanes ?"
        fi
      fi
    fi
  fi
  [[ -f "$LANE_CACHE_FILE" ]] || _leadv2_statusline_safe_write "$LANE_CACHE_FILE" "$LANES" || true
fi

# D6 (STATUSLINE fix round 2): the trailing pulse "last: ..." fragment is
# gone -- the founder asked for it to be dropped twice, and its width budget
# now belongs to the lane digest (see STATUSLINE_WIDTH/BASE_VISIBLE_LEN
# above). LEADV2_LANE_PULSE_STALE_MAX_S is dead along with it.
FINAL_LINE="$(printf '%s \033[34m| %s\033[0m' "$BASE" "$LANES")"

# D6 last-resort width release valve: the degradation ladder above never
# drops a lane, so if the line STILL overflows after every lane is already
# at its 2-char floor, shrink BASE's own cwd segments to their first letter
# instead (~/Projects/persona-engine -> ~/P/persona-engine). Only fires when
# genuinely needed -- the common case never touches BASE.
FINAL_VISIBLE_LEN="$(printf '%s' "$FINAL_LINE" | sed -E $'s/\x1b\\[[0-9;]*m//g' | awk '{print length}')"
[[ -z "$FINAL_VISIBLE_LEN" ]] && FINAL_VISIBLE_LEN=0
if (( FINAL_VISIBLE_LEN > STATUSLINE_WIDTH )) && [[ "$BASE" == *'~/'* ]]; then
  SHRUNK_BASE="$(printf '%s' "$BASE" | sed -E 's#~/([A-Za-z0-9_.-])[A-Za-z0-9_.-]*/#~/\1/#g')"
  if [[ "$SHRUNK_BASE" != "$BASE" ]]; then
    FINAL_LINE="$(printf '%s \033[34m| %s\033[0m' "$SHRUNK_BASE" "$LANES")"
  fi
fi

printf '%s\n' "$FINAL_LINE"

if [[ -n "$OUT_FILE" ]]; then
  OUT_TMP="${OUT_FILE}.tmp.$$"
  if printf '%s' "$FINAL_LINE" > "$OUT_TMP" 2>/dev/null; then
    mv -f "$OUT_TMP" "$OUT_FILE" 2>/dev/null || rm -f "$OUT_TMP" 2>/dev/null
  fi
fi
