#!/usr/bin/env bash
# tests/test-ratelimit-refresh-if-stale.sh — QUOTA-PROVIDER-SIGNAL-GOES-STALE-01
#
# Guards leadv2-ratelimit-refresh-if-stale.sh (the refresh-on-read seam
# leadv2-quota-status.sh now calls before it reads the rate_limit_anthropic
# kv row) and the resets= parsing fix in leadv2-quota-status.sh itself.
#
# Three load-bearing properties, one test group each:
#   1. no stampede (atomic lock; N concurrent callers -> 1 probe run)
#   2. a failed refresh never looks like a fresh reading (captured_epoch
#      stays put, the gauge keeps saying "not captured")
#   3. the refresher actually runs on a stale row (else property 2's own
#      restore logic would trivially "pass" by never doing anything)
# Negative controls for all three live in mutation-control/ (leadv2-mutation-
# control.sh artifacts, run separately — see docs/handoff/dispatch-18dfa6f6/report.md).
#
# Portable: sqlite3 + sh/sed builtins only, no jq/GNU date. Exit 0 = pass.
# run-all-triggers: leadv2-quota-status leadv2-ratelimit-refresh-if-stale

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH_SH="${LEADV2_RATELIMIT_REFRESH_SH_UNDER_TEST:-${SCRIPT_DIR}/../leadv2-ratelimit-refresh-if-stale.sh}"
QUOTA_SH="${SCRIPT_DIR}/../leadv2-quota-status.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "ratelimit-refresh")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1. syntax
# ---------------------------------------------------------------------------
if bash -n "$REFRESH_SH"; then pass "1 bash -n leadv2-ratelimit-refresh-if-stale.sh"; else fail "1 bash -n leadv2-ratelimit-refresh-if-stale.sh"; fi
if bash -n "$QUOTA_SH"; then pass "1 bash -n leadv2-quota-status.sh"; else fail "1 bash -n leadv2-quota-status.sh"; fi

# ---------------------------------------------------------------------------
# fixture helpers
# ---------------------------------------------------------------------------
NOW="$(date -u +%s)"

seed_row() {  # $1=db $2=raw-json-or-empty
  local db="$1" raw="$2"
  sqlite3 "$db" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);" >/dev/null
  if [ -n "$raw" ]; then
    LEADV2_SEED_RAW="$raw" python3 -c '
import os, sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES (\x27rate_limit_anthropic\x27, ?)", (os.environ["LEADV2_SEED_RAW"],))
conn.commit(); conn.close()
' "$db"
  fi
}

read_row() {  # $1=db -> raw json or empty
  sqlite3 "$1" "SELECT value FROM kv WHERE key='rate_limit_anthropic';" 2>/dev/null || true
}

row_epoch() { printf '%s' "$1" | sed -n 's/.*"captured_epoch"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1; }
row_status() { printf '%s' "$1" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1; }

# A fake probe: on invocation, appends to a counter file and writes whatever
# the caller told it to via env vars -- stands in for the real
# leadv2-ratelimit-probe.sh so no test ever touches a real network/keychain.
mk_fake_probe() {  # $1=probe-path $2=counter-file $3=result(ok|fail) $4=db
  local p="$1" ctr="$2" result="$3" db="$4"
  cat > "$p" <<PYEOF
#!/usr/bin/env bash
printf 'x' >> "$ctr"
LEADV2_FP_DB="$db" LEADV2_FP_RESULT="$result" python3 - <<'INNER'
import os, sqlite3, time
db = os.environ["LEADV2_FP_DB"]
result = os.environ["LEADV2_FP_RESULT"]
epoch = int(time.time())
if result == "ok":
    val = '{"status":"ok","state":"ok","captured_epoch":%d,"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}' % epoch
else:
    val = '{"status":"unknown","state":"unauthenticated","captured_epoch":%d,"detail":"no credential"}' % epoch
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)", (val,))
conn.commit(); conn.close()
INNER
PYEOF
  chmod +x "$p"
}

# A poison probe: if this ever runs, a test that must never invoke the probe
# has failed (used for the "already fresh -> no-op" case).
mk_poison_probe() {  # $1=probe-path $2=sentinel-file
  local p="$1" sentinel="$2"
  cat > "$p" <<EOF
#!/usr/bin/env bash
touch "$sentinel"
EOF
  chmod +x "$p"
}

