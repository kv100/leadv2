#!/usr/bin/env bash
# Fixture guard wired through ${CLAUDE_PLUGIN_ROOT}/scripts/ — the shape
# hooks.json uses for leadv2-hook-fork-guard.sh and leadv2-lane-watch-v2.sh
# (GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01). It exists ONLY here,
# never in hook-dir/, so a hooks/-only existence check calls it `missing`
# even though its wiring resolves and its gate knob is readable.
gate="${LEADV2_FX_SCRIPTSDIR:-0}"
[ "$gate" = "1" ] && exit 2
exit 0
