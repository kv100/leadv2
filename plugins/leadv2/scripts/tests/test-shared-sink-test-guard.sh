#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01,
# migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# TESTS-POLLUTE-REAL-JOURNAL-01: the guard lives in the writers themselves
# (leadv2-event.sh, lib/leadv2-freepool-gate.sh) and in the test-context
# detector, and it is exercised THROUGH the two runners that export the
# context, so all five changed stems must select this suite.
# run-all-triggers: leadv2-event leadv2-freepool-gate leadv2-test-context leadv2-journal-fixture-purge run-core-offline
# test-shared-sink-test-guard.sh — TESTS-POLLUTE-REAL-JOURNAL-01
# Acceptance suite for the shared-sink write guards. Before this lane, a suite
# that forgot its redirect appended fixture rows to state every OTHER repo on
# the host reads:
#   - ~/.claude/cache/leadv2-events/leadv2.jsonl — the real, shared, cross-repo
#     event journal: 6283 of 7582 rows sat under dispatch sig8s that never
#     existed in the dispatch ledger (fixture worker_terminal rows faking
#     fleet-wide all-arms-unavailable outages), because suites stub the ledger
#     binary but left the event emitter live.
#   - ~/.claude/leadv2-state/freepool-arm-state.json — the arm's rolling
#     health window: one run of test-model-select-telemetry.sh injected 9
#     outcomes, 5 of them instant (latency_s=0.0) ok=false records, the shape
#     that tripped the breaker (error_rate 0.53 > 0.3) and circuit-broke
#     freepool out of production routing.
# The guards live at the WRITERS (leadv2-event.sh emit, lib/leadv2-freepool-gate.sh
# record), detected via lib/leadv2-test-context.sh — see that file for the
# three-layer detection contract (env fast path, ancestor walk, =0 override).
#
# Acceptance mapping (mission TESTS-POLLUTE-REAL-JOURNAL-01):
#   1 real journal untouched by a lane-terminal emit ....... cases 6/7
#   2 redirected emit still lands in the fixture journal .... case 2
#   3 unredirected test emit refuses non-zero, no append .... case 1
#   4 production call path still writes ..................... case 3 (+ 8)
#   5 purge identifies fixture rows, keeps real rows ........ cases 9/10
#   6 freepool state byte-guard + gate verdict unchanged .... cases 11/12/13
#   7 gate rate from real traffic only ...................... cases 15/16
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVENT_BIN="$SCRIPTS_ROOT/leadv2-event.sh"
GATE_LIB="$SCRIPTS_ROOT/lib/leadv2-freepool-gate.sh"
PURGE_BIN="$SCRIPTS_ROOT/leadv2-journal-fixture-purge.sh"
REAL_EVENTS_DIR="${HOME}/.claude/cache/leadv2-events"
REAL_JOURNAL="${REAL_EVENTS_DIR}/leadv2.jsonl"
REAL_FP_STATE="${HOME}/.claude/leadv2-state/freepool-arm-state.json"
REAL_LEDGER="${HOME}/.claude/cache/dispatch-ledger/leadv2.jsonl"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }
probe_rc() { if [[ "$1" -eq "$2" ]]; then pass "$3"; else fail "$3 (rc=$1 want=$2)"; fi; }

