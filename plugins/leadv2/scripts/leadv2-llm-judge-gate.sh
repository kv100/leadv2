#!/usr/bin/env bash
# leadv2-llm-judge-gate.sh — Load-bearing consumer of docs/handoff/<id>/llm-judge.yaml.
# DEPLOY-JUDGE-IS-ADVISORY-AND-NORMALIZES-KNOWN-BAD-01: this is the one place
# a known-bad judge verdict becomes a deploy REFUSAL, not a checklist item
# left to whichever session reads SKILL.md prose.
#
# Usage:
#   leadv2-llm-judge-gate.sh --task-id <id> [--project-root <path>]
#
# Reads: docs/handoff/<task-id>/llm-judge.yaml
#
# Exit codes:
#   0 = deploy may proceed (verdict go / go-with-caveats, or a legitimate skip)
#   1 = REFUSE — no-go, judge_unavailable (parse error / cost-ceiling skip),
#       or the verdict file is missing/unreadable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# Not readonly: --project-root (parsed below) must be able to override the
# PROJECT_ROOT env default.
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

log()       { printf '[leadv2-judge-gate] %s\n' "$*" >&2; }
log_error() { printf '[leadv2-judge-gate] ERROR: %s\n' "$*" >&2; }

usage() {
  cat >&2 <<'EOF'
Usage: leadv2-llm-judge-gate.sh --task-id <id> [--project-root <path>]
EOF
  exit 1
}

TASK_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)      TASK_ID="$2";      shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) log_error "unknown arg: $1"; usage ;;
  esac
done

[[ -z "$TASK_ID" ]] && { log_error "--task-id required"; usage; }

VERDICT_FILE="${PROJECT_ROOT}/docs/handoff/${TASK_ID}/llm-judge.yaml"

if [[ ! -f "$VERDICT_FILE" ]]; then
  log_error "no verdict file at $VERDICT_FILE — refusing deploy (missing judge artifact is not a pass)"
  exit 1
fi

result=$(python3 -c "
import sys, yaml
try:
    with open('$VERDICT_FILE') as fh:
        d = yaml.safe_load(fh) or {}
except Exception as e:
    print(f'unreadable:{e}')
    sys.exit(0)
j = d.get('llm_judge', d) if isinstance(d, dict) else {}
if not isinstance(j, dict):
    print('unreadable:not-a-dict')
    sys.exit(0)
print(j.get('verdict', 'unreadable'))
" 2>&1) || { log_error "verdict parse crashed: $result"; exit 1; }

if [[ "$result" == unreadable:* ]]; then
  log_error "verdict file unreadable ($VERDICT_FILE): ${result#unreadable:} — refusing deploy"
  exit 1
fi

log "verdict=$result"

case "$result" in
  go|go-with-caveats)
    exit 0
    ;;
  no-go|judge_unavailable)
    log_error "known-bad verdict ($result) — refusing deploy"
    exit 1
    ;;
  *)
    log_error "unrecognized verdict ($result) — refusing deploy (fail closed)"
    exit 1
    ;;
esac
