#!/usr/bin/env bash
# tests/test-leadv2-ratelimit-probe.sh — QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01
#
# Guards the rate_limit_history write path added to leadv2-ratelimit-probe.sh
# (per-account append-only history, keyed on the STABLE account_key, never the
# tier-derived account_label) and the leadv2-quota-window-history.sh reader.
#
# Fixture: from-scratch DB with only `kv` (test-quota-weekly-total.sh:42-49
# pattern) — the writer must create rate_limit_history itself. A fake
# leadv2-quota-live.sh (LEADV2_QUOTA_LIVE_SH) emits a two-account accounts[]
# array; epochs pinned via LEADV2_RATELIMIT_PROBE_NOW.
#
# Portable: sqlite3 + sh/sed/cut builtins only. Exit 0 = pass.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LEADV2_RATELIMIT_PROBE_SH / LEADV2_QUOTA_WINDOW_HISTORY_SH: mutation-control
# injection points (nc-*.sh in this dir) -- run the whole suite against a
# scratch mutated copy without ever editing the real script in place.
PROBE_SH="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPT_DIR}/../leadv2-ratelimit-probe.sh}"
HIST_SH="${LEADV2_QUOTA_WINDOW_HISTORY_SH:-${SCRIPT_DIR}/../leadv2-quota-window-history.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "ratelimit-probe")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1. syntax
# ---------------------------------------------------------------------------
if bash -n "$PROBE_SH"; then pass "1 bash -n leadv2-ratelimit-probe.sh"; else fail "1 bash -n leadv2-ratelimit-probe.sh"; fi
if bash -n "$HIST_SH"; then pass "1 bash -n leadv2-quota-window-history.sh"; else fail "1 bash -n leadv2-quota-window-history.sh"; fi

# ---------------------------------------------------------------------------
# fixture helpers
# ---------------------------------------------------------------------------
FAKE_LIVE="$TMP/quota-live-fake.sh"
NEXT_JSON="$TMP/next-accounts.json"
cat > "$FAKE_LIVE" <<EOF
#!/usr/bin/env bash
cat "$NEXT_JSON"
EOF
chmod +x "$FAKE_LIVE"

ACC_A_SUFFIX="default"
ACC_A_SERVICE="Claude Code-credentials"
ACC_B_SUFFIX="work"
ACC_B_SERVICE="claude-work-credentials"

# mk_json five_a seven_a bind_a label_a five_a_iso seven_a_iso \
#         five_b seven_b bind_b label_b five_b_iso seven_b_iso active_which
mk_json() {
  local five_a="$1" seven_a="$2" bind_a="$3" label_a="$4" five_a_iso="$5" seven_a_iso="$6"
  local five_b="$7" seven_b="$8" bind_b="$9" label_b="${10}" five_b_iso="${11}" seven_b_iso="${12}"
  local active_which="${13}"
  local act_a="false" act_b="false"
  [ "$active_which" = "a" ] && act_a="true"
  [ "$active_which" = "b" ] && act_b="true"
  cat > "$NEXT_JSON" <<JSON
{"provider":"anthropic","status":"ok","accounts":[
{"entry_suffix":"${ACC_A_SUFFIX}","service":"${ACC_A_SERVICE}","account_label":"${label_a}","active":${act_a},"status":"ok","five_hour":{"pct":${five_a},"reset_iso":"${five_a_iso}"},"seven_day":{"pct":${seven_a},"reset_iso":"${seven_a_iso}"},"binding_window":"${bind_a}"},
{"entry_suffix":"${ACC_B_SUFFIX}","service":"${ACC_B_SERVICE}","account_label":"${label_b}","active":${act_b},"status":"ok","five_hour":{"pct":${five_b},"reset_iso":"${five_b_iso}"},"seven_day":{"pct":${seven_b},"reset_iso":"${seven_b_iso}"},"binding_window":"${bind_b}"}
],"active_account":"${label_a}"}
JSON
}

F5A="2026-09-03T22:00:00+00:00"
S7A="2026-09-10T00:00:00+00:00"
F5B="2026-09-03T23:00:00+00:00"
S7B="2026-09-10T01:00:00+00:00"

run_probe() {
  local now_epoch="$1" db="$2"
  LEADV2_QUOTA_LIVE_SH="$FAKE_LIVE" LEADV2_BURN_DB="$db" LEADV2_RATELIMIT_PROBE_NOW="$now_epoch" \
    bash "$PROBE_SH"
}

