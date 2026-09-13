#!/usr/bin/env bash
# tests/nc-quota-telemetry-can-price-an-arm.sh — NC (QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01)
#
# Two mutations, each applied INSIDE the production function body on a
# scratch copy, each followed by a full suite run through the suite's own
# env injection point. The NC passes only when EVERY mutation turns the
# suite red:
#
#   M1 (attribution): leadv2-turn-account-attribute.py's key derivation
#       `key_by_session[sid] = account_key_for_config_dir(path[:cut])` is
#       replaced by a constant key — rows get written with a WRONG account.
#       Kills: assertion 2 (COUNT(account_key=<derived>) on WRITTEN rows).
#
#   M2 (token totals): lib/leadv2-cost-actuals.sh leadv2_lane_token_total's
#       final `printf -- '%s' "${total:--}"` prints a constant '-' — the
#       join exists but always claims unknown, which is the exact 100%-dash
#       live shape the lane was dispatched to fix.
#       Kills: assertions 7a/7b (real counts 1800/1500 must be stamped).
#
# NC-SETUP-FAIL guards mirror nc-ratelimit-history-append.sh: a target line
# that no longer matches fails this script loudly instead of mutating
# nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUITE="$SCRIPT_DIR/test-quota-telemetry-can-price-an-arm.sh"
ATTR_SRC="$SCRIPTS_ROOT/leadv2-turn-account-attribute.py"
COST_SRC="$SCRIPTS_ROOT/lib/leadv2-cost-actuals.sh"
ATTR_MUT="$SCRIPTS_ROOT/.nc-mutated-attr.py"
COST_MUT="$SCRIPTS_ROOT/.nc-mutated-cost.sh"
trap 'rm -f "$ATTR_MUT" "$COST_MUT"' EXIT

RED=0

echo "--- NC M1: attributor derives a constant key ---"
sed 's|key_by_session\[sid\] = account_key_for_config_dir(path\[:cut\])|key_by_session[sid] = "deadbeef"|' \
  "$ATTR_SRC" > "$ATTR_MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$ATTR_SRC" "$ATTR_MUT"; then
  echo "NC-SETUP-FAIL: M1 pattern not found (attributor's derivation line changed? update this NC)" >&2
  exit 2
fi
LEADV2_TURN_ACCOUNT_ATTRIBUTE_PY="$ATTR_MUT" bash "$SUITE"
rc1=$?
echo "--- NC M1: suite exit=$rc1 ---"
if (( rc1 != 0 )); then RED=$((RED+1)); else
  echo "NC-FAIL(M1): suite stayed green against a constant-key attributor" >&2
fi

echo "--- NC M2: lane token total always prints '-' ---"
sed 's|\${total:--}|-|' "$COST_SRC" > "$COST_MUT" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$COST_SRC" "$COST_MUT"; then
  echo "NC-SETUP-FAIL: M2 pattern not found (lane_token_total's final printf changed? update this NC)" >&2
  exit 2
fi
# Pin the event bin to the REAL emitter: the mutant copy lives one directory
# up from lib/, so the lib's own relative default (../leadv2-event.sh) would
# resolve to a missing path and silently skip the record path — a false red
# that has nothing to do with the mutation under test.
LEADV2_COST_ACTUALS_SH="$COST_MUT" \
LEADV2_COST_ACTUAL_EVENT_BIN="$SCRIPTS_ROOT/leadv2-event.sh" bash "$SUITE"
rc2=$?
echo "--- NC M2: suite exit=$rc2 ---"
if (( rc2 != 0 )); then RED=$((RED+1)); else
  echo "NC-FAIL(M2): suite stayed green against an always-dash token total" >&2
fi

if (( RED == 2 )); then
  echo "NC-PASS: every mutation turned the suite red — attribution and token-total assertions bite" >&2
  exit 0
fi
echo "NC-FAIL: only $RED/2 mutations were caught" >&2
exit 1
