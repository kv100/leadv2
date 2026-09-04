#!/usr/bin/env bash
# test-leadv2-freepool-gate.sh — FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01.
#
# 2026-09-04: the freepool proxy was down for a day, and nobody could tell:
# the gate's arm_down refusal reached the arbiter as a bare non-zero rc, which
# rendered as util_freepool=100 — the same number as an arm that had merely
# burnt its quota. One number, two facts. This suite locks the three things
# that must now hold:
#   1. `gate liveness` names the proxy state (ok / arm_down+reason /
#      gate_broken+reason) — a dead port answers 000 and the report SAYS so.
#   2. the arbiter renders a dead freepool as util_freepool=down (a word,
#      never 100) plus freepool_gate=arm_down on the decision line, while a
#      gate_broken refusal stays a NUMBER plus freepool_gate=gate_broken.
#   3. arm_down is loud: the gate's stderr says NOT-quota-exhaustion with the
#      http code, and the arbiter re-emits [route-arbiter] FREEPOOL ARM DOWN
#      on its own stderr (the dispatch journal).
# Mutation controls (one per requirement) run via leadv2-mutation-control.sh
# against THIS suite — see docs/handoff/dispatch-2236d405/report.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="${SCRIPTS_DIR}/lib/leadv2-freepool-gate.sh"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
ARM_CFG="${SCRIPTS_DIR}/../config/freepool-arm.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