row_count() {
  local db="$1"
  sqlite3 "$db" "SELECT COUNT(*) FROM rate_limit_history;"
}

# ===========================================================================
# Main scenario DB — assertions 2..8, 11
# ===========================================================================
DB="$TMP/main.db"
sqlite3 "$DB" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"

T0=1893456000  # fixed epoch, far future — avoids any real-clock coupling

# --- probe 1: two accounts, active=a ---
mk_json 10.0 43.0 seven_day max_20x "$F5A" "$S7A" 5.0 20.0 five_hour max_5x "$F5B" "$S7B" a
KV1="$(run_probe "$T0" "$DB")"
n1="$(row_count "$DB")"
if [[ "$n1" == "2" ]]; then
  pass "2 probe1: row count = 2 (one per account)"
else
  fail "2 probe1: row count = '$n1' expected 2"
fi

# --- assertion 3: two distinct account_key, exactly one is_active=1 ---
distinct_keys="$(sqlite3 "$DB" "SELECT COUNT(DISTINCT account_key) FROM rate_limit_history;")"
active_sum="$(sqlite3 "$DB" "SELECT SUM(is_active) FROM rate_limit_history;")"
if [[ "$distinct_keys" == "2" && "$active_sum" == "1" ]]; then
  pass "3 probe1: 2 distinct account_key, exactly one is_active=1"
else
  fail "3 probe1: distinct_keys='$distinct_keys' active_sum='$active_sum' expected 2 / 1"
fi

# --- assertion 4: kv still exactly one row, value == newest ACTIVE-account probe JSON ---
kv_rows="$(sqlite3 "$DB" "SELECT COUNT(*) FROM kv WHERE key='rate_limit_anthropic';")"
kv_val="$(sqlite3 "$DB" "SELECT value FROM kv WHERE key='rate_limit_anthropic';")"
if [[ "$kv_rows" == "1" && "$kv_val" == "$KV1" ]]; then
  pass "4 kv: exactly one row, value == probe stdout (no-regression lock on :141)"
else
  fail "4 kv: rows='$kv_rows' value_match=$([[ "$kv_val" == "$KV1" ]] && echo yes || echo no)"
fi

# --- probe 2: T0+1000 (> heartbeat 900), pcts changed on both accounts ---
T1=$(( T0 + 1000 ))
mk_json 15.0 43.0 seven_day max_20x "$F5A" "$S7A" 5.0 25.0 five_hour max_5x "$F5B" "$S7B" a
run_probe "$T1" "$DB" >/dev/null
n2="$(row_count "$DB")"
if [[ "$n2" == "4" ]]; then
  pass "2 probe2 (changed pcts): row count grows by one per account (now 4)"
else
  fail "2 probe2: row count = '$n2' expected 4"
fi

# --- assertion 5a: probe 3, T1+100 (< heartbeat), IDENTICAL readings -> no new row ---
T2=$(( T1 + 100 ))
run_probe "$T2" "$DB" >/dev/null
n3="$(row_count "$DB")"
if [[ "$n3" == "4" ]]; then
  pass "5a identical reading inside heartbeat -> no new row (still 4)"
else
  fail "5a row count = '$n3' expected 4 (unchanged)"
fi

# --- assertion 5b: probe 4, T2+900 (>= heartbeat from probe2's captured_epoch), SAME pcts -> new row ---
T3=$(( T2 + 900 ))
run_probe "$T3" "$DB" >/dev/null
n4="$(row_count "$DB")"
if [[ "$n4" == "6" ]]; then
  pass "5b heartbeat elapsed with unchanged pcts -> new row (now 6)"
else
  fail "5b row count = '$n4' expected 6"
fi

# --- assertion 6: tier flip (max_20x -> max_5x) same key, same pcts, < heartbeat -> row appended ---
T4=$(( T3 + 100 ))
mk_json 15.0 43.0 seven_day max_5x "$F5A" "$S7A" 5.0 25.0 five_hour max_5x "$F5B" "$S7B" a
run_probe "$T4" "$DB" >/dev/null
n5="$(row_count "$DB")"
key_after_flip="$(sqlite3 "$DB" "SELECT account_key FROM rate_limit_history WHERE account_label='max_5x' AND account_key='${ACC_A_SUFFIX}' AND captured_epoch=${T4};")"
if [[ "$n5" == "7" && "$key_after_flip" == "$ACC_A_SUFFIX" ]]; then
  pass "6 tier flip max_20x->max_5x -> row appended, account_key unchanged ('${ACC_A_SUFFIX}')"
