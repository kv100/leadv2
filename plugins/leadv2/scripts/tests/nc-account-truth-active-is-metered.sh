#!/usr/bin/env bash
# tests/nc-account-truth-active-is-metered.sh — NC (ACCOUNT-TRUTH-ACTIVE-IS-NOT-THE-METERED-ONE-01)
#
# Proves the suite's ladder assertions actually bite: applies a one-line
# mutation INSIDE resolve_active_account()'s body — the config-dir rung's
# `if cfg_key:` guard is forced permanently false, so the CLAUDE_CONFIG_DIR
# derivation never runs and resolution falls straight through to the bare
# "Claude Code-credentials" service (the never-metered default that IS the
# lane's defect) — then runs the whole suite against that mutated copy via
# LEADV2_QUOTA_READ_PY and PASSES only when the suite reports FAIL > 0.
#
# The mutation is exactly the regression shape the mission named: a stored
# active flag on the bare account re-asserting itself because the rung that
# knows better was disabled. NC-SETUP-FAIL guard mirrors
# nc-ratelimit-history-append.sh: if the target line changes shape, this
# fails loudly instead of silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-quota-read.py"
MUT="$SCRIPTS_ROOT/.nc-mutated-account-truth.sh.py"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside resolve_active_account()'s body, disable the config-dir
# rung (acct-truth-mut-1). The ladder collapses to bare-service resolution.
sed 's|^        if cfg_key:$|        if cfg_key and False:|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (resolve_active_account's 'if cfg_key:' rung changed? update this NC)" >&2
  exit 2
fi

echo "--- NC: running suite against mutated quota-read ($MUT) ---"
LEADV2_QUOTA_READ_PY="$MUT" bash "$SCRIPT_DIR/test-account-truth-active-is-metered.sh"
rc=$?
echo "--- NC: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red with the config-dir rung disabled — the ladder assertions bite" >&2
  exit 0
fi
echo "NC-FAIL: suite stayed green with the config-dir rung disabled — resolution is unguarded" >&2
exit 1
