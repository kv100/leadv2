#!/usr/bin/env bash
# ONE-PATH-EVERYWHERE-01 T5: the guard's REVIEW branch. A Bash tool_use event
# invoking leadv2-dispatch-product-close.sh with no review-gate.md present must
# produce permissionDecision=deny (LEADV2_REVIEW_ENGINE=1). At
# LEADV2_REVIEW_ENGINE=0 (default/prod) the same event must be a no-op (exit 0,
# empty stdout) — proving the review branch stays byte-equivalently inert.
# The plan/architect branch (hard scope fence) must be untouched: a plan-phase
# architect Agent spawn with no sentinel still denies under WORKFLOW_ENABLED=1,
# exactly as before. Uses LEADV2_TASK_ID/LEADV2_ACTIVE_PHASE env overrides
# (leadv2-mode-isolation.sh's documented explicit-override path) instead of a
# process-tree-matched active.yaml, so the test does not depend on faking `ps`
# ancestry.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_ROOT="$(cd "$SCRIPTS_ROOT/../hooks" && pwd)"
GUARD="$HOOKS_ROOT/leadv2-workflow-bypass-guard.sh"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-workflow-bypass-guard-lane.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "$GUARD" 2>/dev/null || { echo "ERROR: guard syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CWD="$TMP/repo"
mkdir -p "$CWD/docs/handoff/task00001"

EVENT="$TMP/event.json"
python3 -c "
import json
print(json.dumps({
  'tool_name': 'Bash',
  'cwd': '$CWD',
  'tool_input': {'command': 'bash plugins/leadv2/scripts/leadv2-dispatch-product-close.sh /root TASK0001 sonnet'}
}))
" > "$EVENT"

# Case A: LEADV2_REVIEW_ENGINE=1, no review-gate.md -> deny.
out_a="$(LEADV2_WORKFLOW_GUARD=1 LEADV2_REVIEW_ENGINE=1 LEADV2_WORKFLOW_ENABLED=0 \
  LEADV2_TASK_ID=task00001 LEADV2_ACTIVE_PHASE=review \
  bash "$GUARD" < "$EVENT" 2>/dev/null)"
if printf '%s' "$out_a" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  pass "REVIEW_ENGINE=1, no review-gate.md -> permissionDecision=deny"
else
  fail "REVIEW_ENGINE=1, no review-gate.md -> expected deny, got: $out_a"
fi

# Case B: same event, LEADV2_REVIEW_ENGINE=0 (default) -> inert (no output, i.e. no deny).
out_b="$(LEADV2_WORKFLOW_GUARD=1 LEADV2_REVIEW_ENGINE=0 LEADV2_WORKFLOW_ENABLED=0 \
  LEADV2_TASK_ID=task00001 LEADV2_ACTIVE_PHASE=review \
  bash "$GUARD" < "$EVENT" 2>/dev/null)"
if [[ -z "$out_b" ]]; then
  pass "REVIEW_ENGINE=0 (default) -> review branch inert, no deny emitted"
else
  fail "REVIEW_ENGINE=0 should be inert, got: $out_b"
fi

# Case C: review-gate.md present with a parseable status: line -> pass (no deny).
printf 'arms: codex,glm\nverified: 0/0\nstatus: pass\nreviewer: codex\ndiff: abc123\n' \
  > "$CWD/docs/handoff/task00001/review-gate.md"
out_c="$(LEADV2_WORKFLOW_GUARD=1 LEADV2_REVIEW_ENGINE=1 LEADV2_WORKFLOW_ENABLED=0 \
  LEADV2_TASK_ID=task00001 LEADV2_ACTIVE_PHASE=review \
  bash "$GUARD" < "$EVENT" 2>/dev/null)"
if [[ -z "$out_c" ]]; then
  pass "review-gate.md present with status: line -> no deny"
else
  fail "review-gate.md present should pass, got: $out_c"
fi

# Case D (regression guard, hard scope fence): plan/architect semantics untouched.
plan_event="$TMP/plan-event.json"
python3 -c "
import json
print(json.dumps({
  'tool_name': 'Agent',
  'cwd': '$CWD',
  'tool_input': {'subagent_type': 'architect'}
}))
" > "$plan_event"
out_d="$(LEADV2_WORKFLOW_GUARD=1 LEADV2_WORKFLOW_ENABLED=1 LEADV2_REVIEW_ENGINE=1 \
  LEADV2_TASK_ID=task00001 LEADV2_ACTIVE_PHASE=plan \
  bash "$GUARD" < "$plan_event" 2>/dev/null)"
if printf '%s' "$out_d" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  pass "plan-phase architect spawn (no sentinel) still denies — plan branch untouched"
else
  fail "plan branch regression: expected deny, got: $out_d"
fi

log ""
log "================================================"
log "  workflow-bypass-guard lane: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
