#!/usr/bin/env bash
# tests/nc-quota-reset-unreadable-reset-zero.sh — NC2 (CLASSIFIER-MUST-SEE-
# QUOTA-AND-RESET-DATE-01 fix round 1)
#
# Proves test-quota-reset-arbiter.sh case (f)/(a)/(b) actually bite the claim
# "an unreadable reset can never fabricate an imminent wait": applies a
# one-line mutation INSIDE window_reset()'s body -- the unreadable-reset
# (missing hours_to_reset, known period) path is forced to report 0.0 hours
# to reset instead of the window's full period -- to a PRIVATE SCRATCH COPY
# of the arbiter (never the tracked file), runs the whole suite against that
# copy via the LEADV2_TEST_ARBITER_BIN injection seam, and PASSES only when
# the suite reports FAIL > 0. Mirrors nc-claude-account-collapse.sh's
# NC-SETUP-FAIL guard: if the target line no longer matches, this script
# fails loudly instead of silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/lib/leadv2-route-arbiter.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-route-arbiter-reset-zero.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside window_reset()'s body, the branch that fires when the
# window's own reset cannot be read (h is None, period IS known) is forced to
# fabricate hours_to_reset=0.0 instead of degrading to the window's full
# period -- a silent zero, exactly the failure mode the comment above this
# line says must never happen.
sed "s/return period, period, 'default_full_period'/return 0.0, period, 'default_full_period'/" \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (window_reset's default_full_period return changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC2: running suite against mutated arbiter ($MUT) ---"
LEADV2_TEST_ARBITER_BIN="$MUT" bash "$SCRIPT_DIR/test-quota-reset-arbiter.sh"
rc=$?
echo "--- NC2: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against an unreadable-reset path that fabricates 0.0, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a fabricated-zero reset -- its assertions do not bite" >&2
exit 1
