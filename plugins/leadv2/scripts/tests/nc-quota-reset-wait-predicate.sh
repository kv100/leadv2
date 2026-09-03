#!/usr/bin/env bash
# tests/nc-quota-reset-wait-predicate.sh — NC1 (CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01
# fix round 1)
#
# Proves test-quota-reset-arbiter.sh case (a) actually bites: applies a
# one-line mutation INSIDE near_reset_wait()'s body -- the wait predicate is
# forced to always return False -- to a PRIVATE SCRATCH COPY of the arbiter
# (never the tracked file), runs the whole suite against that copy via the
# LEADV2_TEST_ARBITER_BIN injection seam, and PASSES only when the suite
# reports FAIL > 0. Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL
# guard: if the target line no longer matches, this script fails loudly
# instead of silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/lib/leadv2-route-arbiter.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-route-arbiter-wait-predicate.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside near_reset_wait()'s body, force the threshold comparison
# that decides "wait" to always evaluate to False -- the function can never
# report near-reset again, regardless of how close hours_to_reset is.
sed 's/return h <= (period \* WAIT_FRACTION_OF_PERIOD)/return False/' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (near_reset_wait's return changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC1: running suite against mutated arbiter ($MUT) ---"
LEADV2_TEST_ARBITER_BIN="$MUT" bash "$SCRIPT_DIR/test-quota-reset-arbiter.sh"
rc=$?
echo "--- NC1: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against a wait predicate that can never fire, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a broken wait predicate -- its assertions do not bite" >&2
exit 1
