#!/usr/bin/env bash
# fx-dispatched — reachable ONLY via fx-dispatcher.sh's MANIFEST, never a
# top-level hooks.json entry. Proves dispatcher-follow, not source grep.
set -uo pipefail
[ -n "${LEADV2_GUARD_VERDICT_LIB:-}" ] && . "$LEADV2_GUARD_VERDICT_LIB"
leadv2_gv_init PreToolUse
printf 'log: fx-dispatched observed\n'
leadv2_gv_verdict log
exit 0
