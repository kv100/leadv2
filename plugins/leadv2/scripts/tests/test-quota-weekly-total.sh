#!/usr/bin/env bash
# tests/test-quota-weekly-total.sh — QUOTA-GAUGE-WEEKLY-AXIS-STILL-LYING-01 regression test.
#
# Guards the load-bearing semantic change: window_weekly.pct counts TOTAL tokens
# (input+cc+cr+output, claude% only) against max_weekly_total_tokens. The old input-only
# figure always printed 0% because Anthropic input is ~0.007% of real weekly burn (cr
# dominates) — the exact "weekly 0% while the console says 40%" bug.
#
# Fixture: claude row with input=1000 and cr dominant, GLM row with 10M total (must be
# excluded from the claude weekly), cap overridden to 1,000,000 via the fixture yaml so the
# arithmetic is exact. Assertions:
#   1. bash -n syntax
#   2. window_weekly.total == 1,000,000 (in+cc+cr+out, claude% only — GLM excluded)
#   3. window_weekly.pct == 100 == total*100/cap (yaml max_weekly_total_tokens honored)
#   4. window_weekly.input_pct_legacy == 0 (the old heuristic still computes, still ~0)
#   5. window_basis == rolling_7d when kv carries no fresh weekly bucket (never fabricated)
#   6. --report line names the basis and the calibrated figure (visible, not silent)
#   7. cap=0 in yaml → pct 0, no division error (guard mirrors MAX_5H_IN)
#   8. fresh kv weekly resetsAt → window_basis == provider_reset and pre-window rows excluded
#   9. stale kv capture (> WK_RL_FRESH_SECS) → back to rolling_7d
#
# Portable: only sqlite3 + sh/sed builtins (no jq / GNU date). Exit 0 = pass.
# Run: bash scripts/tests/test-quota-weekly-total.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_SH="${SCRIPT_DIR}/../leadv2-quota-status.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "quota-weekly-total")"
DB="$TMP/test.db"
CFG="$TMP/ref.yaml"
trap 'rm -rf "$TMP"' EXIT

printf 'max_5h_input_tokens: 8000000\nmax_weekly_input_tokens: 100000000\nmax_weekly_total_tokens: 1000000\nmin_cache_hit_rate: 0.30\n' > "$CFG"

sqlite3 "$DB" "
CREATE TABLE turn_events(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, ts TEXT,
  cc INTEGER DEFAULT 0, cr INTEGER DEFAULT 0, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0,
  model TEXT, tools_json TEXT);
CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX turn_events_ts ON turn_events(ts);
INSERT INTO turn_events(session_id,ts,input,cc,cr,output,model) VALUES
  ('claude1', datetime('now','-1 hour'), 1000, 100000, 890000, 9000, 'claude-opus-5'),
  ('glm1',    datetime('now','-1 hour'), 5000000, 0, 5000000, 0, 'glm-5.2');
"
export LEADV2_BURN_DB="$DB" LEADV2_MAIN_MODEL_CFG="$CFG" LEADV2_QUOTA_LIVE=/nonexistent

# claude weekly total = 1000+100000+890000+9000 = 1,000,000 → pct = 100.
# If GLM leaked in, total would be 11,000,000 → pct = 1100.
jget() { printf '%s' "$1" | sed -n "s/.*$2.*/\1/p" | head -1; }

# 1. syntax
if bash -n "$QUOTA_SH"; then pass "1 bash -n syntax"; else fail "1 bash -n syntax"; fi

json="$(bash "$QUOTA_SH" --json)"
wk_total="$(jget "$json" '"window_weekly":{[^}]*"total":\([0-9]*\)')"
wk_pct="$(jget   "$json" '"window_weekly":{[^}]*"pct":\([0-9]*\)')"
wk_leg="$(jget   "$json" '"input_pct_legacy":\([0-9]*\)')"
wk_basis="$(jget "$json" '"window_basis":"\([a-z_0-9]*\)"')"
glm_wk_total="$(jget "$json" '"glm":{"w5h":{[^}]*},"weekly":{[^}]*"total":\([0-9]*\)')"

