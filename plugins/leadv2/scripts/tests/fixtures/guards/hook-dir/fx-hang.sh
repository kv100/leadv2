#!/usr/bin/env bash
# fx-hang — bails: hangs forever, dies to the census timeout, no verdict.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init PreToolUse
exec sleep 30