bash -n "$GATE" 2>/dev/null || { echo "ERROR: gate syntax check failed"; exit 1; }
bash -n "$ARBITER" 2>/dev/null || { echo "ERROR: arbiter syntax check failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/freepool-liveness.XXXXXX")"
cleanup() {
  [[ -n "${STUB_PID:-}" ]] && kill "${STUB_PID}" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# Hermetic-regression baseline: the real configs are read (never written) by
# every code path below — prove it, same shape as test-freepool-pin-drift.sh.
cfg_sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
ROUTING_BEFORE="$(cfg_sha "$ROUTING")"; ARM_CFG_BEFORE="$(cfg_sha "$ARM_CFG")"

# ── Stub proxy: a REAL loopback HTTP server, because the defect being locked
#    is socket-level (no listener -> curl 000), not just status-code parsing.
#    Behaviour is driven by a state file so one server serves every case.
STUB_STATE="$TMP/stub-state.json"
printf '{"health": 200, "models": ["kimi-k3", "nemotron-3-super-120b", "gpt-oss-120b"]}\n' > "$STUB_STATE"
cat > "$TMP/stub-server.py" <<'PYEOF'
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = os.environ["STUB_STATE"]

def state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {"health": 200, "models": ["kimi-k3"]}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        st = state()
        if self.path.startswith("/health"):
            code = int(st.get("health", 200))
            body = json.dumps({"status": "ok" if 200 <= code < 300 else "bad"}).encode()
        elif self.path.startswith("/v1/models"):
            body = json.dumps({"data": [{"id": m} for m in st.get("models", [])]}).encode()
            code = 200
        else:
            body = b"{}"; code = 404
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(os.path.dirname(STATE), "stub-port.txt"), "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF
STUB_PID=""
STUB_PORT=""
STUB_STATE="$STUB_STATE" python3 "$TMP/stub-server.py" &
STUB_PID=$!
for _ in $(seq 1 100); do
  [[ -s "$TMP/stub-port.txt" ]] && break
  sleep 0.05
done
STUB_PORT="$(cat "$TMP/stub-port.txt" 2>/dev/null || true)"
if [[ -z "$STUB_PORT" ]]; then
  echo "ERROR: stub proxy failed to bind a loopback port"; exit 1
fi
STUB_URL="http://127.0.0.1:${STUB_PORT}"

# A port that is guaranteed DEAD for this run: bound once to reserve it, then
# released without listening — curl against it answers 000 (no listener),
# the founder's exact 2026-09-04 observable.
DEAD_PORT="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
DEAD_URL="http://127.0.0.1:${DEAD_PORT}"

# Every gate invocation is fully hermetic: stub URL, scratch state dir, absent
# pin file (check_pin_drift fail-opens on it), scratch install dir.
gate_env() { # <proxy-url> — prints env assignments for `env`-style invocation
  printf 'FREEPOOL_PROXY_URL=%s LEADV2_FREEPOOL_STATE_DIR=%s FREEPOOL_PIN_FILE=%s/no-such-pin.yaml FREEPOOL_INSTALL_DIR=%s/install' \
    "$1" "$TMP/state" "$TMP" "$TMP"
}

# ── Requirement 2: liveness report — ok / dead / sick, each NAMED ──────────

out="$(env $(gate_env "$STUB_URL") bash "$GATE" liveness 2>"$TMP/e")"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -qE '^\[freepool-liveness\] ok health=200 models=[1-9][0-9]* url='; then
  pass "liveness green: healthy proxy reports ok with models count ($(printf '%s' "$out" | head -1))"
else
  fail "liveness green: healthy proxy reports ok with models count" "rc=${rc} out=${out} err=$(cat "$TMP/e")"
fi

out="$(env $(gate_env "$DEAD_URL") bash "$GATE" liveness 2>"$TMP/e")"; rc=$?
if [[ $rc -ne 0 ]] \
   && printf '%s\n' "$out" | grep -q '^\[freepool-liveness\] arm_down health=000 reason=unreachable ' \
   && grep -q '^LEADV2_DISPATCH_REFUSED: arm_down$' "$TMP/e"; then
  pass "liveness red: proxy answering 000 is named arm_down/unreachable (not a number)"
else
  fail "liveness red: proxy answering 000 is named arm_down/unreachable (not a number)" "rc=${rc} out=${out} err=$(cat "$TMP/e")"
fi

printf '{"health": 503, "models": ["kimi-k3"]}\n' > "$STUB_STATE"
out="$(env $(gate_env "$STUB_URL") bash "$GATE" liveness 2>"$TMP/e")"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -q '^\[freepool-liveness\] arm_down health=503 reason=health_non_2xx '; then
  pass "liveness red: port listening but unhealthy (503) is named arm_down/health_non_2xx"
else
  fail "liveness red: port listening but unhealthy (503) is named arm_down/health_non_2xx" "rc=${rc} out=${out}"
fi

printf '{"health": 200, "models": []}\n' > "$STUB_STATE"
out="$(env $(gate_env "$STUB_URL") bash "$GATE" liveness 2>"$TMP/e")"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -q '^\[freepool-liveness\] gate_broken health=200 reason=models_empty ' \
   && grep -q '^LEADV2_DISPATCH_REFUSED: gate_broken$' "$TMP/e"; then
  pass "liveness red: healthy port with empty /v1/models is named gate_broken/models_empty"
else
  fail "liveness red: healthy port with empty /v1/models is named gate_broken/models_empty" "rc=${rc} out=${out}"
fi
printf '{"health": 200, "models": ["kimi-k3", "nemotron-3-super-120b", "gpt-oss-120b"]}\n' > "$STUB_STATE"

# ── Requirement 3a: the gate's own arm_down refusal is LOUD ────────────────

out="$(env $(gate_env "$DEAD_URL") bash "$GATE" check 2>"$TMP/e")"; rc=$?
if [[ $rc -ne 0 ]] \
   && grep -q 'ARM DOWN: proxy unreachable.*http_code=000.*NOT quota exhaustion' "$TMP/e" \
   && grep -q '^LEADV2_DISPATCH_REFUSED: arm_down$' "$TMP/e"; then
  pass "gate check red: arm_down stderr names http_code=000 and says NOT quota exhaustion"
else
  fail "gate check red: arm_down stderr names http_code=000 and says NOT quota exhaustion" "rc=${rc} err=$(cat "$TMP/e")"
fi

# ── Requirements 1+3b: the arbiter separates DEAD from EXHAUSTED ───────────
# Real quota-live stub (all providers healthy and cheap enough that some arm
# always wins — the freepool verdict rides every decision line regardless).
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "$TMP/live.sh"
export ROUTE_TEST_QUOTA='{"glm":{"status":"ok","five_hour":{"pct":30},"weekly":{"pct":40}},"codex":{"status":"ok","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":20,"seven_day_pct":20}]}}'

cat > "$TMP/arbiter-driver.sh" <<'EOF'
#!/usr/bin/env bash
# Run route_arbiter from a bash file (never the caller's interactive shell):
# the lib's script-dir resolver needs real BASH_SOURCE semantics.
set -u
source "$1"
shift
route_arbiter worker "$1"
EOF

arb_probe() { # <gate-path> <proxy-url-or-""> -> sets ARB_OUT/ARB_RC/ARB_ERR
  local gate="$1" proxy="$2" envs
  envs="LEADV2_ROUTE_ARBITER_QUOTA_LIVE=$TMP/live.sh LEADV2_ROUTE_ARBITER_FREEPOOL_GATE=$gate ROUTE_TEST_QUOTA=$ROUTE_TEST_QUOTA"
  if [[ -n "$proxy" ]]; then
    envs="$envs FREEPOOL_PROXY_URL=$proxy LEADV2_FREEPOOL_STATE_DIR=$TMP/state FREEPOOL_PIN_FILE=$TMP/no-such-pin.yaml FREEPOOL_INSTALL_DIR=$TMP/install"
  fi
  ARB_ERR="$TMP/arb-err.txt"; : > "$ARB_ERR"
  ARB_OUT="$(env $envs LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/arb-state-$3.json" bash "$TMP/arbiter-driver.sh" "$ARBITER" '{"kind":"code","size":"bulk","task":"liveness-suite"}' 2>"$ARB_ERR")"
  ARB_RC=$?
}

