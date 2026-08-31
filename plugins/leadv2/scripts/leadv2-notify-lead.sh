#!/usr/bin/env bash
# leadv2-notify-lead.sh — LEAD-WORKER-CHANNEL-01 the ONE worker->lead notifier.
#
# The design constraint that decides everything: bash cannot call
# SendMessage, only a model can. So a design where delivery depends on the
# message going out is a design that goes silent the moment a model is
# busy, dead, or headless. Therefore the message is the fast path and the
# durable row is the guaranteed path:
#   1. append one row to leadv2-inbox.sh, unconditionally, no network, no
#      model involved;
#   2. print, on stdout, the one-line SendMessage payload a worker MODEL
#      may choose to relay. Printing it is the WHOLE contract -- this
#      script never calls SendMessage and never blocks on one.
# A notifier that can fail a lane is worse than no notifier: every failure
# below is swallowed and this script exits 0 regardless.
#
# Usage: leadv2-notify-lead.sh <task-id> <event> <one-line-text>
#
# Lead resolution, in order:
#   1. $LEADV2_LEAD_SESSION_ID, if the caller already knows it (e.g. a
#      dispatch-code.sh call site that computed _lead_session_id moments
#      earlier for a lane whose registration was refused, so no row for
#      this task-id exists yet in active.yaml to look up);
#   2. active.yaml -- the SAME lane registry leadv2-dispatch-code.sh's
#      lane_register() writes (schema: data['sessions'] rows keyed by
#      task_id, each carrying lead_session_id), read at the SAME
#      control-plane root leadv2-inbox.sh appends to (leadv2-state-path.sh
#      --no-link active.yaml). This is the "lead's identity IS already
#      captured" fact this task's brief points at.
#   3. "unknown" -- row still written, exit 0 (rule 4: a lead unknown or
#      unreachable never fails the caller's lane).
#
# Env overrides (tests sandbox with these):
#   PROJECT_ROOT               - repo root
#   LEADV2_LEAD_SESSION_ID      - explicit lead override (see step 1 above)
#   LEADV2_ACTIVE_YAML_PATH     - explicit active.yaml path (test seam)
#   LEADV2_LEAD_INBOX_DIR       - forwarded to leadv2-inbox.sh unchanged

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Never fail the caller's lane, even over a usage mistake.
if [[ $# -lt 3 ]]; then
  printf -- 'Usage: leadv2-notify-lead.sh <task-id> <event> <one-line-text>\n' >&2
  exit 0
fi
TASK_ID="$1"; EVENT="$2"; shift 2
TEXT="$*"

REPO="$(basename "${PROJECT_ROOT}")"
LANE="${TASK_ID}"

_resolve_lead() {
  if [[ -n "${LEADV2_LEAD_SESSION_ID:-}" ]]; then
    printf '%s' "${LEADV2_LEAD_SESSION_ID}"
    return 0
  fi
  local active_yaml
  active_yaml="${LEADV2_ACTIVE_YAML_PATH:-}"
  if [[ -z "$active_yaml" ]]; then
    active_yaml="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null)" || active_yaml=""
  fi
  [[ -n "$active_yaml" && -f "$active_yaml" ]] || { printf 'unknown'; return 0; }
  python3 - "$active_yaml" "$TASK_ID" <<'PYEOF' 2>/dev/null
import sys
try:
    import yaml
except ImportError:
    print("unknown"); sys.exit(0)
path, task_id = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print("unknown"); sys.exit(0)
rows = doc.get("sessions") if isinstance(doc, dict) else []
if not isinstance(rows, list):
    rows = []
found = "unknown"
for row in rows:
    if isinstance(row, dict) and row.get("task_id") == task_id:
        found = row.get("lead_session_id") or "unknown"
print(found)
PYEOF
}

LEAD_ID="$(_resolve_lead)"
[[ -n "$LEAD_ID" ]] || LEAD_ID="unknown"

"${SCRIPT_DIR}/leadv2-inbox.sh" append "$LEAD_ID" "$REPO" "$TASK_ID" "$LANE" "$EVENT" "$TEXT" >/dev/null 2>&1 || true

printf -- '[leadv2-notify] lead=%s task=%s event=%s: %s\n' "$LEAD_ID" "$TASK_ID" "$EVENT" "$TEXT"
exit 0
