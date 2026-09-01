#!/usr/bin/env bash
# Fixture: fx-disabled — case 2. The census derives "disabled" behaviourally:
# default env => no block, GV_FIX_ARM_ENV armed => block. If arming does NOT
# produce a block this is a regression, not a disabled guard.
GV_FIX_GUARD="fx-disabled.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
GV_FIX_EXPECT="disabled"
GV_FIX_ARM_ENV="LEADV2_FX_GUARD=1"
