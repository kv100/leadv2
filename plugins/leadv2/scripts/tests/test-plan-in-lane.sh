#!/usr/bin/env bash
# Mutation: replace _deliver_plan_into_lane exit 5 refusal with return 0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
grep -A20 '^_deliver_plan_into_lane()' "$ROOT/scripts/leadv2-dispatch-code.sh" | grep -q 'exit 5'
grep -A20 '^_deliver_plan_into_lane()' "$ROOT/scripts/leadv2-dispatch-code.sh" | grep -q 'cp -f'
echo 'PASS: lane plan refusal and copy-only branch present'
