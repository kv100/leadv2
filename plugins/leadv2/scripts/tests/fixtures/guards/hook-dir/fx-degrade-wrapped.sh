#!/usr/bin/env bash
# fx-degrade-wrapped — wired via the degrade-log wrapper pattern used by
# ~34 real hooks.json entries ("cmd"; r=$?; if...; printf ... degrade-log).
# Locks the jq-parser fix: this file EXISTS, so it must never show "missing".
set -uo pipefail
exit 0
