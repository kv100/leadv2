#!/usr/bin/env bash
# Fixture: fx-always-block — drives the guard into its fire path (case 1).
GV_FIX_GUARD="fx-always-block.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
GV_FIX_EXPECT="block"
