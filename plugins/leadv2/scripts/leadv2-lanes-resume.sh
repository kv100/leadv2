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
# Cap: ~60-80 lines / <=6KB. Lanes are sacrosanct; role/focus/next-action are
# permanently unavailable (ROLE-LEDGER-RETIRE-01 -- the founder-session ledger
# this composer used to read is retired) and reported via `degraded`; the
# tail (recent log entries, then tasks_top10) truncates first. Any
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

python3 - "$JSON_MODE" "$ACTIVE_YAML" "$TASKS_YAML" "$CP_QUESTIONS_DIR" "$TOP10_IDS" <<'PY'
import sys, os, json, glob

json_mode, active_yaml, tasks_yaml, cp_dir, top10_ids_raw = sys.argv[1:6]
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

# -- role/focus/next-action/recent: permanently retired (ROLE-LEDGER-RETIRE-01) --
# The founder-session ledger this composer used to read for these fields is
# retired and nothing replaces it. Report the keys honestly rather than
# dropping them -- callers still read this shape.
role_lines = []
recent_entries = []
next_action = None
focus = None
stale_warning = None
degraded.append("founder-session ledger retired (ROLE-LEDGER-RETIRE-01) -- role/focus/next-action/recent unavailable")
degraded_resume_instruction = (
    "ROLE UNAVAILABLE: founder-session ledger is retired; rank docs/tasks.yaml directly"
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
POINTERS = "Full: docs/leadv2/active.yaml . docs/tasks.yaml"

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
