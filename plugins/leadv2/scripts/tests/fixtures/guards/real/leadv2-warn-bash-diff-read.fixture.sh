#!/usr/bin/env bash
# Real-guard fixture: leadv2-warn-bash-diff-read.sh — advisory
# additionalContext JSON by default; with LEADV2_DIFF_READ_DENY=1 the same
# unsummarized `git diff` read upgrades to the exit-2 block (its hard path).
GV_FIX_GUARD="leadv2-warn-bash-diff-read.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"git diff HEAD"}}'
GV_FIX_ENV='LEADV2_DIFF_READ_DENY=1'
GV_FIX_EXPECT="block"
