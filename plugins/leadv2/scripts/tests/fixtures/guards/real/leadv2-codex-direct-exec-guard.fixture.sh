#!/usr/bin/env bash
# Real-guard fixture: leadv2-codex-direct-exec-guard.sh — bare `codex exec`
# bypasses the router's quota gate; observed exit 2 ("BLOCKED direct 'codex exec'").
GV_FIX_GUARD="leadv2-codex-direct-exec-guard.sh"
GV_FIX_STDIN='{"tool_name":"Bash","tool_input":{"command":"codex exec \"explore the tree\""}}'
GV_FIX_EXPECT="block"