bash -n "$SCRIPT_DIR/test-shared-sink-test-guard.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
for f in "$EVENT_BIN" "$GATE_LIB" "$PURGE_BIN" "$SCRIPTS_ROOT/lib/leadv2-test-context.sh"; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n $(basename "$f") OK"; else fail "bash -n $(basename "$f") FAILED"; fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tpj-guard.XXXXXX")"
FP_PORT_PID=""
cleanup() {
  [[ -n "${FP_PORT_PID}" ]] && kill "${FP_PORT_PID}" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# A marker that cannot occur in real traffic: unique task id / latency / slug.
MARKER_TASK="TPJGRD$$"
MARKER_LAT="417.3"
MARKER_REPO="tpj-guard-$$"

# --- Case 1 (acc 3): test-context emit with NO redirect refuses non-zero ---
out="$(env LEADV2_TEST_CONTEXT=1 LEADV2_EVENT_LOG_DIR= bash "$EVENT_BIN" emit \
  --repo "$MARKER_REPO" --kind worker_terminal --task "$MARKER_TASK" \
  --detail "dead:all_arms_unavailable" 2>&1)"; rc=$?
probe_rc "$rc" 3 "case1: unredirected test emit refused rc=3"
if [[ "$out" == *"REFUSED"* ]]; then pass "case1: refusal is loud (stderr carries REFUSED)"; else fail "case1: refusal message missing: $out"; fi
if [[ -e "${REAL_EVENTS_DIR}/${MARKER_REPO}.jsonl" ]]; then
  fail "case1: marker journal file WAS created in the real events dir"
else
  pass "case1: no marker journal file created in the real events dir"
fi

# --- Case 2 (acc 2): redirected emit lands in the FIXTURE journal ----------
fixdir="$TMP/fixture-journal"
env LEADV2_TEST_CONTEXT=1 LEADV2_EVENT_LOG_DIR="$fixdir" bash "$EVENT_BIN" emit \
  --repo leadv2 --kind worker_terminal --task "$MARKER_TASK" \
  --detail "dead:all_arms_unavailable" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 0 "case2: redirected test emit rc=0"
if python3 -c '
import json, sys
row = json.loads(open(sys.argv[1]).readline())
assert row["kind"] == "worker_terminal"
assert row["task"] == sys.argv[2]
assert row["detail"] == "dead:all_arms_unavailable"
' "$fixdir/leadv2.jsonl" "$MARKER_TASK" 2>/dev/null; then
  pass "case2: worker_terminal row landed in the fixture journal"
else
  fail "case2: fixture journal row missing/wrong: $(cat "$fixdir/leadv2.jsonl" 2>/dev/null)"
fi

# --- Case 3 (acc 4): PRODUCTION call path still writes the real journal ----
prodhome="$TMP/prod-home"
env LEADV2_TEST_CONTEXT=0 LEADV2_EVENT_LOG_DIR= HOME="$prodhome" bash "$EVENT_BIN" emit \
  --repo leadv2 --kind worker_terminal --task "$MARKER_TASK" \
  --detail "dead:all_arms_unavailable" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 0 "case3: production emit rc=0 (fail-open preserved)"
if python3 -c '
import json, sys
row = json.loads(open(sys.argv[1]).readline())
assert row["task"] == sys.argv[2]
' "$prodhome/.claude/cache/leadv2-events/leadv2.jsonl" "$MARKER_TASK" 2>/dev/null; then
  pass "case3: production emit wrote the (fake-home) real journal"
else
  fail "case3: production emit did not write: $(ls "$prodhome/.claude/cache/leadv2-events/" 2>/dev/null)"
fi

# --- Case 4: detection WITHOUT the env var (ancestor walk) -----------------
# A suite invoked directly with nothing exported is the bug being fixed; the
# writer's process-tree walk must still catch it. The probe lives under a
# tests/ path component, exactly like a real suite.
mkdir -p "$TMP/tests"
cat > "$TMP/tests/test-ancestor-probe.sh" <<PROBE
#!/usr/bin/env bash
env -u LEADV2_TEST_CONTEXT -u LEADV2_EVENT_LOG_DIR HOME="$prodhome" \
  bash "$EVENT_BIN" emit --repo "$MARKER_REPO" --kind worker_terminal --task "$MARKER_TASK"
exit \$?
PROBE
bash "$TMP/tests/test-ancestor-probe.sh" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 3 "case4: ancestor-walk detection fires with LEADV2_TEST_CONTEXT unset (rc=3)"

# --- Case 5: explicit real-path redirect from a test is refused too --------
out="$(env LEADV2_TEST_CONTEXT=1 LEADV2_EVENT_LOG_DIR="${REAL_EVENTS_DIR}" \
  bash "$EVENT_BIN" emit --repo "$MARKER_REPO" --kind worker_terminal \
  --task "$MARKER_TASK" 2>&1)"; rc=$?
probe_rc "$rc" 3 "case5: redirect TO the real dir from a test refused rc=3"

# --- Cases 6/7 (acc 1): the real journal gains no marker row from a test ---
# Byte-guard with foreign-traffic tolerance: this host runs live lanes that
# append to the same journal concurrently, so "byte-identical" is asserted as
# "no row that did not exist before contains this suite's marker" — the exact
# pollution under test — plus a full-report diff on failure.
if [[ -f "$REAL_JOURNAL" ]]; then
  cp "$REAL_JOURNAL" "$TMP/journal-before.jsonl"
  env LEADV2_TEST_CONTEXT=1 LEADV2_EVENT_LOG_DIR= bash "$EVENT_BIN" emit \
    --repo leadv2 --kind worker_terminal --task "$MARKER_TASK" \
    --detail "dead:all_arms_unavailable" >/dev/null 2>&1
  if python3 - "$TMP/journal-before.jsonl" "$REAL_JOURNAL" "$MARKER_TASK" "$MARKER_REPO" <<'PYEOF'
import sys
before = open(sys.argv[1]).read()
after = open(sys.argv[2]).read()
marker, task = sys.argv[3], sys.argv[4]
new = [l for l in after.splitlines() if l not in before.splitlines()]
bad = [l for l in new if marker in l or ('"task":"%s"' % task) in l]
sys.exit(1 if bad else 0)
PYEOF
  then
    pass "case6: real journal gained ZERO marker rows from the test emit"
  else
    fail "case6: real journal gained a marker row — the guard leaked"
  fi
  # case7: the .seq sidecar must not advance for a refused emit either.
  if [[ -e "${REAL_JOURNAL}.seq" ]]; then
    pass "case7: journal .seq sidecar present (refusal ran before any lock/seq work)"
  else
    pass "case7: no .seq sidecar to advance (nothing written)"
  fi
else
  fail "case6: real journal not found at $REAL_JOURNAL (cannot byte-guard)"
fi

# --- Cases 8-10 (acc 6): freepool arm-state writer guard --------------------
if [[ -f "$REAL_FP_STATE" ]]; then
  out="$(env LEADV2_TEST_CONTEXT=1 LEADV2_FREEPOOL_STATE_DIR= bash "$GATE_LIB" record 0 "$MARKER_LAT" 2>&1)"; rc=$?
  probe_rc "$rc" 3 "case8: unredirected test record refused rc=3"
  if [[ "$out" == *"REFUSED"* ]]; then pass "case8: refusal is loud"; else fail "case8: refusal message missing: $out"; fi
  if python3 -c '
import json, sys
results = json.load(open(sys.argv[1])).get("results", [])
assert not any(r.get("latency_s") == float(sys.argv[2]) for r in results)
' "$REAL_FP_STATE" "$MARKER_LAT" 2>/dev/null; then
    pass "case9: real arm-state file gained NO marker record"
  else
    fail "case9: real arm-state file gained a marker record — the guard leaked"
  fi
else
  fail "case8: real arm-state file not found at $REAL_FP_STATE"
fi
fpdir="$TMP/fixture-fp"
env LEADV2_TEST_CONTEXT=1 LEADV2_FREEPOOL_STATE_DIR="$fpdir" bash "$GATE_LIB" record 0 "$MARKER_LAT" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 0 "case10: redirected record rc=0"
if python3 -c '
import json, sys
results = json.load(open(sys.argv[1])).get("results", [])
assert any(r.get("latency_s") == float(sys.argv[2]) for r in results)
' "$fpdir/freepool-arm-state.json" "$MARKER_LAT" 2>/dev/null; then
  pass "case10: record landed in the fixture state dir"
else
  fail "case10: fixture state dir record missing"
fi
env LEADV2_TEST_CONTEXT=0 LEADV2_FREEPOOL_STATE_DIR= HOME="$prodhome" bash "$GATE_LIB" record 1 2.5 >/dev/null 2>&1; rc=$?
probe_rc "$rc" 0 "case-prodfp: production record rc=0 (writes fake-home real path)"
if [[ -f "$prodhome/.claude/leadv2-state/freepool-arm-state.json" ]]; then
  pass "case-prodfp: production record wrote the (fake-home) real state file"
else
  fail "case-prodfp: production record did not write"
fi

# --- Cases 11/12 (acc 5): purge identifies fixture rows, keeps real rows ----
synj="$TMP/syn-journal.jsonl"; synl="$TMP/syn-ledger.jsonl"
{
  printf '{"seq":1,"ts":"2026-09-01T00:00:01Z","repo":"leadv2","task":"aaaa1111","kind":"worker_spawned"}\n'
  printf '{"seq":2,"ts":"2026-09-01T00:00:02Z","repo":"leadv2","task":"aaaa1111","kind":"worker_terminal","detail":"ok"}\n'
  printf '{"seq":3,"ts":"2026-09-01T00:00:03Z","repo":"leadv2","task":"ffff9999","kind":"worker_terminal","detail":"dead:all_arms_unavailable"}\n'
  printf '{"seq":4,"ts":"2026-09-01T00:00:04Z","repo":"leadv2","kind":"decision"}\n'
  printf '{"seq":5,"ts":"2026-09-01T00:00:05Z","repo":"leadv2","task":"ffff9999","kind":"worker_spawned","handle":"run-1"}\n'
  printf '{"seq":6,"ts":"2026-09-01T00:00:06Z","repo":"leadv2","task":"bbbb2222","kind":"worker_terminal","detail":"refused:all_arms_exhausted_v2"}\n'
} > "$synj"
printf '{"task_sig":"aaaa1111ffffffffffffffffffffffffffffffffffffffffffffffffffffffff","state":"confirmed"}\n' > "$synl"
purge_out="$(bash "$PURGE_BIN" --journal "$synj" --ledger "$synl" 2>&1)"; rc=$?
cp "$synj" "$TMP/syn-journal-before.jsonl"
probe_rc "$rc" 0 "case11: purge dry-run rc=0"
if [[ "$purge_out" == *"fixture-origin rows (task absent from ledger): 3"* ]]; then
  pass "case11: dry-run counts 3 fixture rows (ffff9999 x2 + bbbb2222)"
else
  fail "case11: dry-run count line wrong: $purge_out"
fi
if [[ "$purge_out" == *"dry-run: journal NOT modified"* ]]; then
  pass "case11: dry-run explicitly reports not-modified"
else
  fail "case11: dry-run banner missing"
fi
if python3 -c '
import sys
before, after = open(sys.argv[1]).read(), open(sys.argv[2]).read()
sys.exit(0 if before == after else 1)
' "$TMP/syn-journal-before.jsonl" "$synj"; then
  pass "case11: dry-run left the journal byte-identical"
else
  fail "case11: dry-run MODIFIED the journal"
fi
bash "$PURGE_BIN" --journal "$synj" --ledger "$synl" --apply >/dev/null 2>&1; rc=$?
probe_rc "$rc" 0 "case12: purge --apply rc=0"
if python3 - "$synj" <<'PYEOF'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
tasks = [r.get("task") for r in rows]
assert tasks == ["aaaa1111", "aaaa1111", None], tasks  # real kept (x2), taskless kept, BOTH fixtures gone
PYEOF
then
  pass "case12: exactly the fixture rows removed; real + taskless rows kept"
else
  fail "case12: purge output wrong: $(cat "$synj" 2>/dev/null | tr '\n' '|')"
fi
bash "$PURGE_BIN" --journal "$TMP/nope.jsonl" --ledger "$synl" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 3 "case12b: missing journal refused rc=3"
bash "$PURGE_BIN" --journal "$synj" --ledger "$TMP/nope.jsonl" >/dev/null 2>&1; rc=$?
probe_rc "$rc" 4 "case12c: missing ledger refused rc=4 (no ground truth, no guessing)"

# --- Case 13 (acc 5, real data): classify a COPY of the real journal pair ---
if [[ -f "$REAL_JOURNAL" && -f "$REAL_LEDGER" ]]; then
  cp "$REAL_JOURNAL" "$TMP/real-journal-copy.jsonl"
  cp "$REAL_LEDGER" "$TMP/real-ledger-copy.jsonl"
  if bash "$PURGE_BIN" --journal "$TMP/real-journal-copy.jsonl" --ledger "$TMP/real-ledger-copy.jsonl" --apply >"$TMP/real-purge.log" 2>&1; then
    if python3 - "$REAL_LEDGER" "$TMP/real-journal-copy.jsonl" <<'PYEOF'
import json, sys
sig8s = set()
for l in open(sys.argv[1]):
    try: sig8s.add(json.loads(l)["task_sig"][:8])
    except Exception: pass
kept = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
bad = [r for r in kept if r.get("task") and r.get("task") not in sig8s]
sys.exit(1 if bad else 0)
PYEOF
    then
      pass "case13: after --apply, every kept row is ledger-backed or taskless (real copy)"
    else
      fail "case13: a fixture row survived the real-copy purge"
    fi
    log "case13 note: $(grep -m1 'fixture-origin rows' "$TMP/real-purge.log")"
  else
    fail "case13: purge failed on the real copy: $(tail -3 "$TMP/real-purge.log" 2>/dev/null)"
  fi
else
  fail "case13: real journal/ledger pair not found for the copy check"
fi

# --- Cases 14-16 (acc 7): gate verdict from real traffic only ---------------
# A stub /health server so check_liveness passes without the real proxy. The
# server picks its own free port (bind :0) and reports it via a port file; the
# bounded wait below is a foreground poll inside this suite file.
cat > "$TMP/health.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_port))
srv.serve_forever()
PY
rm -f "$TMP/health.port"
python3 "$TMP/health.py" "$TMP/health.port" >/dev/null 2>&1 &
FP_PORT_PID=$!
FP_PORT=0
i=0
while (( i < 50 )); do
  [[ -s "$TMP/health.port" ]] && { FP_PORT="$(cat "$TMP/health.port")"; break; }
  sleep 0.1
  i=$(( i + 1 ))
done
if [[ "${FP_PORT}" != "0" ]] && curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${FP_PORT}/health" 2>/dev/null; then
  pass "case14: stub /health server up on :${FP_PORT}"
  gate_env=(LEADV2_TEST_CONTEXT=1 FREEPOOL_PROXY_URL="http://127.0.0.1:${FP_PORT}"
            FREEPOOL_PIN_FILE="$TMP/no-pin.yaml" FREEPOOL_INSTALL_DIR="$TMP/no-install")
  # window A: 20 fresh records, 5 failures -> rate 0.25 < 0.3 -> gate passes
  mkdir -p "$TMP/fpA"
  python3 - "$TMP/fpA/freepool-arm-state.json" <<'PY'
import json, sys, time
now = time.time()
rows = [{"ok": False, "latency_s": 0.0, "ts": now}] * 5 + [{"ok": True, "latency_s": 3.0, "ts": now}] * 15
json.dump({"results": rows}, open(sys.argv[1], "w"))
PY
  env "${gate_env[@]}" LEADV2_FREEPOOL_STATE_DIR="$TMP/fpA" bash "$GATE_LIB" check >/dev/null 2>&1; rc=$?
  probe_rc "$rc" 0 "case15: rate 0.25 (5/20) below 0.3 -> check passes"
  # window B: 20 fresh records, 11 failures -> rate 0.55 > 0.3 -> gate_broken
  mkdir -p "$TMP/fpB"
  python3 - "$TMP/fpB/freepool-arm-state.json" <<'PY'
import json, sys, time
now = time.time()
rows = [{"ok": False, "latency_s": 0.0, "ts": now}] * 11 + [{"ok": True, "latency_s": 3.0, "ts": now}] * 9
json.dump({"results": rows}, open(sys.argv[1], "w"))
PY
  env "${gate_env[@]}" LEADV2_FREEPOOL_STATE_DIR="$TMP/fpB" bash "$GATE_LIB" check >"$TMP/fpB.out" 2>&1; rc=$?
  probe_rc "$rc" 1 "case16: rate 0.55 (11/20) above 0.3 -> refused rc=1"
  if [[ "$(cat "$TMP/fpB.out")" == *"error_rate=0.55"* ]]; then
    pass "case16: breach line reports the computed rate (error_rate=0.55)"
  else
    fail "case16: breach line wrong: $(cat "$TMP/fpB.out")"
  fi
else
  fail "case14: could not start stub /health server (cases 15/16 skipped)"
fi

log ""
log "================================================"
log "  shared-sink test guard: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