run_refresh() {  # $1=db $2=probe -> stdout swallowed; just runs
  LEADV2_BURN_DB="$1" LEADV2_RATELIMIT_PROBE_SH="$2" LEADV2_RATELIMIT_LOCK_DIR="$TMP/locks" \
    bash "$REFRESH_SH" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 2. already fresh -> no-op, probe never invoked, bytes unchanged
# ---------------------------------------------------------------------------
DB2="$TMP/t2.db"
FRESH_RAW='{"status":"ok","state":"ok","captured_epoch":'"$((NOW - 100))"',"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}'
seed_row "$DB2" "$FRESH_RAW"
POISON2="$TMP/poison2.sh"; SENTINEL2="$TMP/poison2.hit"
mk_poison_probe "$POISON2" "$SENTINEL2"
run_refresh "$DB2" "$POISON2"
if [ ! -f "$SENTINEL2" ]; then pass "2 fresh row -> probe never invoked"; else fail "2 fresh row -> probe never invoked (poison probe ran)"; fi
AFTER2="$(read_row "$DB2")"
if [ "$AFTER2" = "$FRESH_RAW" ]; then pass "2 fresh row -> bytes unchanged"; else fail "2 fresh row -> bytes unchanged (got: $AFTER2)"; fi

# ---------------------------------------------------------------------------
# 3. stale row + successful probe -> row becomes fresh (property: refresher fires)
# ---------------------------------------------------------------------------
DB3="$TMP/t3.db"
STALE_OK_RAW='{"status":"ok","state":"ok","captured_epoch":'"$((NOW - 700))"',"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}'
seed_row "$DB3" "$STALE_OK_RAW"
CTR3="$TMP/ctr3"; PROBE3="$TMP/probe3.sh"
mk_fake_probe "$PROBE3" "$CTR3" ok "$DB3"
run_refresh "$DB3" "$PROBE3"
AFTER3="$(read_row "$DB3")"
E3="$(row_epoch "$AFTER3")"
if [ -n "$E3" ] && [ $(( NOW - E3 )) -lt 60 ]; then pass "3 stale row + successful probe -> captured_epoch advances (refresher actually runs)"; else fail "3 stale row + successful probe -> captured_epoch advances (got: $AFTER3)"; fi
if [ "$(row_status "$AFTER3")" = "ok" ]; then pass "3 stale row + successful probe -> status ok"; else fail "3 stale row + successful probe -> status ok (got: $AFTER3)"; fi

# ---------------------------------------------------------------------------
# 4. stale row + FAILED probe, prior row exists -> captured_epoch UNCHANGED,
#    old row restored verbatim (property 2 core case)
# ---------------------------------------------------------------------------
DB4="$TMP/t4.db"
OLD_EPOCH4=$((NOW - 700))
STALE_RAW4='{"status":"ok","state":"ok","captured_epoch":'"$OLD_EPOCH4"',"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}'
seed_row "$DB4" "$STALE_RAW4"
CTR4="$TMP/ctr4"; PROBE4="$TMP/probe4.sh"
mk_fake_probe "$PROBE4" "$CTR4" fail "$DB4"
run_refresh "$DB4" "$PROBE4"
AFTER4="$(read_row "$DB4")"
if [ "$AFTER4" = "$STALE_RAW4" ]; then
  pass "4 failed refresh (prior row exists) -> row restored byte-identical, captured_epoch unchanged"
else
  fail "4 failed refresh (prior row exists) -> row restored byte-identical (got: $AFTER4, want: $STALE_RAW4)"
fi

# ---------------------------------------------------------------------------
# 5. FAILED probe, NO prior row -> row stays fully absent (never a fresh-
#    looking failure fabricated from nothing)
# ---------------------------------------------------------------------------
DB5="$TMP/t5.db"
sqlite3 "$DB5" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);" >/dev/null
CTR5="$TMP/ctr5"; PROBE5="$TMP/probe5.sh"
mk_fake_probe "$PROBE5" "$CTR5" fail "$DB5"
run_refresh "$DB5" "$PROBE5"
AFTER5="$(read_row "$DB5")"
if [ -z "$AFTER5" ]; then pass "5 failed refresh (no prior row) -> row stays absent"; else fail "5 failed refresh (no prior row) -> row stays absent (got: $AFTER5)"; fi

# ---------------------------------------------------------------------------
# 6. concurrency -- N callers race a stale row, only ONE probe invocation
# ---------------------------------------------------------------------------
DB6="$TMP/t6.db"
STALE_RAW6='{"status":"ok","state":"ok","captured_epoch":'"$((NOW - 700))"',"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}'
seed_row "$DB6" "$STALE_RAW6"
CTR6="$TMP/ctr6"; PROBE6="$TMP/probe6-slow.sh"
cat > "$PROBE6" <<EOF
#!/usr/bin/env bash
printf 'x' >> "$CTR6"
sleep 0.3
LEADV2_FP_DB="$DB6" python3 - <<'INNER'
import os, sqlite3, time
conn = sqlite3.connect(os.environ["LEADV2_FP_DB"])
conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)",
             ('{"status":"ok","state":"ok","captured_epoch":%d,"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}' % int(time.time()),))
conn.commit(); conn.close()
INNER
EOF
chmod +x "$PROBE6"
for i in 1 2 3 4; do
  ( run_refresh "$DB6" "$PROBE6" ) &
