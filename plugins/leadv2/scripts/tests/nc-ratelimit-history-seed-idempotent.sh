#!/usr/bin/env bash
# tests/nc-ratelimit-history-seed-idempotent.sh — NC3 (QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01)
#
# Proves assertion 12b (a second probe does NOT re-seed from kv) actually
# bites: applies a one-line mutation INSIDE _seed_from_kv()'s body -- the
# "only while rate_limit_history is empty" guard is forced to never trigger
# its early return, so the pre-existing kv row is re-seeded on every single
# probe instead of once -- runs the whole suite against that mutated copy
# via LEADV2_RATELIMIT_PROBE_SH, and PASSES only when the suite reports
# FAIL > 0. Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL guard: if
# the target line ever changes shape, this script fails loudly instead of
# silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="$SCRIPTS_ROOT/leadv2-ratelimit-probe.sh"
MUT="$SCRIPTS_ROOT/.nc-mutated-ratelimit-history-seed-idempotent.sh"
trap 'rm -f "$MUT"' EXIT

# Mutation: inside _seed_from_kv()'s body, force the "history already has
# rows" early-return guard to never trigger -- the function proceeds to
# re-seed from kv on every probe, not just while the table is empty.
sed 's|^    if conn.execute("SELECT 1 FROM rate_limit_history LIMIT 1").fetchone() is not None:$|    if conn.execute("SELECT 1 FROM rate_limit_history LIMIT 1").fetchone() is not None and False:|' \
  "$SRC" > "$MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$MUT"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (_seed_from_kv's empty-table guard changed? update this NC)" >&2
  exit 2
fi
chmod +x "$MUT"

echo "--- NC3: running suite against mutated probe ($MUT) ---"
LEADV2_RATELIMIT_PROBE_SH="$MUT" bash "$SCRIPT_DIR/test-leadv2-ratelimit-probe.sh"
rc=$?
echo "--- NC3: suite exit=$rc ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against a seed that re-fires on every probe, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green against a non-idempotent seed -- the idempotence claim does not bite" >&2
exit 1
