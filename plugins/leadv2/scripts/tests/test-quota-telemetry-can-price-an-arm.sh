#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-turn-account-attribute.py leadv2-turn-account-attribute leadv2-cost-actuals.sh leadv2-cost-actuals leadv2-drain-weights.py leadv2-drain-weights leadv2-quota-read.py leadv2-quota-read leadv2-ratelimit-probe.sh leadv2-ratelimit-probe leadv2-dispatch-code.sh leadv2-dispatch-code
# tests/test-quota-telemetry-can-price-an-arm.sh — QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01
#
# Guards the telemetry half of dispatch-1786402f:
#   - turn_events gains account_key by DERIVATION (jsonl_path[:path.find(
#     "/projects/")] -> sha256_8(realpath)), never a backfill guess; rows that
#     cannot be derived stay NULL (D3: unknown, never a default key)
#   - cost_actual_recorded.tokens gets REAL counts (costs.yaml ->
#     turn_events -> `-`), never a fabricated 0 (D5)
#   - leadv2-drain-weights.py recovers known weights from attributed data
#     (positive control), names the unattributed state (before-reading), and
#     names the 48h retention limit on the 7d window (D9)
#   - attribution never aborts a caller: locked DB -> rc 2, the probe still
#     completes and writes its own row
#
# Two DBs: DB1 exercises attribution + cost-actuals joins; DB2 is a synthetic
# pricing fixture (rate_limit_history carries only the columns drain-weights
# reads — the live-schema equivalence is proven by the live before/after
# reading recorded in the task report, not re-proven here).
#
# Exit 0 = pass.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Mutation-control injection points (nc-quota-telemetry-can-price-an-arm.sh):
# the whole suite runs against scratch mutated copies, never in-place edits.
ATTR_PY="${LEADV2_TURN_ACCOUNT_ATTRIBUTE_PY:-${SCRIPTS_ROOT}/leadv2-turn-account-attribute.py}"
COST_LIB="${LEADV2_COST_ACTUALS_SH:-${SCRIPTS_ROOT}/lib/leadv2-cost-actuals.sh}"
DRAIN_PY="${SCRIPTS_ROOT}/leadv2-drain-weights.py"
PROBE_SH="${LEADV2_RATELIMIT_PROBE_SH:-${SCRIPTS_ROOT}/leadv2-ratelimit-probe.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS+1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "quota-tel")"
trap 'rm -rf "$TMP"; [[ -n "${HOLDER_PID:-}" ]] && kill "$HOLDER_PID" 2>/dev/null' EXIT

sha8() { python3 -c 'import hashlib,os,sys; print(hashlib.sha256(os.path.realpath(sys.argv[1]).rstrip("/").encode()).hexdigest()[:8])' "$1"; }

# ---------------------------------------------------------------------------
# 1. syntax
# ---------------------------------------------------------------------------
if python3 -m py_compile "$ATTR_PY" 2>/dev/null; then pass "1 py_compile leadv2-turn-account-attribute.py"; else fail "1 py_compile leadv2-turn-account-attribute.py"; fi
if python3 -m py_compile "$DRAIN_PY" 2>/dev/null; then pass "1 py_compile leadv2-drain-weights.py"; else fail "1 py_compile leadv2-drain-weights.py"; fi
if bash -n "$COST_LIB"; then pass "1 bash -n lib/leadv2-cost-actuals.sh"; else fail "1 bash -n lib/leadv2-cost-actuals.sh"; fi

# ---------------------------------------------------------------------------
# DB1: attribution — real-schema subset (column names mirror ~/.claude/burn)
# ---------------------------------------------------------------------------
CFG_A="$TMP/cfg-a"; CFG_B="$TMP/cfg-b"; mkdir -p "$CFG_A" "$CFG_B" "$CFG_A/projects/p" "$CFG_B/projects/p"
KEY_A="$(sha8 "$CFG_A")"; KEY_B="$(sha8 "$CFG_B")"
UUID1="11111111-1111-1111-1111-111111111111"
UUID2="22222222-2222-2222-2222-222222222222"
UUIDB="33333333-3333-3333-3333-333333333333"
UUIDG="44444444-4444-4444-4444-444444444444"   # no session row at all
DB1="$TMP/attr.db"
sqlite3 "$DB1" <<SQL
CREATE TABLE sessions (
  session_id TEXT PRIMARY KEY, project_name TEXT, project_dir TEXT,
  jsonl_path TEXT, start_ts TEXT, last_asst_ts TEXT, last_user_ts TEXT,
  turns INTEGER DEFAULT 0, human_msg_count INTEGER DEFAULT 0,
  cc_total INTEGER DEFAULT 0, cr_total INTEGER DEFAULT 0,
  input_total INTEGER DEFAULT 0, output_total INTEGER DEFAULT 0,
  last_model TEXT, last_cr_snapshot INTEGER DEFAULT 0,
  last_input_snapshot INTEGER DEFAULT 0, scan_mtime REAL DEFAULT 0,
  scan_byte_offset INTEGER DEFAULT 0, scan_line_count INTEGER DEFAULT 0,
  updated_at TEXT);