# 2. total = in+cc+cr+out, claude% only.
if [[ "$wk_total" == "1000000" ]]; then
  pass "2 window_weekly.total=$wk_total (total tokens, GLM 10M excluded)"
else
  fail "2 window_weekly.total='${wk_total:-<empty>}' expected 1000000 — GLM leaked in or a component dropped?"
fi

# 3. pct = total*100/cap with cap from max_weekly_total_tokens.
expect_pct=$(( 1000000 * 100 / 1000000 ))
if [[ "$wk_pct" == "$expect_pct" && "$wk_pct" != "0" ]]; then
  pass "3 window_weekly.pct=$wk_pct == total*100/cap (yaml max_weekly_total_tokens honored)"
else
  fail "3 window_weekly.pct='${wk_pct:-<empty>}' expected $expect_pct (cap override ignored → default 4.18B cap would give 0)"
fi

# 4. legacy input-only heuristic still present and still ~0 for cr-dominated burn.
if [[ "$wk_leg" == "0" ]]; then
  pass "4 input_pct_legacy=0 (old heuristic preserved, still blind to cr)"
else
  fail "4 input_pct_legacy='${wk_leg:-<empty>}' expected 0"
fi

# 5. no kv row → rolling basis, honestly reported.
if [[ "$wk_basis" == "rolling_7d" ]]; then
  pass "5 window_basis=rolling_7d with no kv weekly bucket (never fabricated)"
else
  fail "5 window_basis='${wk_basis:-<empty>}' expected rolling_7d"
fi

# 5b. GLM weekly total bucketed separately (rolling 7d, never the Anthropic reset window)
# and provenance honestly says yaml_override for a non-calibrated cap (review M1/L2).
wk_capbasis="$(jget "$json" '"window_weekly":{[^}]*"cap_basis":"\([a-z_]*\)"')"
if [[ "$glm_wk_total" == "10000000" ]]; then
  pass "5b providers.glm.weekly.total=$glm_wk_total (GLM bucketed separately)"
else
  fail "5b providers.glm.weekly.total='${glm_wk_total:-<empty>}' expected 10000000"
fi
if [[ "$wk_capbasis" == "yaml_override" ]]; then
  pass "5b cap_basis=yaml_override for a non-calibrated cap (never a false calibrated label)"
else
  fail "5b cap_basis='${wk_capbasis:-<empty>}' expected yaml_override (cap 1000000 != calibrated 4183721494)"
fi

# 6. --report names basis + the cap provenance on the line (yaml-override spelling here).
rep="$(bash "$QUOTA_SH" --report)"
if printf '%s\n' "$rep" | grep -qE 'weekly\(claude, total-token, cap yaml-override\) 100% \(window=rolling_7d\)'; then
  pass "6 report line names cap provenance + window basis"
else
  fail "6 report line wrong: $(printf '%s\n' "$rep" | head -1)"
fi

# 7. cap=0 guard: pct 0, clean exit (mirrors the MAX_5H_IN guard).
printf 'max_5h_input_tokens: 8000000\nmax_weekly_input_tokens: 100000000\nmax_weekly_total_tokens: 0\n' > "$CFG"
json0="$(bash "$QUOTA_SH" --json)"
wk_pct0="$(jget "$json0" '"window_weekly":{[^}]*"pct":\([0-9]*\)')"
if [[ "$wk_pct0" == "0" ]]; then
  pass "7 cap=0 → pct 0, no division error"
else
  fail "7 cap=0 → pct '${wk_pct0:-<empty>}' expected 0 (guard missing?)"
fi

# 8/9. provider_reset basis: fresh kv weekly resetsAt (now+3d, captured 60s ago) →
# window_start = resetsAt-7d = now-4d; a claude row at now-5d must fall OUTSIDE the window.
# Stale capture (26h old) → rolling_7d again (the now-5d row is back in).
sqlite3 "$DB" "INSERT INTO turn_events(session_id,ts,input,cc,cr,output,model) VALUES
  ('claude-old', datetime('now','-5 days'), 0, 0, 999999999, 0, 'claude-opus-5');"