else
  fail "6 row count='$n5' expected 7; key_after_flip='$key_after_flip' expected '$ACC_A_SUFFIX'"
fi

# --- assertion 7: reset_epoch == epoch(reset_iso); malformed ISO -> NULL ---
T5=$(( T4 + 1 ))
mk_json 16.0 43.0 seven_day max_5x "$F5A" "$S7A" 6.0 25.0 five_hour max_5x "not-a-date" "$S7B" a
run_probe "$T5" "$DB" >/dev/null
exp_epoch="$(python3 -c "import datetime;print(int(datetime.datetime.fromisoformat('$F5A').timestamp()))")"
got_epoch="$(sqlite3 "$DB" "SELECT five_hour_reset_epoch FROM rate_limit_history WHERE account_key='${ACC_A_SUFFIX}' AND captured_epoch=${T5};")"
got_null="$(sqlite3 "$DB" "SELECT five_hour_reset_epoch IS NULL FROM rate_limit_history WHERE account_key='${ACC_B_SUFFIX}' AND captured_epoch=${T5};")"
if [[ "$got_epoch" == "$exp_epoch" && "$got_null" == "1" ]]; then
  pass "7 reset_epoch == epoch(reset_iso) for a valid ISO; malformed ISO -> NULL (not 0/now)"
else
  fail "7 got_epoch='$got_epoch' expected '$exp_epoch'; malformed_is_null='$got_null' expected 1"
fi

# --- assertion 8: hot-path query (contract §6) returns newest row per account_key ---
hot_val="$(sqlite3 "$DB" "SELECT five_hour_pct FROM rate_limit_history WHERE account_key='${ACC_A_SUFFIX}' ORDER BY captured_epoch DESC, id DESC LIMIT 1;")"
if [[ "$hot_val" == "16.0" ]]; then
  pass "8 hot-path query (account_key=?, ORDER BY captured_epoch DESC,id DESC LIMIT 1) returns newest row"
else
  fail "8 hot-path query returned five_hour_pct='$hot_val' expected 16.0 (newest probe)"
fi
# freshness data support: a capture 20 min old must let the CALLER compute age_s > MAX_AGE_S(600)
STALE_EP=$(( T5 - 1200 ))
sqlite3 "$DB" "INSERT INTO rate_limit_history
  (captured_epoch,account_key,account_label,is_active,state,status,overage_status,
   five_hour_pct,five_hour_reset_iso,five_hour_reset_epoch,seven_day_pct,seven_day_reset_iso,
   seven_day_reset_epoch,binding_window,source)
  VALUES (${STALE_EP},'stale-test',NULL,0,'ok','ok',NULL,1.0,NULL,NULL,1.0,NULL,NULL,NULL,'ratelimit-probe');"
newest_stale_ep="$(sqlite3 "$DB" "SELECT captured_epoch FROM rate_limit_history WHERE account_key='stale-test' ORDER BY captured_epoch DESC, id DESC LIMIT 1;")"
age_s=$(( T5 - newest_stale_ep ))
if [[ "$age_s" -gt 600 ]]; then
  pass "8b captured_epoch supports staleness calc: age_s=$age_s > MAX_AGE_S(600) for a 20min-old row"
else
  fail "8b age_s='$age_s' expected > 600"
fi

# --- assertion 11: retention prune (default 180d): row at -200d pruned, row at -100d survives ---
NOW_R=$(( T5 + 10 ))
EP_200D=$(( NOW_R - 200*86400 ))
EP_100D=$(( NOW_R - 100*86400 ))
sqlite3 "$DB" "INSERT INTO rate_limit_history
  (captured_epoch,account_key,account_label,is_active,state,status,overage_status,
   five_hour_pct,five_hour_reset_iso,five_hour_reset_epoch,seven_day_pct,seven_day_reset_iso,
   seven_day_reset_epoch,binding_window,source)
  VALUES
  (${EP_200D},'retention-test',NULL,0,'ok','ok',NULL,1.0,NULL,NULL,1.0,NULL,NULL,NULL,'ratelimit-probe'),
  (${EP_100D},'retention-test',NULL,0,'ok','ok',NULL,1.0,NULL,NULL,1.0,NULL,NULL,NULL,'ratelimit-probe');"
