#!/usr/bin/env bash
# tests/nc-claude-account-check.sh — NC2 (TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01)
#
# Proves T2 (the collapse fixture in test-claude-account-check.sh) actually
# bites: mutates verdict() in a scratch copy of
# leadv2-claude-account-check.sh so it reports TWO_BUCKETS unconditionally,
# runs the whole suite against that copy via LEADV2_TEST_ACCOUNT_CHECK_BIN,
# and PASSES only when the suite reports FAIL > 0. Same NC-SETUP-FAIL guard
# idiom as nc-claude-profile-select.sh / nc-claude-account-collapse.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-claude-account-check.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-claude-account-check.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside verdict()'s body, force the collapse-detection guard to
# never match -- every pair reads as unequal, so the function always falls
# through to the TWO_BUCKETS branch regardless of the real data.
sed 's|if \[\[ "\${ACCOUNTS\[\$_v_i\]}" != "-" \&\& "\${ACCOUNTS\[\$_v_i\]}" == "\${ACCOUNTS\[\$_v_j\]}" \]\]; then|if [[ "X${ACCOUNTS[$_v_i]}" == "Y${ACCOUNTS[$_v_j]}" ]]; then|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (verdict()'s collapse guard changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC2: running suite against mutated account-check ($MUT) ---"
LEADV2_TEST_ACCOUNT_CHECK_BIN="$MUT" bash "$SCRIPT_DIR/test-claude-account-check.sh"
rc=$?
echo "--- NC2: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the broken verdict(), as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a broken verdict() -- its assertions do not bite" >&2
exit 1
