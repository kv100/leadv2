#!/usr/bin/env bash
# tests/test-quota-identity-report.sh — QUOTA-REPORT-PER-ACCOUNT-01 regression test
# (row f56ac3e63723).
#
# Guards the reporting-defect fix: leadv2-quota-status.sh must never print a single
# blended claude% figure and call it `safe` when two Anthropic accounts are live.
# 2026-09-12: it printed 43% "safe" while the account actually dispatching (work)
# was at 80% and the other (personal) was at 0% — 43% is neither account.
#
# Hermetic: LEADV2_QUOTA_STATUS_IDENTITY_LINE injects a profile-select-shaped line
# (the exact stdout contract of leadv2-claude-profile-select.sh / pick.py's
# `windows=` field) with NO subprocess, no registry, no network call at all.
#
# Assertions:
#   1. bash -n syntax
#   2. --report line 1 (what every `head -1` consumer sees) carries `identity=`
#      and the worst account's own status word (work=80% -> warn), never a
#      blended aggregate number carrying that word
#   3. --report also prints BOTH accounts' own lines (personal=0%, work=80%)
#   4. --report's aggregate line is explicitly labelled "aggregate (blended...)"
#      and does NOT end in a bare safe/warn/exhausted word
#   5. --json: top-level status/recommendation reflect the WORST identity (work,
#      warn), status_source names it, identities.list has both accounts,
#      identities.worst is work, aggregate.{status,recommendation} carries the
#      old aggregate-only value separately
#   6. --check does NOT refuse on a warn identity (only exhausted refuses).
#      Since row 3e55153ca645 identity data DOES reach --check (worst account
#      wins, both surfaces); the breaker itself is pinned by
#      test-check-decides-per-account.sh — this case only guards warn-parity.
#   7. per-account opt-out (LEADV2_QUOTA_STATUS_PER_ACCOUNT=0, the escape
#      hatch of the 3e55153ca645 default flip) -> byte-identical first line
#      to the pre-flip script (no regression for opt-out/single-account
#      callers)
#
# Run: bash scripts/tests/test-quota-identity-report.sh
# run-all-triggers: leadv2-quota-status

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_SH="${SCRIPT_DIR}/../leadv2-quota-status.sh"
# QUOTA-PROVIDER-SIGNAL-GOES-STALE-01: quota-status.sh now refreshes the
# rate_limit_anthropic kv row on read by default -- opt out here so this
# suite stays hermetic (no live probe/keychain/network call).
export LEADV2_QUOTA_REFRESH_ON_READ=0

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "quota-identity-report")"
DB="$TMP/test.db"
CFG="$TMP/ref.yaml"
trap 'rm -rf "$TMP"' EXIT

printf 'max_5h_input_tokens: 8000000\nmax_weekly_input_tokens: 100000000\nmin_cache_hit_rate: 0.30\n' > "$CFG"
sqlite3 "$DB" "
CREATE TABLE turn_events(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, ts TEXT,
  cc INTEGER DEFAULT 0, cr INTEGER DEFAULT 0, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0,
  model TEXT, tools_json TEXT);
CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX turn_events_ts ON turn_events(ts);
INSERT INTO turn_events(session_id,ts,input,cr,output,model) VALUES
  ('claude1', datetime('now','-1 hour'), 1000, 100000, 500, 'claude-opus-5');
"
export LEADV2_BURN_DB="$DB" LEADV2_MAIN_MODEL_CFG="$CFG"

# The exact stdout contract of leadv2-claude-profile-select.sh (windows= field),
# reproducing the founder's 2026-09-12 numbers: personal=0% (freer), work=80%
# (the one actually in use, and the one that must carry the safety word).
IDENTITY_LINE_2ACCT='profile=work config_dir=/x rank_by=usable_now_max consumed_pct=80 usable_now=0.224 source=live reason=binding_window candidates=2 cred=file:/x identity=work/na binding=seven_day:consumed_pct=80,usable_now=0.224 windows=personal:seven_day=0,usable_now=0.609|work:seven_day=80,usable_now=0.224'

# 1. syntax
if bash -n "$QUOTA_SH"; then pass "1 bash -n syntax"; else fail "1 bash -n syntax"; fi

rep="$(LEADV2_QUOTA_STATUS_IDENTITY_LINE="$IDENTITY_LINE_2ACCT" bash "$QUOTA_SH" --report)"
line1="$(printf '%s\n' "$rep" | head -1)"