CREATE TABLE turn_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, ts TEXT,
  cc INTEGER, cr INTEGER, input INTEGER, output INTEGER, model TEXT,
  tools_json TEXT);
INSERT INTO sessions (session_id, jsonl_path) VALUES
  ('$UUID1', '$CFG_A/projects/p/a.jsonl'),
  ('$UUID2', '$CFG_A/projects/p/b.jsonl'),
  ('$UUIDB', '$CFG_B/projects/p/c.jsonl'),
  ('no-proj-session', '/tmp/flat/nowhere.jsonl');
INSERT INTO turn_events (session_id, ts, input, output, model) VALUES
  ('$UUID1',    '2026-09-13T10:00:01Z', 700, 300, 'claude-sonnet-5'),
  ('$UUID2',    '2026-09-13T10:05:01Z', 400, 100, 'claude-opus-5'),
  ('$UUIDB',    '2026-09-13T10:10:01Z',  50,  50, 'claude-opus-5'),
  ('no-proj-session', '2026-09-13T10:15:01Z', 10, 10, 'claude-sonnet-5'),
  ('$UUIDG',    '2026-09-13T10:20:01Z',  20,  20, 'claude-haiku-4-5');
SQL

# ---------------------------------------------------------------------------
# 2. attribution run 1 — derived keys land on WRITTEN rows
# ---------------------------------------------------------------------------
OUT1="$(python3 "$ATTR_PY" --db "$DB1" 2>"$TMP/attr1.err")"; RC1=$?
n_a="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM turn_events WHERE account_key='$KEY_A';")"
n_b="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM turn_events WHERE account_key='$KEY_B';")"
n_null="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM turn_events WHERE account_key IS NULL;")"
if [[ "$RC1" == "0" && "$n_a" == "2" && "$n_b" == "1" && "$n_null" == "2" \
      && "$OUT1" == "attributed=3 null=2 total=5" ]]; then
  pass "2 attributor: 3 rows keyed ($KEY_A x2, $KEY_B x1) on WRITTEN rows, rc=0"
else
  fail "2 attributor: rc=$RC1 out='$OUT1' a=$n_a b=$n_b null=$n_null"
fi

# 3. unattributable rows stay NULL (D3) — no /projects/ root, no session row
u1="$(sqlite3 "$DB1" "SELECT account_key FROM turn_events WHERE session_id='no-proj-session';")"
u2="$(sqlite3 "$DB1" "SELECT account_key FROM turn_events WHERE session_id='$UUIDG';")"
if [[ -z "$u1" && -z "$u2" ]]; then
  pass "3 no-/projects/ and no-session rows keep account_key NULL"
else
  fail "3 NULL violated: no-proj='$u1' ghost='$u2'"
fi

# 4. idempotent: a second run attributes nothing and changes no keys
OUT2="$(python3 "$ATTR_PY" --db "$DB1" 2>/dev/null)"; RC2=$?
if [[ "$RC2" == "0" && "$OUT2" == "attributed=0 null=2 total=5" \
      && "$(sqlite3 "$DB1" "SELECT COUNT(*) FROM turn_events WHERE account_key='$KEY_A';")" == "2" ]]; then
  pass "4 idempotent: second run attributed=0, keys unchanged"
else
  fail "4 idempotent: rc=$RC2 out='$OUT2'"
fi

# sessions table untouched by attribution
if [[ "$(sqlite3 "$DB1" "SELECT COUNT(*) FROM sessions;")" == "4" ]]; then
  pass "4 sessions table count unchanged (4)"
