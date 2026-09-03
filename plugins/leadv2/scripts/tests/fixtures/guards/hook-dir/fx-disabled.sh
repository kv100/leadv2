#!/usr/bin/env bash
# fx-disabled — OFF by default; LEADV2_FX_GUARD=1 arms its fire path.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init PreToolUse
if [ "${LEADV2_FX_GUARD:-0}" = "1" ]; then
  printf '{"decision":"block","reason":"fx-disabled armed"}\n'
  leadv2_gv_verdict block
else
  leadv2_gv_verdict nap "flag-off"
fi
exit 0
