#!/usr/bin/env bash
# Fixture: fx-hang — case 6. The guard bails on the census timeout; the bail
# must be recorded with its reason, never silently absent.
GV_FIX_GUARD="fx-hang.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
GV_FIX_EXPECT="bail-timeout"