# 2. line 1 carries identity= and the WORST account's status (work=80% -> warn),
#    never "safe".
if printf '%s' "$line1" | grep -qE 'identity=work seven_day=80% usable_now=0\.224 status=warn'; then
  pass "2 line1 carries identity=work status=warn (worst account, safety signal)"
else
  fail "2 line1 wrong: $line1"
fi
if printf '%s' "$line1" | grep -qE '\bstatus=safe\b'; then
  fail "2b line1 must not read safe when the worst account (work) is at 80%: $line1"
else
  pass "2b line1 does not carry a false 'safe'"
fi

# 3. both accounts' own lines present.
if printf '%s\n' "$rep" | grep -qE 'identity=personal seven_day=0% usable_now=0\.609 status=safe' \
   && printf '%s\n' "$rep" | grep -qE 'identity=work seven_day=80% usable_now=0\.224 status=warn'; then
  pass "3 both accounts reported (personal=0%/safe, work=80%/warn)"
else
  fail "3 missing a per-account line: $(printf '%s\n' "$rep" | grep identity=)"
fi

# 4. aggregate line explicitly labelled and carries no bare safety word.
agg_line="$(printf '%s\n' "$rep" | grep 'aggregate (blended' || true)"
if [[ -n "$agg_line" ]]; then
  pass "4a aggregate line is explicitly labelled 'aggregate (blended ...)'"
else
  fail "4a no aggregate line found: $rep"
fi
if printf '%s' "$agg_line" | grep -qE '\|[[:space:]]*(safe|warn|warn_60|weekly_warn|exhausted)[[:space:]]*$'; then
  fail "4b aggregate line still ends in a bare safety word: $agg_line"
else
  pass "4b aggregate line carries no trailing safe/warn/exhausted word"
fi

# 5. --json reflects the worst identity at top level, aggregate kept separately.
json="$(LEADV2_QUOTA_STATUS_IDENTITY_LINE="$IDENTITY_LINE_2ACCT" bash "$QUOTA_SH" --json)"
py_check="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ok = (
    d.get("status") == "warn"
    and d.get("recommendation") == "downgrade_to_sonnet"
    and d.get("status_source") == "identity:work"
    and d.get("identities", {}).get("count") == 2
    and d.get("identities", {}).get("worst", {}).get("label") == "work"
    and d.get("identities", {}).get("worst", {}).get("pct") == 80
    and any(i.get("label") == "personal" and i.get("pct") == 0 for i in d.get("identities", {}).get("list", []))
    and "aggregate" in d and "status" in d["aggregate"]
)
print("OK" if ok else "BAD: " + json.dumps(d.get("identities")) + " status=" + str(d.get("status")))
')"
if [[ "$py_check" == "OK" ]]; then
  pass "5 --json: top-level status=worst-identity(work/warn), identities+aggregate both present"
else
  fail "5 --json fields wrong: $py_check"
fi

# 6. --check: a warn identity (work=80%) must NOT refuse — only exhausted does.
set +e
LEADV2_QUOTA_STATUS_IDENTITY_LINE="$IDENTITY_LINE_2ACCT" bash "$QUOTA_SH" --check >/dev/null 2>&1; rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  pass "6 --check exit 0 (warn identity does not refuse — empty claude burn db, aggregate healthy)"
else
  fail "6 --check exit $rc — a warn identity must never refuse (only exhausted refuses)"
fi

# 7. opt-out -> byte-identical first line to the pre-flip behavior.
rep_off="$(LEADV2_QUOTA_STATUS_PER_ACCOUNT=0 bash "$QUOTA_SH" --report)"
line1_off="$(printf '%s\n' "$rep_off" | head -1)"
if printf '%s' "$line1_off" | grep -qE '^Quota: 5h [0-9]+% \([0-9]+ / [0-9]+ in, claude% only, cap est\.\) \| weekly\(claude, total-token, calibrated 2026-08-17\) [0-9]+% \(window=rolling_7d\) \| cache-hit [0-9.]+ \| safe$'; then
  pass "7 opt-out -> first line unchanged (single-account path is a byte-identical no-op)"
else
  fail "7 opt-out first line changed: $line1_off"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then printf '%s\n' "${ERRORS[@]}" >&2; exit 1; fi
log "ALL PASS — the safety word belongs to the worst account, never a blend of two."
exit 0
