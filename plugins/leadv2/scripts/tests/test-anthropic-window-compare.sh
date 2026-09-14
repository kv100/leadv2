#!/usr/bin/env bash
# run-all-triggers: leadv2-anthropic-window-compare leadv2-anthropic-window-compare.py leadv2-drain-weights leadv2-drain-weights.py
#
# tests/test-anthropic-window-compare.sh — ANTHROPIC-PRICE-OR-A-REASON-WE-CANNOT-HAVE-ONE-01
#
# Guards leadv2-anthropic-window-compare.py, the tool that answers mission
# item 3 (does Δpct/token depend on which of Anthropic's two nested meters --
# 5h, 7d -- is read, or on time-to-reset) and the zero-token half of item 4
# (does the pooled percentage move with NO tokens attributed to this account
# at all -- the shared-account confound). This is a comparison tool: it never
# fits or prints a price, only rates and ratios, on a synthetic fixture db so
# the suite is hermetic and independent of ~/.claude/burn/history.db.
#
# Fixture: 6 rate_limit_history snapshots -> 5 intervals, by name:
#   (A) 1->2: tokened, no 5h reset, both deltas >=0 -> the one CLEAN interval.
#   (B) 2->3: tokened, but five_hour_reset_epoch changes mid-interval -> the
#       5h window rolled, so this interval must NOT enter the clean set even
#       though it has tokens (mirrors leadv2-drain-weights.py's dropped_reset,
#       applied to the 5h column specifically).
#   (C) 3->4: zero tokens, zero delta on both columns -> true idle, must not
#       appear in either the clean set or the unattributed-drain count.
#   (D) 4->5: zero tokens on THIS account, seven_day_pct still moves, and a
#       DIFFERENT account_key has turn_events in the same span -> counts
#       toward zero_token_nonzero_delta AND explained_by_other_account.
#   (E) 5->6: zero tokens, five_hour_pct moves, no turn_events from ANY
#       account in the span -> counts toward zero_token_nonzero_delta but
#       stays unexplained (real unattributed drain, not an assumption).
# With only 1 clean interval, the time-to-reset tertile buckets must report
# NOT-ENOUGH-DATA rather than guess from too little data.
#
# Exit 0 = pass.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPARE_PY="${SCRIPTS_ROOT}/leadv2-anthropic-window-compare.py"
DRAIN_PY="${SCRIPTS_ROOT}/leadv2-drain-weights.py"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "anthropic-window-compare")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 0. static checks.
# ---------------------------------------------------------------------------
if python3 -m py_compile "$COMPARE_PY"; then pass "0a py_compile leadv2-anthropic-window-compare.py"; else fail "0a py_compile leadv2-anthropic-window-compare.py"; fi
if python3 -m py_compile "$DRAIN_PY"; then pass "0b py_compile leadv2-drain-weights.py (shared account_key_for_config_dir import)"; else fail "0b py_compile leadv2-drain-weights.py"; fi

