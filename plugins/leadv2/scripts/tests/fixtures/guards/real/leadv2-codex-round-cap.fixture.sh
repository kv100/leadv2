#!/usr/bin/env bash
# Real-guard fixture: leadv2-codex-round-cap.sh — task CAP-1 already has two
# codex_round_* keys in docs/handoff/CAP-1/context.yaml, so the round gate
# exits 1 and the guard emits permissionDecision:deny JSON (exit 0).
GV_FIX_GUARD="leadv2-codex-round-cap.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/proj/docs/handoff/CAP-1"
printf "%s\n" "reviews:" "  codex_round_1: {}" "  codex_round_2: {}" > "$LEADV2_SANDBOX/proj/docs/handoff/CAP-1/context.yaml"'
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"codex-task.sh adversarial-review fix-round-3"}}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_ENV='LEADV2_TASK_ID=CAP-1'
GV_FIX_EXPECT="block"
