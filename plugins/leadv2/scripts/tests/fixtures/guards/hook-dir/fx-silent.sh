#!/usr/bin/env bash
# fx-silent — executes, decides allow, never emits.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init Stop
leadv2_gv_verdict allow
exit 0
