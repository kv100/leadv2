#!/usr/bin/env bash
# leadv2-skill-rollup.sh — period rollup over docs/leadv2/skill-invocations.jsonl
# (written by leadv2-skill-telemetry-collect.sh). Classifies every skill on
# disk, across ALL skill roots, into one of three honest buckets:
#   INVOKED                  — >=1 telemetry row inside the window.
#   NEVER_INVOKED             — 0 rows in the window AND 0 rows ever.
#   INVOKED_NO_LANE_SUCCESS  — >=1 row in the window, and every row whose
#                              lane terminal resolved, resolved to non-success.
# A residual 4th label, INVOKED_PAST_ONLY, covers a skill with history but
# nothing in the current window -- it is not one of the three headline
# buckets and no acceptance check depends on it; it exists only so
# bucket_for_skill() never has to lie about a skill with zero window rows
# but nonzero history by calling it NEVER_INVOKED.
#
# Universe = union of every skill root, not just the plugin's own
# plugins/leadv2/skills/ (that undercount — 40 of 89 — is the defect this
# lane exists to fix). A directory with no SKILL.md is still counted, tagged
# 'no-skill-md'.
#
# lane_success is a correlation (skill invoked, lane's own dispatch_terminal
# outcome), never a causal helpfulness score — see the header this script
# prints. Only resolved rows (lane terminal = landed|dead) count; unresolved
# lanes never contribute, and a skill with zero resolved rows reports
# lane_success=n/a, never 0%. Never rank or score by this column.
#
# Usage:
#   leadv2-skill-rollup.sh [--since <Nd>] [--repo <name>]
#                           [--skills-root <dir>]... [--format md|tsv]
#                           [--jsonl <path>] [--repo-root <dir>] [--out <path>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SINCE_DAYS="7"
REPO_FILTER=""
FORMAT="md"
REPO_ROOT="$DEFAULT_REPO_ROOT"
JSONL_OVERRIDE=""
OUT_OVERRIDE=""
SKILLS_ROOTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE_DAYS="${2%d}"; shift 2 ;;
    --since=*)
      SINCE_DAYS="${1#--since=}"; SINCE_DAYS="${SINCE_DAYS%d}"; shift ;;
    --repo)
      REPO_FILTER="$2"; shift 2 ;;
    --repo=*)
      REPO_FILTER="${1#--repo=}"; shift ;;
    --skills-root)
      SKILLS_ROOTS+=("$2"); shift 2 ;;
    --skills-root=*)
      SKILLS_ROOTS+=("${1#--skills-root=}"); shift ;;
    --format)
      FORMAT="$2"; shift 2 ;;
    --format=*)
      FORMAT="${1#--format=}"; shift ;;
    --jsonl)
      JSONL_OVERRIDE="$2"; shift 2 ;;
    --jsonl=*)
      JSONL_OVERRIDE="${1#--jsonl=}"; shift ;;
    --repo-root)
      REPO_ROOT="$2"; shift 2 ;;
    --repo-root=*)
      REPO_ROOT="${1#--repo-root=}"; shift ;;
    --out)
      OUT_OVERRIDE="$2"; shift 2 ;;
    --out=*)
      OUT_OVERRIDE="${1#--out=}"; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      echo "leadv2-skill-rollup: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

case "$SINCE_DAYS" in
  ''|*[!0-9]*)
    echo "leadv2-skill-rollup: --since must be like '7d' (got '${SINCE_DAYS}')" >&2
    exit 2 ;;
esac
case "$FORMAT" in
  md|tsv) ;;
  *) echo "leadv2-skill-rollup: --format must be md|tsv (got '${FORMAT}')" >&2; exit 2 ;;
esac

JSONL="${JSONL_OVERRIDE:-$REPO_ROOT/docs/leadv2/skill-invocations.jsonl}"
OUT_MD="${OUT_OVERRIDE:-$REPO_ROOT/docs/leadv2/skill-usage-rollup.md}"

