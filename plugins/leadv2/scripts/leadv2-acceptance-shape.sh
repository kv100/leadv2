#!/usr/bin/env bash
# leadv2-acceptance-shape.sh — RED-FIRST-GATE-01 R2.
#
# PROBLEM THIS SOLVES
#   skills/leadv2-plan/SKILL.md:433 defines "acceptance" as an internal-contract
#   invocation ("shell command, grep pattern, mypy/pytest invocation") — i.e. the
#   code's own author states what counts as done, in terms only the code speaks.
#   That is a root cause of tautological review: 2026-07-30 shipped a rendered
#   status line with 6+ real defects while its 25/25-green suite never once ran
#   the line and read it. R2 requires acceptance to be a SURFACE OBSERVABLE
#   (rendered line, prod DB row, log line, HTTP response, file artifact),
#   authored BEFORE the diff exists (by the architect prepass), never by the
#   implementer.
#
# SUBCOMMANDS
#   validate <context.yaml>
#     - top-level `acceptance:` block present
#     - `acceptance.surface` in {rendered_line, prod_db_row, log_line,
#       http_response, file_artifact}
#     - `acceptance.observable` is non-empty and free of internal-contract
#       phrasing (case-insensitive: "function ", " returns ", "exit code",
#       "variable", "is set to")
#     - `acceptance.authored_at` parses as ISO-8601
#     exit 0 ok / 1 refuse (reason(s) on stderr)
#
#   assert-precedence --task-id <id> [--context <context.yaml>]
#     `acceptance.authored_at` must be <= the earliest mtime among the files
#     named in LANE_WRITES for this task (read from context.yaml `lane_writes:`
#     if present, else the architect prepass artifact's trailing
#     `LANE_WRITES:` line). Files that do not exist yet are skipped (nothing
#     to compare against); if none of the named files exist, precedence is
#     vacuously true (not yet buildable), never a refusal.
#     exit 0 ok / 1 refuse
#
# GATE FLAG: LEADV2_REQUIRE_ACCEPTANCE=0|1 (default 1) — read by callers
# (leadv2-dispatch-code.sh park branch, leadv2-phase8-assert.sh A11), not by
# this script itself: this script always evaluates and always reports the
# true verdict; callers decide whether a failing verdict blocks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-"$0"}")" 2>/dev/null && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
export LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"
# shellcheck source=leadv2-helpers.sh
source "${SCRIPT_DIR}/leadv2-helpers.sh"
_lv2_load_paths

log() { printf -- '[acceptance-shape] %s\n' "$*" >&2; }

cmd_validate() {
  local ctx="${1:-}"
  [[ -n "$ctx" ]] || { log "validate: <context.yaml> path required"; return 1; }
  [[ -f "$ctx" ]] || { log "validate: not found: ${ctx}"; return 1; }
  python3 -c '
import datetime, sys
import yaml

path = sys.argv[1]
BAD_PHRASES = ["function ", " returns ", "exit code", "variable", "is set to"]
SURFACES = {"rendered_line", "prod_db_row", "log_line", "http_response", "file_artifact"}

try:
    doc = yaml.safe_load(open(path)) or {}
except Exception as exc:
    print(f"unparseable YAML: {exc}", file=sys.stderr)
    sys.exit(1)

acc = doc.get("acceptance")
if not isinstance(acc, dict):
    print("acceptance: block missing or not a mapping", file=sys.stderr)
    sys.exit(1)

reasons = []
surface = acc.get("surface")
if surface not in SURFACES:
    reasons.append(f"acceptance.surface {surface!r} not in {sorted(SURFACES)}")

observable = (acc.get("observable") or "").strip()
if not observable:
    reasons.append("acceptance.observable is empty")
else:
    low = observable.lower()
    hit = [p for p in BAD_PHRASES if p in low]
    if hit:
        reasons.append(f"acceptance.observable reads like an internal contract (phrases: {hit}) — restate as what a human sees at the surface")

authored_at = acc.get("authored_at")
if not authored_at:
    reasons.append("acceptance.authored_at missing")
else:
    try:
        datetime.datetime.fromisoformat(str(authored_at).replace("Z", "+00:00"))
    except Exception:
        reasons.append(f"acceptance.authored_at {authored_at!r} is not ISO-8601 parseable")

if reasons:
    for r in reasons:
        print(f"REFUSED: {r}", file=sys.stderr)
    sys.exit(1)

print(f"OK: surface={surface} authored_at={authored_at}")
sys.exit(0)
' "$ctx"
}

