#!/usr/bin/env bash
# leadv2-lanes-resume.sh — SESSION-HANDOFF-01 resume composer.
# (renamed 2026-08-17, SUPERVISOR-DELETE-01; still contractually write-free,
# see below)
#
# Live-composes the bounded <supervisor-handoff> restore block from canonical
# on-disk sources — NO new state file, NO freeze/reground reuse, zero writes.
# Two call sites:
#   1. leadv2-lanes-snapshot.sh embeds this script's --json output as the
#      "resume" key of its own --json output, on every FULL (non-delta) call
#      — the mandatory first call the leadv2-supervise skill already makes.
#   2. `leadv2-lanes-snapshot.sh --print` execs straight into this script (no
#      tmux reconciliation / sentinel writes / phase-backfill) as a
#      lightweight fallback entry point, per SESSION-HANDOFF-01.
#
# Sources (read-only):
#   <control-plane>/active.yaml       — live session registry (already
#     reconciled by the time the mandatory first supervise call reads it)
#   docs/leadv2/open-threads.md       — head = semantic role/founder session
#     section (sacrosanct, never truncated), tail = freshest running log
#   docs/tasks.yaml                   — ranked via the SAME canonical
#     leadv2-tasks-lib.sh picker logic the (now-retired) supervise-pick.sh used
#     (no 2nd ranker)
#   <control-plane>/questions/*.yaml  — pending control-plane questions,
#     used only to annotate a lane's `blocker` field
#
# Usage: leadv2-lanes-resume.sh [--json] [--project-root <path>]
#   --json   emit the structured resume object (default: render the
#            human-readable <supervisor-handoff> text block to stdout)
#
# Cap: ~60-80 lines / <=6KB. Role+lanes+focus/next-action are sacrosanct;
# the tail (recent log entries, then tasks_top10) truncates first. Any
# missing/malformed source degrades that section visibly — never fakes
# continuity. Exit code is always 0 (a caller must never wedge on this
# best-effort composer); degraded state is reported IN the payload/block.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

JSON_MODE=0
PROJECT_ROOT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=1; shift ;;
    --project-root) PROJECT_ROOT_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      printf -- 'Usage: leadv2-lanes-resume.sh [--json] [--project-root <path>]\n'
      exit 0
      ;;
    *)
      printf -- '[lanes-resume] unknown arg: %s\n' "$1" >&2
      shift
      ;;
  esac
done

PROJECT_ROOT="$PROJECT_ROOT_ARG"
if [[ -z "$PROJECT_ROOT" ]]; then
  if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$LEADV2_PROJECT_ROOT"
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
  elif _lv2r_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
    PROJECT_ROOT="$_lv2r_top"
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  if [[ "$JSON_MODE" -eq 1 ]]; then
    printf -- '{"status":"degraded","reason":"root_error: could not resolve project root"}\n'
  else
    printf -- '<supervisor-handoff>\nHANDOFF DEGRADED — could not resolve project root (set LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR or run inside a git worktree).\n</supervisor-handoff>\n'
  fi
  exit 0
fi

ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" active.yaml 2>/dev/null || printf -- '%s/docs/leadv2/active.yaml' "$PROJECT_ROOT")"
CP_QUESTIONS_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" questions 2>/dev/null || true)"
OPEN_THREADS="${PROJECT_ROOT}/docs/leadv2/open-threads.md"
TASKS_YAML="${PROJECT_ROOT}/docs/tasks.yaml"

# Canonical task ranking order — reuse leadv2-tasks-lib.sh's picker (same
# lane/priority/created_at sort supervise-pick.sh presents to the founder),
# never a second ranking implementation. We only need the ordered id list;
# status/intent are read straight from tasks.yaml below; the picker supplies
# the canonical ranked id list.
TASKS_LIB="${SCRIPT_DIR}/leadv2-tasks-lib.sh"
TOP10_IDS=""
if [[ -f "$TASKS_LIB" ]]; then
  TOP10_IDS="$(PROJECT_ROOT="$PROJECT_ROOT" bash -c "source '$TASKS_LIB' 2>/dev/null; leadv2_tasks_top_n 10 2>/dev/null" | cut -f3 || true)"
fi

python3 - "$JSON_MODE" "$ACTIVE_YAML" "$OPEN_THREADS" "$TASKS_YAML" "$CP_QUESTIONS_DIR" "$TOP10_IDS" <<'PY'
import sys, os, json, glob, datetime, re

