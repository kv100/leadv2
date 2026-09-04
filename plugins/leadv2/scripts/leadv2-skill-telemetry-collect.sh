#!/usr/bin/env bash
# leadv2-skill-telemetry-collect.sh — batch scanner over Claude Code session
# transcript JSONL that records skill INVOCATIONS (not text mentions) into
# docs/leadv2/skill-invocations.jsonl. This is the "which skill fired, when,
# in which session/lane, how did it end" record that
# leadv2-skill-usage-tally.sh cannot produce (that script counts static-text
# refs, never runtime firings — see its header comment).
#
# Two invocation shapes, both real, both scanned:
#   S1a explicit tool call  — assistant message.content[] has
#                             {"type":"tool_use","name":"Skill","input":{"skill":"X"}}
#                             (small in volume; outcome resolvable via the
#                             matching tool_result's toolUseResult.success)
#   S1b description-match injection — the DOMINANT path. A user message with
#                             isMeta:true whose text carries
#                             <command-name>X</command-name> AND
#                             <skill-format>true</skill-format>. Slash
#                             commands carry <command-name> WITHOUT the
#                             skill-format tag — gating on that tag is what
#                             keeps /leadv2, /model, /compact etc. out of the
#                             skill count. S1b calls have no result record,
#                             so their outcome is always "n_a" — never guess ok.
#
# Usage:
#   leadv2-skill-telemetry-collect.sh [--since <Nd>] [--transcripts-root <dir>]
#                                      [--repo-root <dir>] [--out <jsonl>]
#   --since <Nd>             only scan transcript lines timestamped within
#                             the last N days (default 30d).
#   --transcripts-root <dir> override ~/.claude/projects (tests point this at
#                             a fixture tree; never fakes the collector itself).
#   --repo-root <dir>        override the repo root used to resolve
#                             docs/leadv2/tasks/*/journal.md for best-effort
#                             phase resolution (default: this script's repo).
#   --out <jsonl>            override the output file (default:
#                             <repo-root>/docs/leadv2/skill-invocations.jsonl).
#
# Concurrency-safety (four layers, event_id dedup is the one that matters):
#   1. event_id = sha1(session_id|uuid) is loaded from the existing file
#      first, so a rerun during three live sessions appends zero duplicates.
#   2. One locked critical section for the whole append (leadv2-portable-lock.sh).
#   3. New rows are built into a mktemp file and appended once (one `cat`).
#   4. .gitattributes marks the output `merge=union` so two lane branches that
#      both appended merge without a conflict (dedup makes union safe).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=./leadv2-portable-lock.sh
source "$SCRIPT_DIR/leadv2-portable-lock.sh"

SINCE_DAYS="30"
TRANSCRIPTS_ROOT="${HOME}/.claude/projects"
REPO_ROOT="$DEFAULT_REPO_ROOT"
OUT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE_DAYS="${2%d}"; shift 2 ;;
    --since=*)
      SINCE_DAYS="${1#--since=}"; SINCE_DAYS="${SINCE_DAYS%d}"; shift ;;
    --transcripts-root)
      TRANSCRIPTS_ROOT="$2"; shift 2 ;;
    --transcripts-root=*)
      TRANSCRIPTS_ROOT="${1#--transcripts-root=}"; shift ;;
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
      echo "leadv2-skill-telemetry-collect: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

case "$SINCE_DAYS" in
  ''|*[!0-9]*)
    echo "leadv2-skill-telemetry-collect: --since must be like '30d' (got '${SINCE_DAYS}')" >&2
    exit 2 ;;
esac

OUT_JSONL="${OUT_OVERRIDE:-$REPO_ROOT/docs/leadv2/skill-invocations.jsonl}"
LOCKF="${OUT_JSONL}.lock"
mkdir -p "$(dirname "$OUT_JSONL")"
touch "$OUT_JSONL"

TMP="$(mktemp "${TMPDIR:-/tmp}/skill-collect.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

LEADV2_REPO_ROOT="$REPO_ROOT" \
LEADV2_SINCE_DAYS="$SINCE_DAYS" \
LEADV2_TRANSCRIPTS_ROOT="$TRANSCRIPTS_ROOT" \
LEADV2_EXISTING_JSONL="$OUT_JSONL" \
python3 <<'PYEOF' > "$TMP"
import glob
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

