#!/usr/bin/env bash
# Mutation: delete the landed-to-pass_unlanded branch in dispatch_ledger_write_terminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
grep -q 'terminal="pass_unlanded"' "$ROOT/scripts/leadv2-dispatch-ledger.sh"
grep -q 'dirty_lane_retry_exhausted' "$ROOT/scripts/leadv2-dispatch-ledger.sh"
echo 'PASS: dirty landed terminal downgrade and bounded retry branch present'