json_mode, active_yaml, open_threads, tasks_yaml, cp_dir, top10_ids_raw = sys.argv[1:7]
json_mode = json_mode == "1"

MAX_LINES = 80
MAX_BYTES = 6144
degraded = []

def read_yaml(path):
    try:
        import yaml
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except Exception:
        return None

# -- Live lanes from (already-reconciled) active.yaml --
lanes = []
active_data = read_yaml(active_yaml) if os.path.isfile(active_yaml) else None
if not isinstance(active_data, dict):
    degraded.append(f"active.yaml unavailable/malformed ({active_yaml})")
    active_data = {}

q_by_task = {}
if cp_dir and os.path.isdir(cp_dir):
    import yaml as _yaml
    for qf in sorted(glob.glob(os.path.join(cp_dir, "*.yaml"))):
        try:
            with open(qf, encoding="utf-8") as fh:
                qd = _yaml.safe_load(fh) or {}
        except Exception:
            continue
        if isinstance(qd, dict) and qd.get("status") == "pending" and qd.get("task_id"):
            q_by_task.setdefault(qd["task_id"], (qd.get("summary_for_lead") or qd.get("question") or "")[:60])

for s in (active_data.get("sessions") or []):
    if not isinstance(s, dict):
        continue
    tid = s.get("task_id", "?")
    lanes.append({
        "id": tid,
        "phase": s.get("phase") or "?",
        "pid": s.get("pid"),
        "provider": s.get("backend") or ("headless" if s.get("daemon_mode") else "terminal"),
        "blocker": q_by_task.get(tid, "-"),
    })

# -- open-threads.md: role head (sacrosanct) + freshest tail --
role_lines = []
recent_entries = []
next_action = None
focus = None
stale_warning = None
degraded_resume_instruction = None

def extract_role_section(lines):
    """Return the semantic role section, falling back to the first heading."""
    heading_re = re.compile(r"^(#{1,6})\s+(.*)$")
    role_re = re.compile(
        r"^\W*(?:1\.(?=\s|$)|ROLE\b|SESSION MODE\b|SESSION HANDOFF\b|FOUNDER\b)",
        re.IGNORECASE,
    )
    headings = []
    for index, line in enumerate(lines):
        match = heading_re.match(line)
        if match:
            headings.append((index, len(match.group(1)), match.group(2).strip()))

    if not headings:
        return [], "open-threads.md: no heading found while searching for role/session/founder section"

    start_index = None
    start_depth = None
    for index, depth, text in headings:
        if role_re.match(text):
            start_index, start_depth = index, depth
            break

    if start_index is None:
        first_index, first_depth, _ = headings[0]
        if first_index == 0:
            start_index, start_depth = first_index, first_depth
        else:
            # The contract only degrades when no heading exists. A non-heading
            # preamble does not authorize selecting a later unrelated section.
            return [], None

    end_index = min(start_index + 30, len(lines))
    for index, depth, _ in headings:
        if index > start_index and depth <= start_depth:
            end_index = min(end_index, index)
            break
    return lines[start_index:end_index], None

if not os.path.isfile(open_threads):
    degraded.append(f"open-threads.md unavailable ({open_threads})")