REPO_ROOT = os.environ['LEADV2_REPO_ROOT']
SINCE_DAYS = int(os.environ.get('LEADV2_SINCE_DAYS', '30') or '30')
TRANSCRIPTS_ROOT = os.environ['LEADV2_TRANSCRIPTS_ROOT']
EXISTING_JSONL = os.environ['LEADV2_EXISTING_JSONL']

SKILL_TAG_RE = re.compile(r'<skill-format>true</skill-format>')
NAME_RE = re.compile(r'<command-name>([^<]+)</command-name>')

# Known journal decision-event name prefixes mapped to a canonical /leadv2
# phase label. Best-effort only: a lane journal that never mentions a given
# event, or a lane with no journal at all, resolves to "unknown" rather than
# a guess (WAVE4 requirement).
PHASE_PREFIX_MAP = [
    ('dispatch_classified', 'classify'),
    ('phase_precondition', 'classify'),
    ('architect_prepass', 'plan'),
    ('lane_writes', 'plan'),
    ('mission', 'plan'),
    ('route_resolved', 'build'),
    ('arm_resolved', 'build'),
    ('worker_spawned', 'build'),
    ('product_close', 'build'),
    ('review_gate', 'review'),
    ('review_diff', 'review'),
    ('review_signals', 'review'),
    ('review_recorded', 'review'),
    ('dispatch_terminal', 'close'),
    ('lane_worktree_left', 'close'),
]


def parse_ts(s):
    if not s:
        return None
    for fmt in ('%Y-%m-%dT%H:%M:%S.%fZ', '%Y-%m-%dT%H:%M:%SZ'):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def now_iso():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.') + \
        '{:03d}Z'.format(datetime.now(timezone.utc).microsecond // 1000)


def event_id_for(session_id, uuid):
    raw = '{}|{}'.format(session_id or '', uuid or '')
    return hashlib.sha1(raw.encode('utf-8')).hexdigest()


def derive_repo_lane(cwd):
    if not cwd:
        return (None, None)
    marker = '/.claude/worktrees/'
    idx = cwd.find(marker)
    if idx != -1:
        repo = os.path.basename(cwd[:idx].rstrip('/'))
        rest = cwd[idx + len(marker):]
        lane = rest.split('/')[0] if rest else None
        return (repo or None, lane or None)
    return (os.path.basename(cwd.rstrip('/')) or None, 'main')


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
        idx.setdefault(task_id, jpath)
        idx.setdefault(task_dir, jpath)
        try:
            with open(jpath, errors='ignore') as f:
                for line in f:
                    m = re.search(r'founder_task=(\S+)', line)
                    if m:
                        idx.setdefault(m.group(1), jpath)
        except OSError:
            continue
    _journal_index = idx
    return idx


def resolve_phase(lane, ts_dt):
    if not lane or lane == 'main' or ts_dt is None:
        return 'unknown'
    jpath = journal_index().get(lane)
    if not jpath:
        return 'unknown'
    best_phase = 'unknown'
    best_ts = None
    try:
        with open(jpath, errors='ignore') as f:
            for line in f:
                m = re.match(r'-\s*(\S+)\s+\[decision\]\s+(\S+)', line)
                if not m:
                    continue
                lts = parse_ts(m.group(1))
                if lts is None or lts > ts_dt:
                    continue
                ev = m.group(2)
                phase = None
                for prefix, ph in PHASE_PREFIX_MAP:
                    if ev.startswith(prefix):
                        phase = ph
                        break
                if phase is None:
                    continue
                if best_ts is None or lts >= best_ts:
                    best_ts = lts
                    best_phase = phase
    except OSError:
        return 'unknown'
    return best_phase


