#!/usr/bin/env bash
# lib/leadv2-receipt-freshness.sh — receipt freshness guard (SESSION-CLOSE-
# FIXES-01 fix 2). A completion receipt at <state>/completions/<id>.json is
# only valid proof of completion if the task is NOT currently open (status
# queued|pending) in docs/tasks.yaml. A re-filed task carries a stale receipt
# from a prior close; this guard detects that and renames the receipt aside
# (never deletes) so the runner proceeds instead of refusing to run.
#
# ONE implementation, THREE sourcers (kimi/glm/session-runner) — matching the
# lib/leadv2-alarm-dedupe.sh convention. The three runners already drifted on
# the receipt-parsing predicate (three near-identical sentinel_present blocks);
# do not triplicate this too.
#
# Decision table — fail-closed everywhere except the one proven-stale case:
#   receipt absent                                   -> HONOUR (rc 1, unchanged)
#   tasks.yaml missing / unreadable / parse error    -> HONOUR (rc 1)
#   task id absent from tasks.yaml                   -> HONOUR (rc 1)
#   task id present, status queued|pending           -> STALE  (rc 0, rename)
#   task id present, any other status                -> HONOUR (rc 1)
# Any exception -> HONOUR (rc 1).
#
# Env:
#   LEADV2_RECEIPT_REQUEUE_GUARD — default 1 (on); 0 => always HONOUR (today's
#     behaviour), so a bad tasks.yaml cannot brick the fleet.
#   LEADV2_TASKS_YAML — test injection of the tasks.yaml path.
#   LEADV2_PROJECT_ROOT / PROJECT_ROOT — repo root for tasks.yaml resolution.
#
# Surfaces:
#   leadv2_receipt_is_stale <task_id> <receipt_path> [tasks_yaml] [log_file]
#       rc 0 = STALE (re-queued: receipt renamed aside + logged, proceed);
#       rc 1 = HONOUR (receipt is valid proof, unchanged — do not run).
#   tasks_yaml resolution: positional > $LEADV2_TASKS_YAML >
#     $LEADV2_PROJECT_ROOT/docs/tasks.yaml.
#   log_file (4th arg, optional) receives the rename line in addition to stderr
#     so it lands in the runner's normal log. If unset, the line goes to stderr.
#
# Sourcing this file defines the functions; it performs no I/O at source time.

set -o pipefail

# Internal: emit the rename/ignore line to the runner's log (4th arg) and stderr.
_leadv2_receipt_log() {
  local log_file="${1:-}" msg="${2:-}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"
  if [[ -n "$log_file" ]]; then
    mkdir -p "$(dirname -- "$log_file")" 2>/dev/null || true
    printf -- '%s [receipt-freshness] %s\n' "$ts" "$msg" >>"$log_file" 2>/dev/null || true
  fi
  printf -- '[receipt-freshness] %s\n' "$msg" >&2
}

# Verdict + action in one call: returns 0 (STALE: renamed, proceed) / 1 (HONOUR).
leadv2_receipt_is_stale() {
  local task_id="${1:?task_id required}"
  local receipt_path="${2:?receipt_path required}"
  local tasks_yaml_override="${3:-}"
  local log_file="${4:-}"

  # Kill-switch: 0 => honour the receipt unconditionally (today's behaviour).
  [[ "${LEADV2_RECEIPT_REQUEUE_GUARD:-1}" == "1" ]] || return 1
  # No receipt on disk -> nothing to invalidate; honour (unchanged).
  [[ -f "$receipt_path" ]] || return 1

  local verdict
  verdict="$(LEADV2_RECEIPT_TASKS_YAML_OVERRIDE="$tasks_yaml_override" \
             LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT:-}}" \
             python3 - "$task_id" <<'PYEOF' 2>/dev/null || true
import os, sys
task_id = sys.argv[1]
override = os.environ.get("LEADV2_RECEIPT_TASKS_YAML_OVERRIDE") or ""
paths = []
if override:
    paths.append(override)
env_path = os.environ.get("LEADV2_TASKS_YAML") or ""
if env_path:
    paths.append(env_path)
proj = os.environ.get("LEADV2_PROJECT_ROOT") or os.environ.get("PROJECT_ROOT") or ""
if proj:
    paths.append(os.path.join(proj, "docs", "tasks.yaml"))

# Accept BOTH shapes tasks-lib documents (GATE-A2-FIX-01): a bare top-level
# list, OR a mapping with a `tasks:` key. First readable tasks.yaml wins; a
# missing/unreadable/parse-error tasks.yaml => HONOUR (fail-closed).
try:
    import yaml
except Exception:
    print("HONOUR"); raise SystemExit(0)

for p in paths:
    try:
        with open(p, encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except Exception:
        continue                       # unreadable / parse error -> try next
    tasks = data if isinstance(data, list) else (
        data.get("tasks") if isinstance(data, dict) else None)
    if not isinstance(tasks, list):
        continue                       # readable but wrong shape -> try next
    for t in tasks:
        if isinstance(t, dict) and t.get("id") == task_id:
            status = str(t.get("status") or "")
            if status in ("queued", "pending"):
                print("STALE")
            else:
                print("HONOUR")        # present but not open -> honour
            raise SystemExit(0)
    print("HONOUR")                    # readable tasks.yaml, id absent -> honour
    raise SystemExit(0)
# No readable tasks.yaml at all -> honour (missing/unreadable).
print("HONOUR")
PYEOF
)"

  # A python failure (no python, fatal) => verdict empty => honour.
  if [[ "$verdict" != "STALE" ]]; then
    return 1
  fi

  # STALE: rename (never delete), then return 0 so the caller proceeds. A rename
  # failure (read-only dir) is non-fatal — the guard's purpose is to UNBLOCK the
  # run, not to manage files; return 0 regardless and log the failure.
  local stamp dest
  stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf 'unknown')"
  dest="${receipt_path}.stale-${stamp}"
  if mv -f "$receipt_path" "$dest" 2>/dev/null; then
    _leadv2_receipt_log "$log_file" \
      "stale receipt (task re-queued) — ignoring + renaming to ${dest##*/}"
  else
    _leadv2_receipt_log "$log_file" \
      "stale receipt (task re-queued) — ignoring; rename to ${dest##*/} failed (read-only?); proceeding"
  fi
  return 0
}
