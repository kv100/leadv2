#!/usr/bin/env bash
# Real-guard fixture: leadv2-lead-edit-guard.sh (PreToolUse:Edit|Write).
# Derives "disabled" behaviourally (probe 2026-09-01):
#   flag off  -> exit 0, no block
#   LEADV2_LEAD_GUARD_FORCE=1 -> exit 2, "Lead editing code/config files
#   directly is forbidden during /leadv2."
# The census runs under env -i, so the operator's own LEADV2_LEAD_GUARD=1
# cannot leak in and fake a blocking default.
GV_FIX_GUARD="leadv2-lead-edit-guard.sh"
GV_FIX_STDIN='{"tool_name":"Edit","tool_input":{"file_path":"/fixture/src/module.py","old_string":"a","new_string":"b"}}'
GV_FIX_EXPECT="disabled"
GV_FIX_ARM_ENV="LEADV2_LEAD_GUARD_FORCE=1"
