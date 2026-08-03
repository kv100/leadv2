#!/usr/bin/env bash
set -euo pipefail
# proof-of: red-skill deliberate failure
source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"
assert_eq 1 2 "deliberate mismatch"
