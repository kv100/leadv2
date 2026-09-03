#!/usr/bin/env bash
# tests/nc-ratelimit-history-kv-untouched.sh — NC2 (QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01)
#
# Proves assertion 4 (kv row stays byte-identical to the probe's own stdout)
# actually bites: applies a one-line mutation INSIDE _append_history()'s
# body -- the same call site that performs the per-account history
# side-write is made to also DELETE the kv row, so the write path no longer
# leaves kv untouched -- runs the whole suite against that mutated copy via
# LEADV2_RATELIMIT_PROBE_SH, and PASSES only when the suite reports FAIL > 0.
# Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL guard: if the target
# line ever changes shape, this script fails loudly instead of silently
# mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-ratelimit-probe.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-ratelimit-history-kv-untouched.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside _append_history()'s body, make the history side-write
# also clobber the kv row it must leave alone.
sed 's|^        _insert_row(conn, row)$|        _insert_row(conn, row); conn.execute("DELETE FROM kv")|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (_append_history's _insert_row(conn, row) call changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC2: running suite against mutated probe ($MUT) ---"
LEADV2_RATELIMIT_PROBE_SH="$MUT" bash "$SCRIPT_DIR/test-leadv2-ratelimit-probe.sh"
rc=$?
echo "--- NC2: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against a history writer that also clobbers kv, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a history writer that clobbers kv -- kv byte-identity is not actually asserted" >&2
exit 1