printf 'max_5h_input_tokens: 8000000\nmax_weekly_input_tokens: 100000000\nmax_weekly_total_tokens: 1000000\n' > "$CFG"
RESET_ISO="$(sqlite3 "$DB" "SELECT strftime('%Y-%m-%dT%H:%M:%S+00:00','now','+3 days');")"
FRESH_EP="$(( $(date +%s) - 60 ))"
sqlite3 "$DB" "INSERT INTO kv(key,value) VALUES('rate_limit_anthropic',
  '{\"status\":\"ok\",\"overageStatus\":\"normal\",\"resetsAt\":\"$RESET_ISO\",\"captured_epoch\":$FRESH_EP,\"seven_day_pct\":50.0,\"seven_day_reset_iso\":\"$RESET_ISO\",\"binding_window\":\"seven_day\"}');"
json_pr="$(bash "$QUOTA_SH" --json)"
wk_basis_pr="$(jget "$json_pr" '"window_basis":"\([a-z_0-9]*\)"')"
wk_total_pr="$(jget "$json_pr" '"window_weekly":{[^}]*"total":\([0-9]*\)')"
if [[ "$wk_basis_pr" == "provider_reset" && "$wk_total_pr" == "1000000" ]]; then
  pass "8 fresh kv weekly resetsAt → basis=provider_reset, pre-window row excluded (total still 1000000)"
else
  fail "8 basis='${wk_basis_pr:-?}' total='${wk_total_pr:-?}' — expected provider_reset / 1000000 (pre-window row leaked?)"
fi

# 8b. A FRESH HEALTHY kv (status=ok/overage=normal, as the live ratelimit-probe writes them)
# must NOT trip the --check breaker — only an unhealthy provider signal may set exhausted.
set +e
bash "$QUOTA_SH" --check >/dev/null 2>&1; rc_pr=$?
set -e
if [[ $rc_pr -eq 0 ]]; then
  pass "8b fresh healthy kv (ok/normal) → --check exit 0 (weekly 100% warns but never exits 1)"
else
  fail "8b --check exit $rc_pr with a healthy fresh provider signal — status spelling mismatch falsely tripped the breaker"
fi

STALE_EP="$(( $(date +%s) - 93600 ))"  # 26h > WK_RL_FRESH_SECS (86400)
sqlite3 "$DB" "UPDATE kv SET value=replace(value,'\"captured_epoch\":$FRESH_EP','\"captured_epoch\":$STALE_EP') WHERE key='rate_limit_anthropic';"
json_st="$(bash "$QUOTA_SH" --json)"
wk_basis_st="$(jget "$json_st" '"window_basis":"\([a-z_0-9]*\)"')"
wk_total_st="$(jget "$json_st" '"window_weekly":{[^}]*"total":\([0-9]*\)')"
if [[ "$wk_basis_st" == "rolling_7d" && "$wk_total_st" == "1000999999" ]]; then
  pass "9 stale kv capture → rolling_7d, old row counted again (total 1000999999)"
else
  fail "9 basis='${wk_basis_st:-?}' total='${wk_total_st:-?}' — expected rolling_7d / 1000999999"
fi

# 10. malformed-but-fresh kv (fresh epoch, NO status field, review L1): the breaker falls
# back to the heuristic instead of tripping on an empty string — garbage must not lie RED.
FRESH_EP2="$(( $(date +%s) - 30 ))"
sqlite3 "$DB" "UPDATE kv SET value='{\"overageStatus\":\"normal\",\"resetsAt\":\"$RESET_ISO\",\"captured_epoch\":$FRESH_EP2,\"seven_day_reset_iso\":\"$RESET_ISO\",\"binding_window\":\"seven_day\"}' WHERE key='rate_limit_anthropic';"
set +e
bash "$QUOTA_SH" --check >/dev/null 2>&1; rc_mal=$?
set -e
if [[ $rc_mal -eq 0 ]]; then
  pass "10 malformed fresh kv (no status) → --check exit 0 (heuristic fallback, no lying-RED)"
else
  fail "10 --check exit $rc_mal on a statusless kv capture — empty RL_STATUS tripped the breaker"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then printf '%s\n' "${ERRORS[@]}" >&2; exit 1; fi
log "ALL PASS — weekly % counts total tokens against a calibrated cap, basis never fabricated."
exit 0
