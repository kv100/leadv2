#!/usr/bin/env bash
# Real-guard fixture: leadv2-codex-nopoll-guard.sh — a second
# `codex-task.sh status` within 5 tool calls: the seeded counter file
# (LEADV2_TASK_STATE_DIR) records a poll at tool-call 10, none since, so the
# guard emits permissionDecision:deny JSON (exit 0). Sandboxed HOME keeps the
# tool-count lookup away from the real ~/.claude state.
GV_FIX_GUARD="leadv2-codex-nopoll-guard.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/state" "$LEADV2_SANDBOX/home/.claude/state/leadv2" "$LEADV2_SANDBOX/proj/docs/leadv2"
printf "%s" "10" > "$LEADV2_SANDBOX/state/codex-nopoll-counter"
printf "%s\n" "t" "t" "t" "t" "t" "t" "t" "t" "t" "t" "t" "t" > "$LEADV2_SANDBOX/home/.claude/state/leadv2/FIX-NP-1.tool-count"
printf "%s\n" "sessions:" "  - task_id: FIX-NP-1" > "$LEADV2_SANDBOX/proj/docs/leadv2/active.yaml"'
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"codex-task.sh status FIX-NP-1"},"cwd":"$LEADV2_SANDBOX/proj"}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_HOME='$LEADV2_SANDBOX/home'
GV_FIX_ENV='LEADV2_TASK_STATE_DIR=$LEADV2_SANDBOX/state'
GV_FIX_EXPECT="block"
