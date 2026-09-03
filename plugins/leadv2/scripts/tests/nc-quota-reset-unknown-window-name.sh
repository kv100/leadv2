#!/usr/bin/env bash
# tests/nc-quota-reset-unknown-window-name.sh — NC3 (CLASSIFIER-MUST-SEE-
# QUOTA-AND-RESET-DATE-01 fix round 1, item 1)
#
# Proves test-quota-reset-arbiter.sh case (g) actually bites the claim "an
# unknown window NAME must never borrow DEFAULT_PERIOD_HOURS": applies a
# one-line mutation INSIDE window_period_hours()'s body -- reintroduces the
# pre-fix fallback that assumed every unrecognized window name is a 168h
# weekly window -- to a PRIVATE SCRATCH COPY of the arbiter (never the
# tracked file), runs the whole suite against that copy via the
# LEADV2_TEST_ARBITER_BIN injection seam, and PASSES only when the suite
# reports FAIL > 0. Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL
# guard: if the target line no longer matches, this script fails loudly
# instead of silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/lib/leadv2-route-arbiter.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-route-arbiter-unknown-window.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside window_period_hours()'s body, the branch reached when the
# window NAME is not in WINDOW_PERIOD_HOURS is forced back to the pre-fix
# behaviour -- silently assume DEFAULT_PERIOD_HOURS=168h instead of reporting
# "I don't know this window's period" (None).
sed 's/return WINDOW_PERIOD_HOURS.get(name)$/return WINDOW_PERIOD_HOURS.get(name, 168.0)/' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (window_period_hours's unknown-name return changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC3: running suite against mutated arbiter ($MUT) ---"
LEADV2_TEST_ARBITER_BIN="$MUT" bash "$SCRIPT_DIR/test-quota-reset-arbiter.sh"
rc=$?
echo "--- NC3: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against an unknown window name that assumes a 168h period, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a reintroduced unknown-window-name fallback -- its assertions do not bite" >&2
exit 1
