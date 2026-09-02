#!/usr/bin/env bash
# Real-guard fixture: leadv2-block-fg-dispatch.sh — a foreground
# leadv2-dispatch-code.sh launch is the exact 2-minute-timeout kill the guard
# exists for; observed exit 2 (stderr "Override: set LEADV2_ALLOW_FG_DISPATCH=1").
GV_FIX_GUARD="leadv2-block-fg-dispatch.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"leadv2-dispatch-code.sh --task FIX-1"}}'
GV_FIX_EXPECT="block"