done
wait
N6=$(wc -c < "$CTR6" 2>/dev/null | tr -d ' ')
if [ "${N6:-0}" -eq 1 ]; then pass "6 concurrency: 4 racing callers -> exactly 1 probe invocation"; else fail "6 concurrency: 4 racing callers -> exactly 1 probe invocation (got: ${N6:-0})"; fi

# ---------------------------------------------------------------------------
# 7. quota-status.sh integration: refresh-on-read wiring, both settings
# ---------------------------------------------------------------------------
DB7="$TMP/t7.db"
sqlite3 "$DB7" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS turn_events (ts TEXT, model TEXT, input INTEGER, cc INTEGER, cr INTEGER, output INTEGER);" >/dev/null
FAKE_REFRESHER7="$TMP/fake-refresher7.sh"
cat > "$FAKE_REFRESHER7" <<EOF
#!/usr/bin/env bash
LEADV2_FR_DB="\${LEADV2_BURN_DB}" python3 - <<'INNER'
import os, sqlite3, time
conn = sqlite3.connect(os.environ["LEADV2_FR_DB"])
conn.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)")
conn.execute("INSERT OR REPLACE INTO kv (key, value) VALUES ('rate_limit_anthropic', ?)",
             ('{"status":"ok","state":"ok","captured_epoch":%d,"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}' % int(time.time()),))
conn.commit(); conn.close()
INNER
EOF
chmod +x "$FAKE_REFRESHER7"

rep_on="$(LEADV2_BURN_DB="$DB7" LEADV2_QUOTA_REFRESH_ON_READ=1 LEADV2_RATELIMIT_REFRESH_SH="$FAKE_REFRESHER7" bash "$QUOTA_SH" --report)"
if printf '%s' "$rep_on" | grep -q "rate_limit_info"; then
  pass "7 refresh-on-read ON: empty row -> refresher fires before the read, gauge sees the fresh row in the SAME invocation"
else
  fail "7 refresh-on-read ON: empty row -> refresher fires before the read (report: $(printf '%s' "$rep_on" | grep 'rate_limit:'))"
fi

DB7B="$TMP/t7b.db"
sqlite3 "$DB7B" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS turn_events (ts TEXT, model TEXT, input INTEGER, cc INTEGER, cr INTEGER, output INTEGER);" >/dev/null
SENTINEL7B="$TMP/sentinel7b.hit"
POISON7B="$TMP/poison7b.sh"
mk_poison_probe "$POISON7B" "$SENTINEL7B"
rep_off="$(LEADV2_BURN_DB="$DB7B" LEADV2_QUOTA_REFRESH_ON_READ=0 LEADV2_RATELIMIT_REFRESH_SH="$POISON7B" bash "$QUOTA_SH" --report)"
if [ ! -f "$SENTINEL7B" ] && printf '%s' "$rep_off" | grep -q "not captured"; then
  pass "7 refresh-on-read OFF: refresher never invoked, gauge stays 'not captured'"
else
  fail "7 refresh-on-read OFF: refresher never invoked (sentinel exists: $([ -f "$SENTINEL7B" ] && echo yes || echo no); report: $(printf '%s' "$rep_off" | grep 'rate_limit:'))"
fi

# ---------------------------------------------------------------------------
# 8. resets= fix: a fresh row with a quoted ISO resetsAt prints the ISO
#    value, never "resets=?"
# ---------------------------------------------------------------------------
DB8="$TMP/t8.db"
sqlite3 "$DB8" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS turn_events (ts TEXT, model TEXT, input INTEGER, cc INTEGER, cr INTEGER, output INTEGER);" >/dev/null
FRESH_RAW8='{"status":"ok","state":"ok","captured_epoch":'"$NOW"',"resetsAt":"2026-09-16T05:00:00+00:00","overageStatus":"normal"}'
seed_row "$DB8" "$FRESH_RAW8"
rep8="$(LEADV2_BURN_DB="$DB8" LEADV2_QUOTA_REFRESH_ON_READ=0 bash "$QUOTA_SH" --report)"
rl_line8="$(printf '%s' "$rep8" | grep 'rate_limit:' || true)"
if printf '%s' "$rl_line8" | grep -q 'resets=2026-09-16T05:00:00+00:00'; then
  pass "8 resets= fix: fresh row with quoted ISO resetsAt prints the real value"
else
  fail "8 resets= fix: fresh row with quoted ISO resetsAt prints the real value (got: $rl_line8)"
fi
if printf '%s' "$rl_line8" | grep -q 'resets=?'; then
  fail "8 resets= fix: line still contains the old resets=? placeholder ($rl_line8)"
else
  pass "8 resets= fix: no resets=? placeholder left"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "[TEST] ALL PASS — the provider signal stays fresh, a failed refresh never fakes freshness, resets= is real."
  exit 0
else
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
