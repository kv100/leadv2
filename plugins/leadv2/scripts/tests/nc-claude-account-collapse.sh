#!/usr/bin/env bash
# tests/nc-claude-account-collapse.sh — NC1 (TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01)
#
# Proves T14/T21 (same-account detection + refusal) actually bite: applies a
# one-line mutation INSIDE detect_same_account()'s body -- the account
# comparison is forced to always-unequal, so no same_account WARN, no alarm
# file, and no `profile=- reason=same_account` refusal ever fires -- runs the
# whole suite against that mutated copy via LEADV2_TEST_SELECT_BIN, and
# PASSES only when the suite reports FAIL > 0. Mirrors
# nc-claude-profile-select.sh's NC-SETUP-FAIL guard: if the target line ever
# changes shape, this script fails loudly instead of silently mutating
# nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-claude-profile-select.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-claude-account-collapse.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside detect_same_account()'s body, force the guard that fires
# a same_account WARN/refusal to always be false -- the account comparison
# becomes unconditionally unequal (both the accountUuid branch and the
# sub/email fallback are gated behind this one `if (( same ))`).
sed 's|if (( same )); then|if (( same )) \&\& [[ "X" == "Y" ]]; then|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (detect_same_account's guard changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC1: running suite against mutated selector ($MUT) ---"
LEADV2_TEST_SELECT_BIN="$MUT" bash "$SCRIPT_DIR/test-claude-profile-select.sh"
rc=$?
echo "--- NC1: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the broken same-account detector, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a broken same-account detector -- its assertions do not bite" >&2
exit 1
