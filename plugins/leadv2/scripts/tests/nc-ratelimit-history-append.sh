#!/usr/bin/env bash
# tests/nc-ratelimit-history-append.sh — NC1 (QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01)
#
# Proves assertion 2 (row count = 2, one per account after a probe) actually
# bites: applies a one-line mutation INSIDE _append_history()'s body -- the
# `if should:` guard that gates the INSERT is forced permanently false, so
# _insert_row() is never called and every probe is a silent no-op against
# rate_limit_history -- runs the whole suite against that mutated copy via
# LEADV2_RATELIMIT_PROBE_SH, and PASSES only when the suite reports FAIL > 0.
# Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL guard: if the target
# line ever changes shape, this script fails loudly instead of silently
# mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-ratelimit-probe.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-ratelimit-history-append.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside _append_history()'s body, force the `if should:` guard
# that gates _insert_row() to always be false -- the INSERT becomes a no-op
# on every probe, regardless of what _should_append() decided.
sed 's|^    if should:$|    if should and False:|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (_append_history's 'if should:' guard changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC1: running suite against mutated probe ($MUT) ---"
LEADV2_RATELIMIT_PROBE_SH="$MUT" bash "$SCRIPT_DIR/test-leadv2-ratelimit-probe.sh"
rc=$?
echo "--- NC1: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against a history writer whose INSERT is a no-op, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a no-op history INSERT -- its assertions do not bite" >&2
exit 1
