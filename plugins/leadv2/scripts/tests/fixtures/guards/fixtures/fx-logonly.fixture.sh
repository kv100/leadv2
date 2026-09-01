#!/usr/bin/env bash
# Fixture: fx-logonly — the promise-guard shape (case 3): reaches the fire
# path, emits, never blocks.
GV_FIX_GUARD="fx-logonly.sh"
GV_FIX_STDIN='{"session_id":"fx","stop_hook_active":false}'
GV_FIX_EXPECT="log"
