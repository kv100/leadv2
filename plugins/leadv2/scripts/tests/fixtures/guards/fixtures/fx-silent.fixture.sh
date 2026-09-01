#!/usr/bin/env bash
# Fixture: fx-silent — executes cleanly, never reaches a would-block decision.
GV_FIX_GUARD="fx-silent.sh"
GV_FIX_STDIN='{"session_id":"fx","stop_hook_active":false}'
GV_FIX_EXPECT="nap"
