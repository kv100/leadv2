#!/usr/bin/env bash
# fx-degrade-wrapped — wired via the degrade-log wrapper pattern used by
# 32 real hooks.json entries (probe: grep -o "\"; r=\$?" hooks.json | wc -l = 32 of 172 commands).
# Locks the jq-parser fix: this file EXISTS, so it must never show "missing".
set -uo pipefail
exit 0
