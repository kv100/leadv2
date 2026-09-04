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
MUT2="$SCRIPTS_ROOT/.nc2-mutated-leadv2-claude-profile-select.sh"
trap 'rm -f "$MUT" "$MUT2"' EXIT

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
nc1_ok=1
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the broken selector, as required"
else
  echo "NC-FAIL: suite stayed green against a broken selector — its assertions do not bite" >&2
  nc1_ok=0
fi

# NC2 (CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01, D6): reintroduce the pre-fix
# (buggy) refreshability predicate INSIDE credential_health()'s own function
# body -- judge liveness by the access-token `expiresAt` instead of the
# refresh window `refreshTokenExpiresAt`. D6 requires this mutation land
# inside the function, never at file top level, so the negative control
# actually exercises the corrected logic path rather than failing for an
# unrelated (e.g. syntax) reason.
python3 - "$SRC" "$MUT2" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
old = '  if [[ "$rexp" =~ ^[0-9]+(\\.[0-9]+)?$ ]] && (( ${rexp%%.*} <= now_ms )); then return 1; fi\n'
new = '  if [[ "$exp" =~ ^[0-9]+(\\.[0-9]+)?$ ]] && (( ${exp%%.*} <= now_ms )); then return 1; fi\n'
text = open(src).read()
if old not in text:
    sys.stderr.write("NC2-SETUP-FAIL: mutation pattern not found (credential_health's refresh-check line changed? update this NC)\n")
    sys.exit(2)
open(dst, "w").write(text.replace(old, new, 1))
PY
setup_rc=$?
if (( setup_rc != 0 )); then
  echo "NC2-SETUP-FAIL: could not build mutated copy" >&2
  exit 2
fi
if cmp -s "$SRC" "$MUT2"; then
  echo "NC2-SETUP-FAIL: mutated copy identical to source (mutation did not apply)" >&2
  exit 2
fi

echo "--- NC2: running suite against mutated selector ($MUT2) ---"
LEADV2_TEST_SELECT_BIN="$MUT2" bash "$SCRIPT_DIR/test-claude-profile-select.sh"
rc2=$?
echo "--- NC2: suite exit=$rc2 ---"
nc2_ok=1
if (( rc2 != 0 )); then
  echo "NC-PASS: suite went red against the credential_health() expiresAt-regression mutation, as required"
else
  echo "NC-FAIL: suite stayed green against the credential_health() expiresAt-regression mutation — its assertions do not bite" >&2
  nc2_ok=0
fi

if (( nc1_ok == 1 && nc2_ok == 1 )); then
  exit 0
fi
exit 1