# ---------------------------------------------------------------------------
# Fixture db.
# ---------------------------------------------------------------------------
epoch() { python3 -c "import datetime,sys; print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))" "$1"; }
iso_plus() { python3 -c "
import datetime, sys
t = datetime.datetime.fromisoformat(sys.argv[1]) + datetime.timedelta(seconds=int(sys.argv[2]))
print(t.isoformat())" "$1" "$2"; }
T1="2026-09-14T00:00:00+00:00"; T2="2026-09-14T01:00:00+00:00"
T3="2026-09-14T02:00:00+00:00"; T4="2026-09-14T03:00:00+00:00"
T5="2026-09-14T04:00:00+00:00"; T6="2026-09-14T05:00:00+00:00"
E1="$(epoch "$T1")"; E2="$(epoch "$T2")"; E3="$(epoch "$T3")"
E4="$(epoch "$T4")"; E5="$(epoch "$T5")"; E6="$(epoch "$T6")"
RESET_A="$((E1 + 18000))"
RESET_B="$((E2 + 18000))"
# Events land strictly inside their intended interval (e0, e1] -- an event at
# exactly e0 would be attributed to the PRECEDING interval by the tool's own
# bisect convention (same rule leadv2-drain-weights.py uses), so every
# fixture event sits 1800s after its interval's left snapshot.
EV_A="$(iso_plus "$T1" 1800)"   # inside (E1,E2] -> interval A
EV_B="$(iso_plus "$T2" 1800)"   # inside (E2,E3] -> interval B
EV_D="$(iso_plus "$T4" 1800)"   # inside (E4,E5] -> interval D, OTHER account

DB="$TMP/history.db"
sqlite3 "$DB" <<SQL
CREATE TABLE rate_limit_history (id INTEGER PRIMARY KEY AUTOINCREMENT,captured_epoch INTEGER NOT NULL,account_key TEXT NOT NULL,account_label TEXT,is_active INTEGER NOT NULL DEFAULT 0,state TEXT,status TEXT,overage_status TEXT,five_hour_pct REAL,five_hour_reset_iso TEXT,five_hour_reset_epoch INTEGER,seven_day_pct REAL,seven_day_reset_iso TEXT,seven_day_reset_epoch INTEGER,binding_window TEXT,source TEXT);
CREATE TABLE turn_events (id INTEGER PRIMARY KEY AUTOINCREMENT,session_id TEXT,ts TEXT,cc INTEGER,cr INTEGER,input INTEGER,output INTEGER,model TEXT,tools_json TEXT,account_key TEXT);

INSERT INTO rate_limit_history (captured_epoch,account_key,state,five_hour_pct,five_hour_reset_epoch,seven_day_pct) VALUES
  ($E1,'fixture-acct','ok',10,$RESET_A,50),
  ($E2,'fixture-acct','ok',20,$RESET_A,52),
  ($E3,'fixture-acct','ok',5, $RESET_B,53),
  ($E4,'fixture-acct','ok',5, $RESET_B,53),
  ($E5,'fixture-acct','ok',5, $RESET_B,56),
  ($E6,'fixture-acct','ok',6, $RESET_B,56);

INSERT INTO turn_events (ts,input,output,model,account_key) VALUES
  ('$EV_A','60000','40000','claude-sonnet-5','fixture-acct'),
  ('$EV_B','20000','5000','claude-haiku-4-5','fixture-acct'),
  ('$EV_D','30000','10000','claude-opus-5','OTHER-account-xyz');
SQL

OUT="$(python3 "$COMPARE_PY" --db "$DB" --account fixture-acct 2>&1)"
log "compare output:"
printf '%s\n' "$OUT" | sed 's/^/  /'

if [[ "$OUT" == *"intervals_total=5 "* ]]; then pass "1a intervals_total=5 (six snapshots)"; else fail "1a intervals_total wrong: [$OUT]"; fi
if [[ "$OUT" == *"tokened_intervals=2 "* ]]; then pass "1b tokened_intervals=2 (A and B both carry tokens)"; else fail "1b tokened_intervals wrong: [$OUT]"; fi
if [[ "$OUT" == *"clean_intervals=1 "* ]]; then pass "1c clean_intervals=1 (B dropped: 5h window reset mid-interval)"; else fail "1c clean_intervals wrong: [$OUT]"; fi
if [[ "$OUT" == *"zero_token_nonzero_delta=2"* ]]; then pass "1d zero_token_nonzero_delta=2 (D and E; C is true idle, excluded)"; else fail "1d zero_token_nonzero_delta wrong: [$OUT]"; fi

if [[ "$OUT" == *"window=5h clean=1 mean_pct_per_token=0.0001 "* ]]; then
  pass "2a 5h rate = 10pct / 100000tok = 1e-4 exactly, on the one clean interval"
else
  fail "2a 5h rate wrong: [$OUT]"
fi
if [[ "$OUT" == *"window=7d clean=1 mean_pct_per_token=2e-05 "* ]]; then
  pass "2b 7d rate = 2pct / 100000tok = 2e-5 exactly"
else
  fail "2b 7d rate wrong: [$OUT]"
fi
if [[ "$OUT" == *"ratio_5h_over_7d n=1 mean=5 "* ]]; then
  pass "2c ratio 5h/7d = 5 on the single clean interval (not a fit, just a ratio)"
else
  fail "2c ratio wrong: [$OUT]"
fi
if [[ "$OUT" == *"ttr_buckets NOT-ENOUGH-DATA"* ]]; then
  pass "3 time-to-reset tertiles refuse to guess from 1 clean interval"
else
  fail "3 ttr_buckets should have refused: [$OUT]"
fi
if [[ "$OUT" == *"unattributed_drain zero_token_intervals=2 explained_by_other_account=1 unexplained=1"* ]]; then
  pass "4 unattributed drain: D explained by OTHER-account-xyz's turn_events, E stays unexplained"
else
  fail "4 unattributed_drain counts wrong: [$OUT]"
fi

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
