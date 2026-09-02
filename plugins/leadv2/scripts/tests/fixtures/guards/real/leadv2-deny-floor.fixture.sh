#!/usr/bin/env bash
# Real-guard fixture: leadv2-deny-floor.sh (PreToolUse:Bash, ALWAYS-wired via
# the dispatcher). Drives the enabled rm_rf_root rule; observed exit 2.
GV_FIX_GUARD="leadv2-deny-floor.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
GV_FIX_EXPECT="block"
