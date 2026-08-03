#!/usr/bin/env bash
set -euo pipefail
# proof-of: green-skill trivial pass
source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"
assert_eq 1 1 "trivial equality holds"