mk_json 1.0 1.0 seven_day max_5x "$F5A" "$S7A" 1.0 1.0 five_hour max_5x "$F5B" "$S7B" a
run_probe "$NOW_R" "$DB" >/dev/null
remaining_200="$(sqlite3 "$DB" "SELECT COUNT(*) FROM rate_limit_history WHERE account_key='retention-test' AND captured_epoch=${EP_200D};")"
remaining_100="$(sqlite3 "$DB" "SELECT COUNT(*) FROM rate_limit_history WHERE account_key='retention-test' AND captured_epoch=${EP_100D};")"
if [[ "$remaining_200" == "0" && "$remaining_100" == "1" ]]; then
  pass "11 retention: row at now-200d pruned, row at now-100d survives (retain=180d default)"
else
  fail "11 retention: remaining_200='$remaining_200' expected 0; remaining_100='$remaining_100' expected 1"
fi

# ===========================================================================
# Seed DB — assertion 12 (isolated: history must be empty when the FIRST
# probe runs, so this cannot share the main DB above)
# ===========================================================================
DB2="$TMP/seed.db"
SEED_EPOCH=$(( T0 - 5000 ))
sqlite3 "$DB2" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO kv(key,value) VALUES('rate_limit_anthropic',
  '{\"status\":\"ok\",\"state\":\"ok\",\"overageStatus\":\"normal\",\"resetsAt\":\"$S7A\",\"captured_epoch\":${SEED_EPOCH},\"source\":\"ratelimit-probe\",\"account_label\":\"max_20x\",\"five_hour_pct\":9.0,\"five_hour_reset_iso\":\"$F5A\",\"seven_day_pct\":40.0,\"seven_day_reset_iso\":\"$S7A\",\"binding_window\":\"seven_day\"}');"

mk_json 10.0 43.0 seven_day max_20x "$F5A" "$S7A" 5.0 20.0 five_hour max_5x "$F5B" "$S7B" a
run_probe "$T0" "$DB2" >/dev/null
seed_rows="$(sqlite3 "$DB2" "SELECT COUNT(*) FROM rate_limit_history WHERE source='seed:kv';")"
seed_key="$(sqlite3 "$DB2" "SELECT account_key FROM rate_limit_history WHERE source='seed:kv';")"
total_after_1="$(row_count "$DB2")"
if [[ "$seed_rows" == "1" && "$seed_key" == "unknown" && "$total_after_1" == "3" ]]; then
  pass "12a seed: pre-existing kv + empty history -> one source=seed:kv row, account_key=unknown (3 total)"
else
  fail "12a seed_rows='$seed_rows' seed_key='$seed_key' total='$total_after_1' expected 1/unknown/3"
fi

run_probe "$(( T0 + 1000 ))" "$DB2" >/dev/null
seed_rows2="$(sqlite3 "$DB2" "SELECT COUNT(*) FROM rate_limit_history WHERE source='seed:kv';")"
if [[ "$seed_rows2" == "1" ]]; then
  pass "12b second probe does not re-seed (still exactly 1 seed:kv row)"
else
  fail "12b seed_rows after 2nd probe='$seed_rows2' expected 1"
fi

# ===========================================================================
# History reader — assertions 9, 10
# ===========================================================================
# 10. reader against a DB with no rate_limit_history -> exit 0 + "no history yet"
DB3="$TMP/empty.db"
sqlite3 "$DB3" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"
set +e
out10="$(LEADV2_BURN_DB="$DB3" bash "$HIST_SH" --days 14 2>&1)"
rc10=$?
set -e
if [[ $rc10 -eq 0 && "$out10" == *"no history yet"* ]]; then
  pass "10 reader against DB with no rate_limit_history -> exit 0 + 'no history yet'"
else
  fail "10 rc=$rc10 out='$out10'"
fi

# 9. historical query: known 5h/7d mix -> per-account dwell_pct split + peaks;
#    asleep-laptop fixture is dwell-capped at 1800s.
DB4="$TMP/history.db"
sqlite3 "$DB4" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"
mk_json 1.0 1.0 seven_day max_5x "$F5A" "$S7A" 1.0 1.0 five_hour max_5x "$F5B" "$S7B" a
BASE=1893000000
run_probe "$BASE" "$DB4" >/dev/null
# Build 60 evenly-spaced 'ok' samples over 10 days for account 'default', all
# binding_window=seven_day, then one big 12h gap (asleep laptop) to prove the
# 1800s dwell cap. account 'work' gets 55 'five_hour' samples, no gap.
python3 - "$DB4" "$BASE" <<'PY'
import sqlite3, sys
db, base = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(db)
step = int(10*86400/60)
rows = []
PEAK_I = 30  # single distinguished sample -> proves peak-with-timestamp, not just MAX()
for i in range(60):
    ep = base + i*step
    seven_pct = 77.0 if i == PEAK_I else 40.0
    rows.append((ep, 'default', 'max_5x', 0, 'ok', 'ok', 'normal', 10.0, None, None, seven_pct, None, None, 'seven_day', 'ratelimit-probe'))
