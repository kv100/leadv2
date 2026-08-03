#!/usr/bin/env bash
set -euo pipefail
# proof-of: trivially valid proof that fails at runtime
source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"
assert_eq 1 2 "deliberate mismatch"