else
  fail "4 sessions table count changed"
fi

# 5. locked DB -> rc 2, clean message, bounded time
HOLDER_PID=""
python3 - "$DB1" <<'PY' &
import sqlite3, sys, time
conn = sqlite3.connect(sys.argv[1], timeout=1)
conn.execute("BEGIN EXCLUSIVE")
time.sleep(8)
PY
HOLDER_PID=$!
sleep 0.7
T_LOCK_START=$(python3 -c 'import time; print(time.time())')
OUT_LOCK="$(python3 "$ATTR_PY" --db "$DB1" 2>"$TMP/lock.err")"; RC_LOCK=$?
T_LOCK_DUR="$(python3 -c "import time; print('%.1f' % (time.time() - $T_LOCK_START))")"
kill "$HOLDER_PID" 2>/dev/null; wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
if [[ "$RC_LOCK" == "2" && -s "$TMP/lock.err" ]]; then
  pass "5 locked DB: rc=2 (skip this cycle, reason on stderr) after ${T_LOCK_DUR}s, no crash"
else
  fail "5 locked DB: rc=$RC_LOCK out='$OUT_LOCK' dur=${T_LOCK_DUR}s"
fi

# 5b. a failing attributor never aborts the caller: the probe still exits 0
FAIL_ATTR="$TMP/fail-attr.sh"
printf '#!/usr/bin/env bash\necho "attributed=0 null=0 total=0 error=simulated" >&2\nexit 2\n' > "$FAIL_ATTR"
chmod +x "$FAIL_ATTR"
FAKE_LIVE="$TMP/quota-live-fake.sh"; NEXT_JSON="$TMP/next.json"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$NEXT_JSON" > "$FAKE_LIVE"; chmod +x "$FAKE_LIVE"
cat > "$NEXT_JSON" <<'JSON'
{"provider":"anthropic","status":"ok","accounts":[
{"entry_suffix":"probeacct","service":"Claude Code-credentials-probeacct","account_label":"max_20x","active":true,"status":"ok","five_hour":{"pct":10.0,"reset_iso":"2026-09-13T22:00:00+00:00"},"seven_day":{"pct":4.0,"reset_iso":"2026-09-16T00:00:00+00:00"},"binding_window":"five_hour"}
],"active_account":"max_20x"}
JSON
DBP="$TMP/probe.db"; sqlite3 "$DBP" "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT);"
LEADV2_QUOTA_LIVE_SH="$FAKE_LIVE" LEADV2_BURN_DB="$DBP" \
LEADV2_TURN_ACCOUNT_ATTRIBUTE_PY="$FAIL_ATTR" LEADV2_RATELIMIT_PROBE_NOW="1893456000" \
  bash "$PROBE_SH" >/dev/null 2>&1
RC_PROBE=$?
probe_rows="$(sqlite3 "$DBP" "SELECT COUNT(*) FROM rate_limit_history;" 2>/dev/null)"
if [[ "$RC_PROBE" == "0" && "$probe_rows" == "1" ]]; then
  pass "5b caller completes: probe rc=0 and its history row written despite attributor rc=2"
else
  fail "5b caller completes: probe rc=$RC_PROBE rows='$probe_rows'"
fi

# ---------------------------------------------------------------------------
# DB2: pricing — the fit must recover KNOWN weights from attributed data
# ---------------------------------------------------------------------------
DB2="$TMP/pricing.db"
KEY_P="$(sha8 "$CFG_A")"
python3 - "$DB2" "$CFG_A" "$KEY_P" <<'PY'
import datetime, os, sqlite3, sys
db, cfg, key = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(db)
conn.executescript("""
CREATE TABLE sessions (session_id TEXT PRIMARY KEY, jsonl_path TEXT);
CREATE TABLE turn_events (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT,
  ts TEXT, cc INTEGER, cr INTEGER, input INTEGER, output INTEGER, model TEXT, tools_json TEXT);
CREATE TABLE rate_limit_history (captured_epoch INTEGER, account_key TEXT,
  state TEXT, five_hour_pct REAL, seven_day_pct REAL);
""")
sid = "fit-session-0000"
conn.execute("INSERT INTO sessions VALUES (?, ?)",
             (sid, os.path.join(cfg, "projects/p/fit.jsonl")))
