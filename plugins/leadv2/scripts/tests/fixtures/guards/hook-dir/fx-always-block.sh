#!/usr/bin/env bash
# fx-always-block — synthetic PreToolUse guard whose fire path always blocks.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init PreToolUse
printf '{"decision":"block","reason":"fx-always-block fires on every event"}\n'
leadv2_gv_verdict block
exit 0
