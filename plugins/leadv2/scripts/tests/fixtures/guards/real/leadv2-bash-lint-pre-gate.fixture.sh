#!/usr/bin/env bash
# Real-guard fixture: leadv2-bash-lint-pre-gate.sh — hook mode (LEADV2_TASK_ID
# set) with a staged .sh that fails `bash -n` (lone `fi`); the guard emits
# permissionDecision:deny JSON (exit 0).
GV_FIX_GUARD="leadv2-bash-lint-pre-gate.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/proj"
cd "$LEADV2_SANDBOX/proj"
git init -q .
git config user.email fix@example.com
git config user.name fix
printf "%s\n" "#!/bin/sh" "fi" > bad.sh
git add bad.sh'
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"wip\""},"cwd":"$LEADV2_SANDBOX/proj"}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_ENV='LEADV2_TASK_ID=FIX-BL-1'
GV_FIX_EXPECT="block"