T0 = 1893456000
WA, WB = 0.0001, 0.0002   # known weights the fit must recover
pct = 10.0
utc = datetime.timezone.utc
for i in range(16):
    a = 500 + (37 * i) % 400          # varying mix -> not collinear
    b = 0 if i % 4 == 0 else 200 + (53 * i) % 300
    pct += WA * a + WB * b            # exact linear relation -> r2 ~ 1.0
    # event epoch INSIDE interval i: (T0+i*300, T0+(i+1)*300]
    ts = datetime.datetime.fromtimestamp(T0 + i * 300 + 60, tz=utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    conn.execute("INSERT INTO turn_events (session_id, ts, input, output, model) "
                 "VALUES (?,?,?,?,?)", (sid, ts, a, 0, "model-a"))
    conn.execute("INSERT INTO turn_events (session_id, ts, input, output, model) "
                 "VALUES (?,?,?,?,?)", (sid, ts, b, 0, "model-b"))
    conn.execute("INSERT INTO rate_limit_history VALUES (?,?,?,?,?)",
                 (T0 + (i + 1) * 300, key, "ok", round(pct, 10), None))
conn.commit(); conn.close()
PY

# 6. BEFORE reading: unattributed turn_events is named, not silently empty
FIT_BEFORE="$(python3 "$DRAIN_PY" --window 5h --db "$DB2" --account "$KEY_P" 2>&1)"
if [[ "$FIT_BEFORE" == *"NOT-ENOUGH-DATA"* && "$FIT_BEFORE" == *"unattributed"* ]]; then
  pass "6 before: fit names 'turn_events unattributed' instead of fitting nothing"
else
  fail "6 before: '$FIT_BEFORE'"
fi

# attribute DB2, then the fit must recover the planted weights
python3 "$ATTR_PY" --db "$DB2" >/dev/null 2>&1
FIT_AFTER="$(python3 "$DRAIN_PY" --window 5h --db "$DB2" --account "$KEY_P" 2>&1)"
W_A="$(printf '%s\n' "$FIT_AFTER" | grep -o 'model-a=[0-9.]*' | head -1 | cut -d= -f2)"
W_B="$(printf '%s\n' "$FIT_AFTER" | grep -o 'model-b=[0-9.]*' | head -1 | cut -d= -f2)"
R2="$(printf '%s\n' "$FIT_AFTER" | grep -o 'r2=[-0-9.]*' | cut -d= -f2)"
CORR="$(printf '%s\n' "$FIT_AFTER" | grep -o 'max_abs_corr=[0-9.]*' | cut -d= -f2)"
W_OK="$(python3 -c 'import sys; a,b,r=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3]); print(int(abs(a-0.0001)<1e-6 and abs(b-0.0002)<1e-6 and r>0.99))' "${W_A:-9}" "${W_B:-9}" "${R2:--9}")"
if [[ "$W_OK" == "1" ]]; then
  pass "6 after: NNLS recovers planted weights (a=0.0001 b=0.0002) r2=$R2 corr=$CORR"
else
  fail "6 after: wa='$W_A' wb='$W_B' r2='$R2' (expected 0.0001/0.0002/>0.99)"
fi

# 6b. 7d window names the structural limit even when data exists
FIT_7D="$(python3 "$DRAIN_PY" --window 7d --db "$DB2" --account "$KEY_P" 2>&1)"
if [[ "$FIT_7D" == *"NOT-ENOUGH-DATA"* && "$FIT_7D" == *"retention_limit_h=48"* ]]; then
  pass "6b 7d window names retention_limit_h=48 (lib.py:8), never a number"
else
  fail "6b 7d window: '$FIT_7D'"
fi

# ---------------------------------------------------------------------------
# 7. cost-actuals: real counts, `-` for unknown, never 0 (D5)
# ---------------------------------------------------------------------------
ROOT="$TMP/lane-root"
HANDOFF="$ROOT/docs/handoff/dispatch-TESTSIG1"
mkdir -p "$HANDOFF"
printf '2026-09-13T10:00:00Z\tattempt-1\t%s\n2026-09-13T10:30:00Z\tattempt-2\t%s\n' "$UUID1" "$UUID2" > "$HANDOFF/sessions.map"

# (a) costs.yaml — direct observation wins
cat > "$HANDOFF/costs.yaml" <<YAML
sessions:
  $UUID1:
    input_tokens: 1000
    output_tokens: 500
  $UUID2:
    input_tokens: 200
    output_tokens: 100
YAML
TOK_A="$(LEADV2_COST_FLUSH_SH=/bin/true bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG1'")"
if [[ "$TOK_A" == "1800" ]]; then pass "7a tokens from costs.yaml = 1800"; else fail "7a costs.yaml tokens='$TOK_A'"; fi