if [[ ${#SKILLS_ROOTS[@]} -eq 0 ]]; then
  SKILLS_ROOTS+=("$REPO_ROOT/plugins/leadv2/skills")
  SKILLS_ROOTS+=("$HOME/Projects/persona-engine/.claude/skills")
fi
SKILLS_ROOTS_CSV="$(printf '%s\n' "${SKILLS_ROOTS[@]}" | paste -sd '|' -)"

mkdir -p "$(dirname "$OUT_MD")"

LEADV2_REPO_ROOT="$REPO_ROOT" \
LEADV2_SINCE_DAYS="$SINCE_DAYS" \
LEADV2_REPO_FILTER="$REPO_FILTER" \
LEADV2_JSONL="$JSONL" \
LEADV2_OUT_MD="$OUT_MD" \
LEADV2_SKILLS_ROOTS="$SKILLS_ROOTS_CSV" \
LEADV2_FORMAT="$FORMAT" \
python3 <<'PYEOF'
import glob
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

REPO_ROOT = os.environ['LEADV2_REPO_ROOT']
SINCE_DAYS = int(os.environ.get('LEADV2_SINCE_DAYS', '7') or '7')
REPO_FILTER = os.environ.get('LEADV2_REPO_FILTER') or None
JSONL = os.environ['LEADV2_JSONL']
OUT_MD = os.environ['LEADV2_OUT_MD']
SKILLS_ROOTS = [r for r in os.environ['LEADV2_SKILLS_ROOTS'].split('|') if r]
FORMAT = os.environ['LEADV2_FORMAT']

HEADER_LINE = 'lane_success is CORRELATION, NOT PROOF of helpfulness.'


def parse_ts(s):
    if not s:
        return None
    for fmt in ('%Y-%m-%dT%H:%M:%S.%fZ', '%Y-%m-%dT%H:%M:%SZ'):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


_journal_index = None


def journal_index():
    global _journal_index
    if _journal_index is not None:
        return _journal_index
    idx = {}
    root = os.path.join(REPO_ROOT, 'docs', 'leadv2', 'tasks')
    for jpath in glob.glob(os.path.join(root, '*', 'journal.md')):
        task_dir = os.path.basename(os.path.dirname(jpath))
        task_id = task_dir[len('dispatch-'):] if task_dir.startswith('dispatch-') else task_dir
        idx.setdefault(task_id, (jpath, task_id))
        idx.setdefault(task_dir, (jpath, task_id))
        try:
            with open(jpath, errors='ignore') as f:
                for line in f:
                    m = re.search(r'founder_task=(\S+)', line)
                    if m:
                        idx.setdefault(m.group(1), (jpath, task_id))
        except OSError:
            continue
    _journal_index = idx
    return idx


_lane_outcome_cache = {}


def resolve_lane_outcome(lane):
    """landed|failed|unresolved -- real dispatch_terminal vocabulary only,
    never a guess. 'parked' or any unrecognised terminal value stays
    unresolved."""
    if not lane or lane == 'main':
        return 'unresolved'
    if lane in _lane_outcome_cache:
        return _lane_outcome_cache[lane]
    entry = journal_index().get(lane)
    result = 'unresolved'
    if entry:
        jpath, task_id = entry
        try:
            with open(jpath, errors='ignore') as f:
                content = f.read()
        except OSError:
            content = ''
        matches = re.findall(
            r'dispatch_terminal task=' + re.escape(task_id) + r' terminal=(\S+)', content)
        if matches:
            terminal = matches[-1]
            if terminal == 'landed':
                result = 'landed'
            elif terminal == 'dead':
                result = 'failed'
    _lane_outcome_cache[lane] = result
    return result


def bucket_for_skill(name, window_rows, alltime_rows):
    count = len(window_rows)
    if count == 0:
        if len(alltime_rows) == 0:
            return 'NEVER_INVOKED'
        return 'INVOKED_PAST_ONLY'
    resolved = [r for r in window_rows if r.get('lane_outcome') in ('landed', 'failed')]
    if resolved and all(r.get('lane_outcome') == 'failed' for r in resolved):
        return 'INVOKED_NO_LANE_SUCCESS'
    return 'INVOKED'


all_rows = []
if os.path.isfile(JSONL):
    with open(JSONL, errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if REPO_FILTER and rec.get('repo') != REPO_FILTER:
                continue
            all_rows.append(rec)

cutoff = datetime.now(timezone.utc) - timedelta(days=SINCE_DAYS)

window_by_skill = {}
alltime_by_skill = {}
for r in all_rows:
    skill = r.get('skill')
    if not skill:
        continue
    alltime_by_skill.setdefault(skill, []).append(r)
    ts_dt = parse_ts(r.get('ts'))
    if ts_dt is not None and ts_dt >= cutoff:
        r['lane_outcome'] = resolve_lane_outcome(r.get('lane'))
        window_by_skill.setdefault(skill, []).append(r)

universe = []  # (name, root, has_skill_md)
for root in SKILLS_ROOTS:
    if not os.path.isdir(root):
        continue
    for entry in sorted(os.listdir(root)):
        full = os.path.join(root, entry)
        if not os.path.isdir(full):
            continue
        has_md = os.path.isfile(os.path.join(full, 'SKILL.md'))
        universe.append((entry, root, has_md))

rows_out = []
never_ct = 0
no_success_ct = 0
invoked_ct = 0
no_skill_md_ct = 0
for name, root, has_md in universe:
    wrows = window_by_skill.get(name, [])
    arows = alltime_by_skill.get(name, [])
    if not has_md:
        bucket = 'no-skill-md'
        no_skill_md_ct += 1
    else:
        bucket = bucket_for_skill(name, wrows, arows)
        if bucket == 'NEVER_INVOKED':
            never_ct += 1
        elif bucket == 'INVOKED_NO_LANE_SUCCESS':
            no_success_ct += 1
        elif bucket == 'INVOKED':
            invoked_ct += 1

    display_rows = wrows if wrows else arows
    sessions = len({r.get('session_id') for r in display_rows if r.get('session_id')})
    lanes = len({r.get('lane') for r in display_rows if r.get('lane')})
    invocations = len(wrows) if wrows else len(arows)
    last_seen = max((r.get('ts') or '' for r in display_rows), default='') or 'never'

    resolved = [r for r in wrows if r.get('lane_outcome') in ('landed', 'failed')]
    if resolved:
        landed = sum(1 for r in resolved if r['lane_outcome'] == 'landed')
        lane_success = '{}%'.format(round(100.0 * landed / len(resolved)))
    else:
        lane_success = 'n/a'

    rows_out.append({
        'skill': name, 'root': root, 'invocations': invocations,
        'sessions': sessions, 'lanes': lanes, 'last_seen': last_seen,
        'bucket': bucket, 'lane_success': lane_success,
    })

universe_n = len(universe)

# -- MD report: always written --
md_lines = []
md_lines.append('# Skill usage rollup')
md_lines.append('')
md_lines.append('window=last {}d  universe={}  invoked={} never_invoked={} '
                 'invoked_no_lane_success={} no_skill_md={}'.format(
                     SINCE_DAYS, universe_n, invoked_ct, never_ct, no_success_ct, no_skill_md_ct))
md_lines.append('')
md_lines.append(HEADER_LINE)
md_lines.append('')
md_lines.append('| skill | root | invocations | sessions | lanes | last_seen | bucket | lane_success |')
md_lines.append('|---|---|---|---|---|---|---|---|')
for r in rows_out:
    md_lines.append('| {skill} | {root} | {invocations} | {sessions} | {lanes} | {last_seen} | {bucket} | {lane_success} |'.format(**r))
md_lines.append('')

with open(OUT_MD, 'w') as f:
    f.write('\n'.join(md_lines) + '\n')

if FORMAT == 'tsv':
    cols = ['skill', 'root', 'invocations', 'sessions', 'lanes', 'last_seen', 'bucket', 'lane_success']
    sys.stdout.write('\t'.join(cols) + '\n')
    for r in rows_out:
        sys.stdout.write('\t'.join(str(r[c]) for c in cols) + '\n')
PYEOF
py_rc=$?

if [[ $py_rc -ne 0 ]]; then
  echo "leadv2-skill-rollup: rollup failed (rc=${py_rc})" >&2
  exit 1
fi

exit 0
