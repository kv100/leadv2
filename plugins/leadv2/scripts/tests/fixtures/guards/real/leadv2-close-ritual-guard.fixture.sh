#!/usr/bin/env bash
# Real-guard fixture: leadv2-close-ritual-guard.sh — a close-style commit with
# NEITHER docs/leadv2/closed/<id>.yaml NOR docs/handoff/<id>/phase8-passed.flag
# in the sandbox project; the guard emits permissionDecision:deny JSON (exit 0).
GV_FIX_GUARD="leadv2-close-ritual-guard.sh"
GV_FIX_PRE='mkdir -p "$LEADV2_SANDBOX/proj"'
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: close CLOSE-IT-1\""},"cwd":"$LEADV2_SANDBOX/proj"}'
GV_FIX_CWD='$LEADV2_SANDBOX/proj'
GV_FIX_EXPECT="block"