# (b) costs.yaml gone -> turn_events over the lane's session ids
rm "$HANDOFF/costs.yaml"
TOK_B="$(LEADV2_BURN_DB="$DB1" bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG1'")"
if [[ "$TOK_B" == "1500" ]]; then pass "7b tokens from turn_events = 1500 (700+300+400+100)"; else fail "7b turn_events tokens='$TOK_B'"; fi

# (c) unknown session everywhere -> `-`, never 0 and never empty
printf '2026-09-13T11:00:00Z\tattempt-9\t99999999-9999-9999-9999-999999999999\n' > "$HANDOFF/sessions.map"
TOK_C="$(LEADV2_BURN_DB="$DB1" bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG1'")"
if [[ "$TOK_C" == "-" ]]; then pass "7c unknown lane -> tokens='-' (not 0)"; else fail "7c unknown tokens='$TOK_C'"; fi

# (d) a zero-only costs.yaml is rejected, not reported as a free lane
printf 'sessions:\n  x:\n    input_tokens: 0\n    output_tokens: 0\n' > "$HANDOFF/costs.yaml"
rm "$HANDOFF/sessions.map"
TOK_D="$(LEADV2_BURN_DB="$DB1" bash -c "source '$COST_LIB'; leadv2_lane_token_total '$ROOT' 'TESTSIG1'")"
if [[ "$TOK_D" == "-" ]]; then pass "7d zero-total costs.yaml -> '-' (a false zero would poison observed-cost)"; else fail "7d zero-total tokens='$TOK_D'"; fi

# ---------------------------------------------------------------------------
# 8. the record path: 8 args stamp tokens, 7 args stamp `-`, junk -> `-`
# ---------------------------------------------------------------------------
EVTDIR="$TMP/evtdir"; mkdir -p "$EVTDIR"
JOURNAL="$EVTDIR/testrepo.jsonl"
python3 - "$JOURNAL" "$UUID1" <<'PY'
import datetime, json, sys
path, sid = sys.argv[1], sys.argv[2]
row = {"kind": "worker_spawned", "task": "TESTSIG1", "arm": "glm", "repo": "testrepo",
       "session": sid,
       "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
with open(path, "w") as fh:
    fh.write(json.dumps(row) + "\n")
PY
REC8="$(LEADV2_EVENT_LOG_DIR="$EVTDIR" LEADV2_BURN_DB="$DB1" bash -c "source '$COST_LIB'; leadv2_cost_actual_record testrepo TESTSIG1 closed done work code claude-sonnet-5 1500")"
REC7="$(LEADV2_EVENT_LOG_DIR="$EVTDIR" bash -c "source '$COST_LIB'; leadv2_cost_actual_record testrepo TESTSIG1 closed done work code claude-sonnet-5")"
RECJ="$(LEADV2_EVENT_LOG_DIR="$EVTDIR" bash -c "source '$COST_LIB'; leadv2_cost_actual_record testrepo TESTSIG1 closed done work code claude-sonnet-5 'n/a'")"
EMITTED="$(grep -c 'kind=cost_actual\|"kind": *"cost_actual"' "$JOURNAL" 2>/dev/null)"
EMIT_TOK="$(grep 'tokens=1500' "$JOURNAL" | wc -l | tr -d ' ')"
if [[ "$REC8" == *"tokens=1500"* && "$REC7" == *"tokens=-"* && "$RECJ" == *"tokens=-"* && "$EMITTED" -ge 1 && "$EMIT_TOK" -ge 1 ]]; then
  pass "8 record: 8 args -> tokens=1500; 7 args/junk -> tokens=-; row emitted to journal"
else
  fail "8 record: rec8='$REC8' rec7='$REC7' recj='$RECJ' emitted='$EMITTED' emit_tok='$EMIT_TOK'"
fi

# ---------------------------------------------------------------------------
printf -- '\n'
printf -- 'pass=%d fail=%d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
exit 0
