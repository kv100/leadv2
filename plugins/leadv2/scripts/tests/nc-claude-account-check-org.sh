#!/usr/bin/env bash
# tests/nc-claude-account-check-org.sh — NC3 (TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01, fix round 1)
#
# Proves T6 (the ORG_COLLAPSE fixture in test-claude-account-check.sh) actually
# bites: mutates the ORG-level pairwise comparison inside verdict() -- NOT the
# accountUuid comparison NC2 already targets -- in a scratch copy of
# leadv2-claude-account-check.sh, so the org check never matches regardless of
# input. Runs the whole suite against that mutated copy via
# LEADV2_TEST_ACCOUNT_CHECK_BIN, and PASSES only when the suite reports
# FAIL > 0. Same NC-SETUP-FAIL guard idiom as nc-claude-account-check.sh /
# nc-claude-profile-select.sh / nc-claude-account-collapse.sh: if the target
# line ever changes shape, this script fails loudly instead of silently
# mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-claude-account-check.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-claude-account-check-org.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside verdict()'s SECOND (org) pairwise loop, force the
# collapse-detection guard to never match -- every pair of organizationUuids
# reads as unequal, so the org branch always falls through to TWO_BUCKETS
# regardless of the real data. The accountUuid comparison above it (NC2's
# target) is left untouched.
sed 's|if \[\[ "\${ORGS\[\$_v_i\]}" != "-" \&\& "\${ORGS\[\$_v_i\]}" == "\${ORGS\[\$_v_j\]}" \]\]; then|if [[ "X${ORGS[$_v_i]}" == "Y${ORGS[$_v_j]}" ]]; then|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (verdict()'s org guard changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC3: running suite against mutated account-check ($MUT) ---"
LEADV2_TEST_ACCOUNT_CHECK_BIN="$MUT" bash "$SCRIPT_DIR/test-claude-account-check.sh"
rc=$?
echo "--- NC3: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the neutralised org comparison, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a neutralised org comparison -- its assertions do not bite" >&2
exit 1
