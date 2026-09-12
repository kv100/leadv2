#!/usr/bin/env bash
# leadv2-lanes-resume.sh — bounded, read-only resume composer.
#
# Continuity comes from the live registry, tasks.yaml, and scheduled decisions.
# The role contract is plugin-owned, so it stays stable without a repo-local
# journal that can be stale or misclassified.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_MODE=0
PROJECT_ROOT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=1; shift ;;
    --project-root) PROJECT_ROOT_ARG="${2:-}"; shift 2 ;;
    -h|--help) printf 'Usage: leadv2-lanes-resume.sh [--json] [--project-root <path>]\n'; exit 0 ;;
    *) printf '[lanes-resume] unknown arg: %s\n' "$1" >&2; shift ;;
  esac
done

PROJECT_ROOT="$PROJECT_ROOT_ARG"
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  if [[ "$JSON_MODE" -eq 1 ]]; then
    printf '{"status":"degraded","reason":"root_error: could not resolve project root"}\n'
  else
    printf '<supervisor-handoff>\nHANDOFF DEGRADED — could not resolve project root.\n</supervisor-handoff>\n'
  fi
  exit 0
fi

ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" active.yaml 2>/dev/null || printf '%s/docs/leadv2/active.yaml' "$PROJECT_ROOT")"
TASKS_YAML="${PROJECT_ROOT}/docs/tasks.yaml"
SCHEDULED_DECISIONS="${PROJECT_ROOT}/docs/leadv2/scheduled-decisions.md"

python3 - "$JSON_MODE" "$ACTIVE_YAML" "$TASKS_YAML" "$SCHEDULED_DECISIONS" <<'PY'
import datetime, json, os, sys

json_mode, active_yaml, tasks_yaml, scheduled = sys.argv[1:5]
degraded, lanes, tasks = [], [], []

def read_yaml(path):
    try:
        import yaml
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except Exception:
        return None

active = read_yaml(active_yaml)
if not isinstance(active, dict):
    degraded.append(f"active.yaml unavailable/malformed ({active_yaml})")
    active = {}
for row in active.get("sessions") or []:
    if isinstance(row, dict) and not row.get("stale"):
        lanes.append({
            "id": row.get("task_id", "?"), "phase": row.get("phase", "?"),
            "pid": row.get("pid"), "provider": row.get("backend") or "terminal",
        })

data = read_yaml(tasks_yaml)
if data is None:
    degraded.append(f"tasks.yaml unavailable/malformed ({tasks_yaml})")
else:
    items = data.get("tasks") if isinstance(data, dict) else data
    for row in items or []:
        if isinstance(row, dict) and str(row.get("status", "")).lower() not in {
            "done", "closed", "resolved", "complete", "completed", "cancelled", "canceled"
        }:
            tasks.append({"id": row.get("id", "?"), "status": row.get("status", "?"),
                          "intent": (row.get("intent") or row.get("title") or "")[:70],
                          "priority": row.get("priority") or ""})
tasks.sort(key=lambda row: (row["priority"] or "P9", str(row["id"])))

out = ["<supervisor-handoff>",
       "ROLE (stable): ${CLAUDE_PLUGIN_ROOT}/docs/single-lead-pulse.md", "",
       f"LIVE LANES ({len(lanes)}):"]
if lanes:
    out.extend(f"  - {row['id']} phase={row['phase']} pid={row['pid']} provider={row['provider']}" for row in lanes)
else:
    out.append("  (none live)")
out += ["", f"TASKS.YAML TOP-{min(10, len(tasks))}:"]
if tasks:
    out.extend(f"  - {row['id']} [{row['status']}] {row['intent']}" for row in tasks[:10])
else:
    out.append("  (none open)")
if not os.path.isfile(scheduled):
    degraded.append(f"scheduled-decisions.md unavailable ({scheduled})")
if degraded:
    out += ["", "HANDOFF DEGRADED:"] + [f"  - {item}" for item in degraded]
out += ["", "Full: docs/leadv2/active.yaml . docs/tasks.yaml . docs/leadv2/scheduled-decisions.md", "</supervisor-handoff>"]
block = "\n".join(out)
if json_mode == "1":
    print(json.dumps({"status": "degraded" if degraded else "ok", "lanes": lanes,
                      "tasks_top10": tasks[:10], "degraded": degraded, "block": block}, indent=2))
else:
    print(block)
PY