# asleep-laptop gap: last 'default' sample followed by a 12h-later one
rows.append((base + 60*step + 12*3600, 'default', 'max_5x', 0, 'ok', 'ok', 'normal', 10.0, None, None, 40.0, None, None, 'seven_day', 'ratelimit-probe'))
step_b = int(10*86400/55)
for i in range(55):
    ep = base + i*step_b
    rows.append((ep, 'work', 'max_5x', 0, 'ok', 'ok', 'normal', 5.0, None, None, 20.0, None, None, 'five_hour', 'ratelimit-probe'))
conn.executemany(
  "INSERT INTO rate_limit_history (captured_epoch,account_key,account_label,is_active,state,status,"
  "overage_status,five_hour_pct,five_hour_reset_iso,five_hour_reset_epoch,seven_day_pct,"
  "seven_day_reset_iso,seven_day_reset_epoch,binding_window,source) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
  rows)
conn.commit()
conn.close()
PY
out9="$(LEADV2_BURN_DB="$DB4" bash "$HIST_SH" --days 30)"
if printf '%s\n' "$out9" | grep -q 'default' && printf '%s\n' "$out9" | grep -q 'work'; then
  pass "9 historical query lists both account_key rows (default, work)"
else
  fail "9 historical query missing an account: $out9"
fi
# Fixture design: 60 samples spaced 4h apart (14400s, already > the 1800s cap)
# plus one final sample 12h (43200s) later (the "asleep laptop" gap) -> ALL 60
# real gaps exceed the cap, so a correctly-capped script reports EXACTLY
# 60*1800=108000s of dwell. Reading through the script's own --json output
# (not a second hand-rolled query) so this assertion actually exercises the
# mutable line under test.
out9_json="$(LEADV2_BURN_DB="$DB4" bash "$HIST_SH" --account default --days 30 --json | grep -v '^coverage:')"
dwell_default="$(python3 -c "
import json,sys
rows=json.loads(sys.stdin.read())
for r in rows:
    if r.get('window')=='seven_day':
        print(r.get('dwell_s'))
" <<<"$out9_json")"
if [[ "$dwell_default" == "108000" ]]; then
  pass "9b asleep-laptop gap dwell-capped via script output: dwell_s=$dwell_default (60 gaps x 1800s cap)"
else
  fail "9b dwell_s='${dwell_default:-<empty>}' expected 108000 (cap not applied by the script?)"
fi

# --- assertion 9c: peak-with-timestamp (D6) -- one distinguished sample
# (i=30, seven_day_pct=77.0) among 60 flat 40.0 samples must be reported as
# THE peak, at ITS OWN captured_epoch -- not MAX() alone (which would give
# the right value but no way to say when it happened).
PEAK_EPOCH_EXPECTED=$(( BASE + 30 * (10*86400/60) ))
peak_pct_default="$(python3 -c "
import json,sys
rows=json.loads(sys.stdin.read())
for r in rows:
    if r.get('window')=='seven_day':
        print(r.get('peak_pct'))
" <<<"$out9_json")"
peak_epoch_default="$(python3 -c "
import json,sys
rows=json.loads(sys.stdin.read())
for r in rows:
    if r.get('window')=='seven_day':
        print(r.get('peak_epoch'))
" <<<"$out9_json")"
if [[ "$peak_pct_default" == "77.0" && "$peak_epoch_default" == "$PEAK_EPOCH_EXPECTED" ]]; then
  pass "9c peak-with-timestamp: peak_pct=77.0 at peak_epoch=$peak_epoch_default (matches distinguished sample)"
else
  fail "9c peak_pct='$peak_pct_default' expected 77.0; peak_epoch='$peak_epoch_default' expected '$PEAK_EPOCH_EXPECTED'"
fi

# ---------------------------------------------------------------------------
echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then printf '%s\n' "${ERRORS[@]}" >&2; exit 1; fi
log "ALL PASS — rate_limit_history write path + historical reader verified."
exit 0
