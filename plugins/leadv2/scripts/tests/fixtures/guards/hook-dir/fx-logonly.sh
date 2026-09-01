#!/usr/bin/env bash
# fx-logonly — the promise-guard shape: reaches its fire path, complains, never blocks.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init Stop
echo "[fx-logonly] would have blocked: turn ended on an unmet obligation" >&2
leadv2_gv_verdict log
exit 0
