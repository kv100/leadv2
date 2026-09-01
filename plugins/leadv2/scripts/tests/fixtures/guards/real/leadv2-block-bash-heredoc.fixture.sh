#!/usr/bin/env bash
# Real-guard fixture: leadv2-block-bash-heredoc.sh (PreToolUse:Bash).
# Probe artifact 2026-09-01: 2122-byte heredoc command -> exit 2 with the
# "Heredocs in Bash live in the transcript forever" stderr.
GV_FIX_GUARD="leadv2-block-bash-heredoc.sh"
_LV2FX_BIG="$(printf 'x%.0s' $(seq 1 2100))"
GV_FIX_STDIN="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat <<EOF\\\\n${_LV2FX_BIG}\\\\necho done\"}}"
GV_FIX_EXPECT="block"