_as_lane_writes() { # <task_id> <ctx_yaml> -> newline list of repo-relative paths
  local task_id="$1" ctx="$2"
  local from_ctx=""
  if [[ -f "$ctx" ]]; then
    from_ctx="$(python3 -c '
import sys, yaml
try:
    doc = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    doc = {}
lw = doc.get("lane_writes")
if isinstance(lw, str):
    for p in lw.split(","):
        p = p.strip()
        if p:
            print(p)
elif isinstance(lw, list):
    for p in lw:
        print(str(p).strip())
' "$ctx" 2>/dev/null)"
  fi
  if [[ -n "$from_ctx" ]]; then
    printf '%s\n' "$from_ctx"
    return
  fi
  local prepass_dir="${LEADV2_HANDOFF_DIR}/${task_id}-architect"
  local cand
  for cand in "${prepass_dir}/architect.full.md" "${LEADV2_HANDOFF_DIR}/${task_id}/architect-prepass.md"; do
    [[ -f "$cand" ]] || continue
    grep -m1 '^LANE_WRITES:' "$cand" | sed 's/^LANE_WRITES:[[:space:]]*//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d'
    return
  done
}

cmd_assert_precedence() {
  local task_id="" ctx=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --context) ctx="$2"; shift 2 ;;
      *) log "assert-precedence: unknown arg $1"; return 1 ;;
    esac
  done
  [[ -n "$task_id" ]] || { log "assert-precedence: --task-id required"; return 1; }
  [[ -n "$ctx" ]] || ctx="${LEADV2_HANDOFF_DIR}/${task_id}/context.yaml"
  [[ -f "$ctx" ]] || { log "assert-precedence: no context.yaml at ${ctx}"; return 1; }

  local authored_at
  authored_at="$(python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
print((doc.get("acceptance") or {}).get("authored_at") or "")
' "$ctx")"
  [[ -n "$authored_at" ]] || { log "assert-precedence: acceptance.authored_at missing in ${ctx}"; return 1; }

  local authored_epoch
  authored_epoch="$(python3 -c '
import datetime, sys
s = sys.argv[1].replace("Z", "+00:00")
print(int(datetime.datetime.fromisoformat(s).timestamp()))
' "$authored_at" 2>/dev/null)"
  [[ -n "$authored_epoch" ]] || { log "assert-precedence: acceptance.authored_at ${authored_at} not parseable"; return 1; }

  local writes; writes="$(_as_lane_writes "$task_id" "$ctx")"
  if [[ -z "$writes" ]]; then
    log "assert-precedence: no LANE_WRITES found for ${task_id} — nothing to compare, treating as vacuously ok"
    return 0
  fi

  local earliest="" f mtime
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "${PROJECT_ROOT}/${f}" ]] || continue
    mtime="$(python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "${PROJECT_ROOT}/${f}" 2>/dev/null)"
    [[ -z "$mtime" ]] && continue
    if [[ -z "$earliest" || "$mtime" -lt "$earliest" ]]; then earliest="$mtime"; fi
  done <<< "$writes"

  if [[ -z "$earliest" ]]; then
    log "assert-precedence: none of the LANE_WRITES files exist yet — vacuously ok (not yet built)"
    return 0
  fi

  if [[ "$authored_epoch" -le "$earliest" ]]; then
    log "assert-precedence OK: authored_at=${authored_at} (${authored_epoch}) <= earliest LANE_WRITES mtime (${earliest})"
    return 0
  fi
  log "assert-precedence REFUSED: authored_at=${authored_at} (${authored_epoch}) is AFTER earliest LANE_WRITES mtime (${earliest}) — acceptance was written after the diff existed"
  return 1
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] && shift || true
  case "$sub" in
    validate) cmd_validate "$@" ;;
    assert-precedence) cmd_assert_precedence "$@" ;;
    *) log "usage: leadv2-acceptance-shape.sh {validate <context.yaml>|assert-precedence --task-id <id> [--context <path>]}"; return 2 ;;
  esac
}

main "$@"