existing_ids = set()
if os.path.isfile(EXISTING_JSONL):
    with open(EXISTING_JSONL, errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            eid = rec.get('event_id')
            if eid:
                existing_ids.add(eid)

cutoff = datetime.now(timezone.utc) - timedelta(days=SINCE_DAYS)
seen_this_run = set()
new_rows = []


def base_record(d, skill, source, ts_raw, ts_dt, outcome):
    cwd = d.get('cwd')
    repo, lane = derive_repo_lane(cwd)
    return {
        'event_id': event_id_for(d.get('sessionId'), d.get('uuid')),
        'ts': ts_raw,
        'skill': skill,
        'source': source,
        'session_id': d.get('sessionId'),
        'agent_id': d.get('agentId'),
        'is_sidechain': bool(d.get('isSidechain', False)),
        'cwd': cwd,
        'repo': repo,
        'lane': lane,
        'git_branch': d.get('gitBranch'),
        'phase': resolve_phase(lane, ts_dt),
        'outcome': outcome,
        'collected_at': now_iso(),
    }


def scan_file(path):
    try:
        with open(path, errors='ignore') as f:
            raw_lines = f.readlines()
    except OSError:
        return

    parsed = []
    for line in raw_lines:
        line = line.strip()
        if not line:
            parsed.append(None)
            continue
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            parsed.append(None)

    tool_uses = {}   # tool_use_id -> (d, skill)
    tool_results = {}  # tool_use_id -> success (True/False/None)

    for d in parsed:
        if d is None:
            continue
        msg = d.get('message')
        if not isinstance(msg, dict):
            continue
        content = msg.get('content')
        if not isinstance(content, list):
            continue
        if d.get('type') == 'assistant':
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get('type') == 'tool_use' and item.get('name') == 'Skill':
                    inp = item.get('input')
                    skill = inp.get('skill') if isinstance(inp, dict) else None
                    if skill:
                        tool_uses[item.get('id')] = (d, skill)
        elif d.get('type') == 'user':
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get('type') == 'tool_result':
                    tur = d.get('toolUseResult')
                    success = tur.get('success') if isinstance(tur, dict) else None
                    tool_results[item.get('tool_use_id')] = success

    for tuid, (d, skill) in tool_uses.items():
        ts_raw = d.get('timestamp')
        ts_dt = parse_ts(ts_raw)
        if ts_dt is None or ts_dt < cutoff:
            continue
        eid = event_id_for(d.get('sessionId'), d.get('uuid'))
        if eid in existing_ids or eid in seen_this_run:
            continue
        success = tool_results.get(tuid)
        if success is True:
            outcome = 'ok'
        elif success is False:
            outcome = 'error'
        else:
            outcome = 'n_a'
        rec = base_record(d, skill, 'skill_tool_use', ts_raw, ts_dt, outcome)
        seen_this_run.add(eid)
        new_rows.append(rec)

    for d in parsed:
        if d is None:
            continue
        if d.get('type') != 'user' or d.get('isMeta') is not True:
            continue
        msg = d.get('message')
        if not isinstance(msg, dict):
            continue
        content = msg.get('content')
        if not isinstance(content, list):
            continue
        text_blob = ''
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'text':
                text_blob += item.get('text', '') + '\n'
        if not SKILL_TAG_RE.search(text_blob):
            continue  # slash commands carry <command-name> without this tag
        m = NAME_RE.search(text_blob)
        if not m:
            continue
        skill = m.group(1).strip()
        ts_raw = d.get('timestamp')
        ts_dt = parse_ts(ts_raw)
        if ts_dt is None or ts_dt < cutoff:
            continue
        eid = event_id_for(d.get('sessionId'), d.get('uuid'))
        if eid in existing_ids or eid in seen_this_run:
            continue
        rec = base_record(d, skill, 'skill_format_injection', ts_raw, ts_dt, 'n_a')
        seen_this_run.add(eid)
        new_rows.append(rec)


session_files = glob.glob(os.path.join(TRANSCRIPTS_ROOT, '*', '*.jsonl'))
subagent_files = glob.glob(os.path.join(TRANSCRIPTS_ROOT, '*', '*', 'subagents', 'agent-*.jsonl'))

for path in session_files + subagent_files:
    scan_file(path)

for rec in new_rows:
    sys.stdout.write(json.dumps(rec, sort_keys=False, separators=(',', ':')) + '\n')
PYEOF
py_rc=$?

if [[ $py_rc -ne 0 ]]; then
  echo "leadv2-skill-telemetry-collect: collector failed (rc=${py_rc})" >&2
  exit 1
fi

new_count=$(wc -l < "$TMP" | tr -d ' ')
if [[ "$new_count" -eq 0 ]]; then
  echo "leadv2-skill-telemetry-collect: 0 new rows (idempotent, ${new_count} appended) -> ${OUT_JSONL}"
  exit 0
fi

(
  lv2_lock_wait "$LOCKF" 10 || exit 3
  cat "$TMP" >> "$OUT_JSONL"
) 9>"$LOCKF"
lock_rc=$?
if [[ $lock_rc -ne 0 ]]; then
  echo "leadv2-skill-telemetry-collect: locked append failed (rc=${lock_rc})" >&2
  exit "$lock_rc"
fi

echo "leadv2-skill-telemetry-collect: appended ${new_count} new row(s) -> ${OUT_JSONL}"
