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

LANES="lanes ?"
CACHE_KEY="${CWD_FROM_INPUT//\//_}"
[[ -z "$CACHE_KEY" ]] && CACHE_KEY="default"
LANE_CACHE_FILE="${TMPDIR:-/tmp}/leadv2-statusline-lane-${CACHE_KEY}"

# Hoisted (was inside the CACHE_FRESH=0 branch only): also needed below,
# unconditionally, to resolve the pulse log for the "last:" digest.
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
LIVENESS_MEMO_FILE="${LANE_CACHE_FILE}.liveness"
LIVENESS_MEMO_TTL_S="${LEADV2_LANE_LIVENESS_MEMO_TTL_S:-10}"

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
      LANES="$(PROJECT_ROOT="$CWD_FROM_INPUT" timeout 4 python3 -c "
import sys, os, time, glob, subprocess
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

now = time.time()
rows = []
sessions_by_tid = {}
for s in sessions:
    tid = str(s.get('task_id', '?'))
    phase = str(s.get('phase', '?'))
    log = lane_log(s)
    age_s = None
    if log:
        try:
            age_s = int(now - os.path.getmtime(log))
        except Exception:
            age_s = None
    rows.append((age_s, tid, phase))
    sessions_by_tid[tid] = s

# Pulse digest (founder ask, fix5 attempt 2): only the top-2 MOST
# recently-active lanes, not the first 8 in file order — smallest age_s
# first; unknown-age lanes (no discoverable log) sort last, never first.
rows.sort(key=lambda r: (r[0] is None, r[0] if r[0] is not None else 0))

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

# FIX5e: liveness verdict memo, same tab-separated-file shape as label_memo
# above, keyed by task_id -> (verdict, resolved_at_epoch). A fresh memo entry
# (age < liveness_ttl) is reused as-is; only an expired or missing entry pays
# for a real leadv2-lane-liveness.sh subprocess.
liveness_bin, liveness_memo_file, liveness_ttl_raw = sys.argv[7], sys.argv[8], sys.argv[9]
try:
    liveness_ttl = float(liveness_ttl_raw)
except ValueError:
    liveness_ttl = 10.0
liveness_memo = {}
if os.path.isfile(liveness_memo_file):
    try:
        with open(liveness_memo_file, encoding='utf-8') as fh:
            for line in fh:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 3:
                    k, v, ts = parts
                    try:
                        liveness_memo[k] = (v, float(ts))
                    except ValueError:
                        pass
    except Exception:
        liveness_memo = {}

