#!/usr/bin/env bash
# tests/nc-claude-profile-select.sh — H1 negative control (fix-round 2026-08-27)
#
# Proves the suite can actually go red: applies a one-line mutation to a
# scratch copy of the selector (breaks the identity-derivation email line so
# the derived identity loses its .claude.json email half), runs the whole
# suite against that copy via LEADV2_TEST_SELECT_BIN, and PASSES only when
# the suite reports FAIL > 0.  A suite that stays green against a broken
# selector is a suite that proves nothing.
#
# The scratch copy lives in the same scripts/ dir (leading-dot name) so its
# SCRIPT_DIR-based pick-helper resolution still works; it is removed on exit
# and never committed.  No network, no keychain — the suite itself is
# hermetic.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-claude-profile-select.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-leadv2-claude-profile-select.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: drop the .claude.json (oauthAccount.emailAddress) source from the
# identity email derivation — the exact line the T12 identity contract stands
# on.  Every test that asserts a real email in identity= (T14 same_account,
# T15 label_mismatch, T17 default_token_expired) must go red.
sed 's|email = oa.get("emailAddress") or co.get("email") or co.get("emailAddress") or "na"|email = co.get("email") or co.get("emailAddress") or "na"|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (selector's identity-derivation line changed? update this NC)" >&2
  exit 2
fi

echo "--- NC: running suite against mutated selector ($MUT) ---"
LEADV2_TEST_SELECT_BIN="$MUT" bash "$SCRIPT_DIR/test-claude-profile-select.sh"
rc=$?
echo "--- NC: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the broken selector, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a broken selector — its assertions do not bite" >&2
exit 1
