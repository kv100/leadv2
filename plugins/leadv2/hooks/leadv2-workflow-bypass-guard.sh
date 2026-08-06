#!/usr/bin/env bash
# PreToolUse(Agent|Bash) guard -- enforce Workflow-first protocol for the plan phase,
# and (ONE-PATH-EVERYWHERE-01) enforce review-gate.md presence for the review phase.
#
# PLAN BRANCH (unchanged, hard scope fence — do not touch): when
# LEADV2_WORKFLOW_ENABLED=1 AND active phase is plan AND the sentinel file
# docs/handoff/<task>/.workflow-called-plan is absent AND the spawn targets
# architect -> deny.
#
# REVIEW BRANCH (ONE-PATH-EVERYWHERE-01, NEW): gated on its OWN env var,
# LEADV2_REVIEW_ENGINE=1 (separate from LEADV2_WORKFLOW_ENABLED — the plan branch
# above is untouched by this flag). Matches tool_name=="Bash" whose command
# invokes leadv2-dispatch-product-close.sh or leadv2-dispatch-code.sh (the lane),
# in addition to the original Agent/subagent_type match for critic/security-auditor.
# Pass predicate: docs/handoff/<task>/review-gate.md exists AND has a parseable
# `status:` line (the review-gate.md write contract per
# leadv2-dispatch-product-close.sh / leadv2-review-run.sh — NOT a literal
# `REVIEW_VERDICT:` string, which only appears in the reviewer's own
# review-<arm>.md output, never in review-gate.md itself). No sentinel check for
# review anymore (leadv2-workflow-sentinel-touch.sh narrowed to `plan` only).
# At LEADV2_REVIEW_ENGINE=0 (default) this whole branch is inert — same
# behaviour as before this change (byte-equivalent no-op for review).
#
# Env kill-switch: LEADV2_WORKFLOW_GUARD=0 -> exit 0 (fail open), applies to BOTH
# branches. Fail open on ANY parse error (`trap 'exit 0' ERR`).

set -euo pipefail
trap 'exit 0' ERR

[[ "${LEADV2_WORKFLOW_GUARD:-1}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# shellcheck source=leadv2-mode-isolation.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-mode-isolation.sh"
leadv2_hook_is_supervisor_session "$INPUT" && exit 0

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"

if [[ "$TOOL_NAME" == "Bash" ]]; then
  # REVIEW BRANCH — gated on LEADV2_REVIEW_ENGINE, NOT LEADV2_WORKFLOW_ENABLED.
  [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]] || exit 0

  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  case "$CMD" in
    *leadv2-dispatch-product-close.sh*|*leadv2-dispatch-code.sh*) ;;
    *) exit 0 ;;
  esac

  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
  [[ -z "$CWD" ]] && CWD="$PWD"

  ACTIVE_YAML=""
  for _cand in "$CWD/docs/leadv2/active.yaml" "$CWD/.claude/leadv2-tasks/active.yaml"; do
    [[ -f "$_cand" ]] && { ACTIVE_YAML="$_cand"; break; }
  done
  ACTIVE_PHASE="$(leadv2_hook_resolve_phase "$INPUT" "$ACTIVE_YAML" 2>/dev/null || true)"
  [[ "${ACTIVE_PHASE:-}" == "review" ]] || exit 0

  TASK_ID="$(leadv2_hook_resolve_task_id "$INPUT" "$ACTIVE_YAML" 2>/dev/null || true)"
  [[ -n "$TASK_ID" ]] || exit 0

  GATE="$CWD/docs/handoff/${TASK_ID}/review-gate.md"
  if [[ -f "$GATE" ]] && grep -qE '^[[:space:]]*status:[[:space:]]*[A-Za-z_]+' "$GATE" 2>/dev/null; then
    exit 0
  fi

  python3 -c "
import sys, json
task=sys.argv[1]
msg=('workflow-bypass-guard DENY: launching the product-close lane during phase=review '
     'without a parseable docs/handoff/%s/review-gate.md present. The review engine '
     '(leadv2-review-run.sh) is the sole owner of that file. To bypass: LEADV2_WORKFLOW_GUARD=0.' % task)
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':'deny','permissionDecisionReason':msg}}))
" -- "$TASK_ID"
  exit 0
fi

# PLAN BRANCH — unchanged (hard scope fence).
[[ "${LEADV2_WORKFLOW_ENABLED:-0}" == "1" ]] || exit 0

SUBTYPE="$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
case "$SUBTYPE" in
  architect|critic|security-auditor) ;;
  *) exit 0 ;;
esac

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
[[ -z "$CWD" ]] && CWD="$PWD"

ACTIVE_YAML=""
for _cand in "$CWD/docs/leadv2/active.yaml" "$CWD/.claude/leadv2-tasks/active.yaml"; do
  [[ -f "$_cand" ]] && { ACTIVE_YAML="$_cand"; break; }
done
ACTIVE_PHASE="$(leadv2_hook_resolve_phase "$INPUT" "$ACTIVE_YAML" 2>/dev/null || true)"
TASK_ID="$(leadv2_hook_resolve_task_id "$INPUT" "$ACTIVE_YAML" 2>/dev/null || true)"

# ONE-PATH-EVERYWHERE-01: review is no longer enforced on this Agent/subagent_type
# path at all — its enforcement moved entirely to the Bash-tool review branch above
# (sentinel-touch.sh was narrowed to `plan` only, so a review sentinel would never
# be written for this path to check anyway).
case "${ACTIVE_PHASE:-}" in
  plan) ;;
  *) exit 0 ;;
esac
[[ -n "$TASK_ID" ]] || exit 0

SENTINEL="$CWD/docs/handoff/${TASK_ID}/.workflow-called-${ACTIVE_PHASE}"
[[ -f "$SENTINEL" ]] && exit 0

case "$SUBTYPE" in
  architect)        WORKFLOW_NAME="leadv2-plan" ;;
  critic)           WORKFLOW_NAME="leadv2-review" ;;
  security-auditor) WORKFLOW_NAME="leadv2-review" ;;
  *)                WORKFLOW_NAME="the corresponding leadv2 Workflow" ;;
esac

python3 -c "
import sys, json
subtype=sys.argv[1]; phase=sys.argv[2]; wf=sys.argv[3]
msg=('workflow-bypass-guard DENY: spawning %s during phase=%s without calling the %s Workflow first. '
     'Call Workflow(name=%s) to fan-out; it touches the sentinel. To bypass: LEADV2_WORKFLOW_GUARD=0.' % (subtype,phase,wf,wf))
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':'deny','permissionDecisionReason':msg}}))
" -- "$SUBTYPE" "$ACTIVE_PHASE" "$WORKFLOW_NAME"
exit 0