arb_probe "$GATE" "$DEAD_URL" dead
if [[ $ARB_RC -eq 0 ]] \
   && printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=down' \
   && printf '%s\n' "$ARB_OUT" | grep -q 'freepool_gate=arm_down' \
   && ! printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=100' \
   && grep -q '^\[route-arbiter\] FREEPOOL ARM DOWN: gate refused arm_down (proxy unreachable) — NOT quota exhaustion' "$ARB_ERR"; then
  pass "arbiter names DEAD as a word: util_freepool=down + freepool_gate=arm_down + loud stderr"
else
  fail "arbiter names DEAD as a word: util_freepool=down + freepool_gate=arm_down + loud stderr" "rc=$ARB_RC out=$ARB_OUT err=$(cat "$ARB_ERR")"
fi

arb_probe "$GATE" "$STUB_URL" healthy
if [[ $ARB_RC -eq 0 ]] \
   && printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=0' \
   && ! printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=down' \
   && ! printf '%s\n' "$ARB_OUT" | grep -q 'freepool_gate=' \
   && ! grep -q 'FREEPOOL ARM DOWN' "$ARB_ERR"; then
  pass "arbiter healthy: util_freepool=0, no gate token, no ARM DOWN noise"
else
  fail "arbiter healthy: util_freepool=0, no gate token, no ARM DOWN noise" "rc=$ARB_RC out=$ARB_OUT err=$(cat "$ARB_ERR")"
fi

# Contrast: a gate_broken refusal (sick window, not a dead proxy) must stay a
# NUMBER plus its named token — sick-vs-dead is exactly the split that died
# when both rendered as 100.
cat > "$TMP/gate-broken-stub.sh" <<'EOF'
#!/usr/bin/env bash
printf 'LEADV2_DISPATCH_REFUSED: gate_broken\n' >&2
exit 1
EOF
arb_probe "$TMP/gate-broken-stub.sh" "" brokengate
if [[ $ARB_RC -eq 0 ]] \
   && printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=100' \
   && printf '%s\n' "$ARB_OUT" | grep -q 'freepool_gate=gate_broken' \
   && ! printf '%s\n' "$ARB_OUT" | grep -q 'util_freepool=down' \
   && ! grep -q 'FREEPOOL ARM DOWN' "$ARB_ERR"; then
  pass "arbiter contrast: gate_broken stays util_freepool=100 + freepool_gate=gate_broken (busy is a number, dead is the word)"
else
  fail "arbiter contrast: gate_broken stays util_freepool=100 + freepool_gate=gate_broken (busy is a number, dead is the word)" "rc=$ARB_RC out=$ARB_OUT err=$(cat "$ARB_ERR")"
fi

# ── Hermetic regression: configs untouched, nothing outside TMP written ────
if [[ "$(cfg_sha "$ROUTING")" == "$ROUTING_BEFORE" && "$(cfg_sha "$ARM_CFG")" == "$ARM_CFG_BEFORE" ]]; then
  pass "hermetic: routing.yaml and freepool-arm.yaml unmodified"
else
  fail "hermetic: routing.yaml and freepool-arm.yaml unmodified"
fi

printf 'freepool-liveness: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