else:
    age_h = (datetime.datetime.now().timestamp() - os.path.getmtime(open_threads)) / 3600.0
    if age_h > 48:
        stale_warning = f"STALE open-threads.md (age {age_h:.0f}h) -- tail below omitted, role/rules still shown"
    try:
        with open(open_threads, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        lines = []
        degraded.append(f"open-threads.md unreadable ({open_threads}: {exc})")

    if not lines:
        if not any(item.startswith("open-threads.md unreadable") for item in degraded):
            degraded.append(f"open-threads.md empty ({open_threads})")
    else:
        role_lines, role_reason = extract_role_section(lines)
        if role_reason:
            degraded.append(role_reason)

    if stale_warning is None:
        heading_idxs = [i for i, ln in enumerate(lines) if ln.startswith("## ")]
        for idx in heading_idxs[-3:]:
            heading = lines[idx].lstrip("#").strip()
            body = ""
            for j in range(idx + 1, min(idx + 4, len(lines))):
                if lines[j].strip().startswith("-"):
                    body = lines[j].strip()
                    break
            recent_entries.append((heading, body))
        if heading_idxs:
            focus = lines[heading_idxs[-1]].lstrip("#").strip()
        for ln in lines:
            if ln.strip().startswith("ON RESUME FIRST"):
                next_action = ln.strip()  # last match wins -- freshest

if not role_lines:
    degraded_resume_instruction = (
        "ROLE UNAVAILABLE: read docs/leadv2/open-threads.md head verbatim; "
        "do not hand-rank docs/tasks.yaml"
    )

# -- tasks.yaml P0/P1 top-10 (id/status/intent) --
tasks_top = []
tasks_data = read_yaml(tasks_yaml) if os.path.isfile(tasks_yaml) else None
if tasks_data is None:
    degraded.append(f"tasks.yaml unavailable/malformed ({tasks_yaml})")
else:
    items = tasks_data.get("tasks") if isinstance(tasks_data, dict) else tasks_data
    by_id = {str(t.get("id")): t for t in (items or []) if isinstance(t, dict)}
    for tid in [i for i in top10_ids_raw.splitlines() if i.strip()][:10]:
        t = by_id.get(tid)
        if not t:
            continue
        intent = (t.get("intent") or t.get("title") or "")[:70]
        tasks_top.append({"id": tid, "status": t.get("status", "?"), "intent": intent})

# -- Render, with tail-truncates-first cap enforcement --
POINTERS = "Full: docs/leadv2/open-threads.md . docs/leadv2/active.yaml . docs/tasks.yaml"

def render(recent_n, tasks_n, lanes_n):
    out = ["<supervisor-handoff>", "ROLE (sacrosanct):"]
    out.extend(role_lines if role_lines else ["  (unavailable -- see degraded)"])
    out.append("")
    if stale_warning:
        out.append(f"WARN {stale_warning}")
    out.append(f"LIVE LANES ({len(lanes)}):")
    if lanes:
        for l in lanes[:lanes_n]:
            out.append(f"  - {l['id']} phase={l['phase']} pid={l['pid']} provider={l['provider']} blocker={l['blocker']}")
        if len(lanes) > lanes_n:
            out.append(f"  ... +{len(lanes) - lanes_n} more (see active.yaml)")
    else:
        out.append("  (none live)")
    out.append("")
    out.append(f"FOCUS: {focus or '(unavailable)'}")
    out.append(f"NEXT-ACTION: {next_action or '(none captured -- see tail below)'}")
    if recent_n and recent_entries:
        out.append("")
        out.append("RECENT (freshest tail, thread log -- decisions+asks commingled at source):")
        for heading, body in recent_entries[-recent_n:]:
            line = f"  - {heading}"
            if body:
                line += f" :: {body[:90]}"
            out.append(line)
    if tasks_n and tasks_top:
        out.append("")
        out.append(f"TASKS.YAML TOP-{min(tasks_n, len(tasks_top))} (P0/P1 ranked):")
        for t in tasks_top[:tasks_n]:
            out.append(f"  - {t['id']} [{t['status']}] {t['intent']}")
    if degraded:
        out.append("")
        out.append("HANDOFF DEGRADED:")
        for d in degraded:
            out.append(f"  - {d}")
        if degraded_resume_instruction:
            out.append(f"  - {degraded_resume_instruction}")
    out.append("")
    out.append(POINTERS)
    out.append("</supervisor-handoff>")
    return "\n".join(out)

recent_n, tasks_n, lanes_n = 3, 10, len(lanes) or 1
block = render(recent_n, tasks_n, lanes_n)
# Tail truncates first: tasks_top10 shrinks before recent entries; lanes and
# role are never reduced (sacrosanct per spec).
while (len(block.splitlines()) > MAX_LINES or len(block.encode("utf-8")) > MAX_BYTES):
    if tasks_n > 3:
        tasks_n = max(3, tasks_n - 3)
    elif recent_n > 1:
        recent_n -= 1
    elif tasks_n > 0:
        tasks_n = 0
    else:
        degraded.append("block truncated to fit cap -- some tail content dropped")
        break
    block = render(recent_n, tasks_n, lanes_n)

if json_mode:
    print(json.dumps({
        "status": "degraded" if degraded else "ok",
        "role_present": bool(role_lines),
        "lanes": lanes,
        "focus": focus,
        "next_action": next_action,
        "recent": [{"heading": h, "body": b} for h, b in recent_entries[:recent_n]],
        "tasks_top10": tasks_top[:tasks_n],
        "degraded": degraded,
        "degraded_resume_instruction": degraded_resume_instruction,
        "pointers": POINTERS,
        "block": block,
        "block_lines": len(block.splitlines()),
        "block_bytes": len(block.encode("utf-8")),
    }, indent=2))
else:
    print(block)
PY