def lane_verdict(tid):
    now_ts = time.time()
    cached = liveness_memo.get(tid)
    if cached and (now_ts - cached[1]) < liveness_ttl:
        return cached[0]
    verdict = None
    try:
        proc = subprocess.run(
            ['bash', liveness_bin, '--project-root', root, '--lane', tid],
            capture_output=True, text=True, timeout=2,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            verdict = proc.stdout.strip().splitlines()[0].strip()
    except Exception:
        verdict = None
    if verdict:
        liveness_memo[tid] = (verdict, now_ts)
    return verdict

def cap_label(text, label_cap):
    text = text.strip()
    label_cap = max(label_cap, 1)
    if len(text) <= label_cap:
        return text
    return text[:label_cap - 1] + '…' if label_cap > 1 else '…'

def raw_label(tid, s):
    # Returns the UNCAPPED label text; capping is applied later, per-row,
    # once the digest-wide length budget is known (fix5d-addendum).
    for key in ('title', 'mission'):
        val = s.get(key)
        if val:
            return str(val)
    if tid in label_memo:
        return label_memo[tid]
    label = tid
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

# FIX5d-addendum (founder ask): digest also carries dispatch kind (sw =
# leadv2-dispatch-code.sh's single-worker funnel, identified by backend/
# where == "dispatch-code"; everything else -- headless/terminal/tmux -- is
# a full-cycle fanout.sh child, so "full") and the model that ran the lane.
lane_meta = []
for age_s, tid, phase in rows[:2]:
    if age_s is None:
        age = '?'
    elif age_s < 60:
        age = f'{age_s}s'
    elif age_s < 3600:
        age = f'{age_s // 60}m'
    else:
        age = f'{age_s // 3600}h'
    s = sessions_by_tid.get(tid, {})
    kind = 'sw' if str(s.get('backend') or s.get('where') or '') == 'dispatch-code' else 'full'
    model = str(s.get('lead_model') or s.get('provider') or '?')
    label = raw_label(tid, s)
    # FIX5e: a '·verdict-prefix' suffix only when the authoritative verdict
    # is NOT 'alive' -- the prefix (everything before the first ':') is whatever
    # leadv2-lane-liveness.sh itself returns ('dead', 'silent', ...), never a
    # hand-kept enum here, so a future verdict category renders correctly
    # with no code change. A lookup failure (no verdict resolved at all)
    # renders no suffix -- absence of evidence is not evidence of death.
    verdict = lane_verdict(tid)
    vsuffix = ''
    if verdict and not verdict.startswith('alive'):
        vprefix = verdict.split(':', 1)[0].strip()
        if vprefix:
            vsuffix = '·' + vprefix
    # NB: tuples, not a dict-with-string-keys -- this whole heredoc-style
    # block is embedded inside the OUTER bash script's double-quoted
    # 'python3 -c \"...\"' string, so a python double-quoted f-string (or
    # any bracket lookup needing its OWN quotes inside an f-string) would
    # prematurely close the outer bash quoting. Every line in this block
    # stays single-quote-only for that reason.
    lane_meta.append((label, kind, model, phase, age, vsuffix))

# Whole line stays under ~90 chars, per-lane label absorbs the squeeze
# first (founder ask) -- everything else (kind/model/phase/age/verdict) is
# short and load-bearing, so it is never shrunk.
DIGEST_BUDGET = 90
base_prefix = f'lanes {n}/{cap}'
id_parts = []
if lane_meta:
    fixed_len = len(base_prefix) + len(' | ') + (len(lane_meta) - 1) * len(' ')
    overheads = [1 + len(k) + 1 + len(mo) + 1 + len(ph) + 1 + len(ag) + len(vs)
                 for _, k, mo, ph, ag, vs in lane_meta]
    fixed_len += sum(overheads)
    available = DIGEST_BUDGET - fixed_len
    per_label_cap = max(6, min(LABEL_CAP, available // len(lane_meta) if available > 0 else 6))
    for lbl, k, mo, ph, ag, vs in lane_meta:
        lbl = cap_label(lbl, per_label_cap)
        id_parts.append(f'{lbl}·{k}·{mo}·{ph}:{ag}{vs}')

out = base_prefix
if id_parts:
    out += ' | ' + ' '.join(id_parts)
print(out)
try:
    with open(cache_file, 'w', encoding='utf-8') as fh:
        fh.write(out)
except Exception:
    pass
try:
    with open(label_memo_file, 'w', encoding='utf-8') as fh:
        for k, v in label_memo.items():
            fh.write(f'{k}\t{v}\n')
except Exception:
    pass
try:
    with open(liveness_memo_file, 'w', encoding='utf-8') as fh:
        for k, (v, ts) in liveness_memo.items():
            fh.write(f'{k}\t{v}\t{ts}\n')
except Exception:
    pass
" "$ACTIVE_YAML" "$CWD_FROM_INPUT" "$LANE_CACHE_FILE" "$LIMITS_YAML" "$LABEL_MEMO_FILE" "$TASKS_LIB" "$LIVENESS_BIN" "$LIVENESS_MEMO_FILE" "$LIVENESS_MEMO_TTL_S" 2>/dev/null || true)"
      [[ -z "$LANES" ]] && LANES="lanes ?"
    fi
  fi
  [[ -f "$LANE_CACHE_FILE" ]] || printf '%s' "$LANES" > "$LANE_CACHE_FILE" 2>/dev/null || true
fi

# ---- pulse digest "last:" fragment ----
# Read ONLY here (the detached background tail script), never in the hot
# path (leadv2-lane-status-line.sh just `cat`s the cache). Resolved via the
# supervise loop's own path config (leadv2-supervise-loop.sh: LOG_FILE via
# leadv2-state-path.sh supervise-loop.log) — never a hardcoded docs/leadv2
# path, same reasoning as the active.yaml lookup above. Independent of the
# lane cache TTL: cheap (one file tail), so it is recomputed every tail-
# script run rather than folded into the lane cache's freshness window.
# FIX5c: same stale fix-round-3 budgets as above (0.08s vs. this resolver's
# own measured ~100-110ms) — bumped for the same reason.
# FIX5e: a non-running supervise loop leaves the last pulse line as a
# fossil forever -- the founder's live repro showed a 2-day-old UTC line
# rendering as if it were live. Age is measured off the LINE'S OWN leading
# ISO8601 timestamp (never the log file's mtime, which an unrelated write
# could refresh); once that age is >= PULSE_STALE_MAX_S the fragment is
# omitted entirely rather than shown stale. When rendered, the leading UTC
# stamp is converted to local HH:MM (never raw UTC ISO) — BSD `date -j` first
# (mac), GNU `date -d`/`date -r @` fallback (VPS), matching the rest of this
# repo's date-portability convention.
PULSE_STALE_MAX_S="${LEADV2_LANE_PULSE_STALE_MAX_S:-7200}"
PULSE_FRAG=""
if [[ -x "$RESOLVER" ]]; then
  PULSE_LOG="$(PROJECT_ROOT="$CWD_FROM_INPUT" timeout 1 "$RESOLVER" --no-link supervise-loop.log 2>/dev/null || true)"
  if [[ -n "$PULSE_LOG" && -f "$PULSE_LOG" ]]; then
    PULSE_TEXT="$(timeout 0.5 grep -v '^[[:space:]]*$' "$PULSE_LOG" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$PULSE_TEXT" ]]; then
      PULSE_TS="$(printf '%s' "$PULSE_TEXT" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?' || true)"
      PULSE_EPOCH="" PULSE_LOCAL_HHMM=""
      if [[ -n "$PULSE_TS" ]]; then
        # -u is load-bearing on BSD: the source stamp is UTC (the trailing
        # Z), and `date -j -f` with no -u would silently parse those digits
        # as LOCAL wall-clock instead, skewing the epoch by the machine's
        # UTC offset (measured: a 5-minute-old EEST stamp mis-parsed this
        # way computed as >3h old and got wrongly treated as stale).
        PULSE_EPOCH="$(timeout 0.2 date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$PULSE_TS" +%s 2>/dev/null || timeout 0.2 date -d "$PULSE_TS" +%s 2>/dev/null || true)"
        if [[ -n "$PULSE_EPOCH" ]]; then
          PULSE_LOCAL_HHMM="$(timeout 0.2 date -r "$PULSE_EPOCH" +%H:%M 2>/dev/null || timeout 0.2 date -d "@${PULSE_EPOCH}" +%H:%M 2>/dev/null || true)"
        fi
      fi
      PULSE_AGE=""
      if [[ -n "$PULSE_EPOCH" ]]; then
        NOW_PULSE_S="${EPOCHSECONDS:-$(date +%s)}"
        PULSE_AGE=$(( NOW_PULSE_S - PULSE_EPOCH ))
      fi
      if [[ -z "$PULSE_AGE" || "$PULSE_AGE" -lt "$PULSE_STALE_MAX_S" ]]; then
        if [[ -n "$PULSE_TS" && -n "$PULSE_LOCAL_HHMM" ]]; then
          PULSE_TEXT="${PULSE_LOCAL_HHMM}${PULSE_TEXT#"$PULSE_TS"}"
        fi
        PULSE_TEXT="${PULSE_TEXT:0:40}"
        PULSE_FRAG=" | \033[2mlast: ${PULSE_TEXT}\033[0m"
      fi
    fi
  fi
fi

FINAL_LINE="$(printf '%s \033[34m| %s\033[0m%b' "$BASE" "$LANES" "$PULSE_FRAG")"
printf '%s\n' "$FINAL_LINE"

if [[ -n "$OUT_FILE" ]]; then
  OUT_TMP="${OUT_FILE}.tmp.$$"
  if printf '%s' "$FINAL_LINE" > "$OUT_TMP" 2>/dev/null; then
    mv -f "$OUT_TMP" "$OUT_FILE" 2>/dev/null || rm -f "$OUT_TMP" 2>/dev/null
  fi
fi
