#!/usr/bin/env bash
# tests/test-provider-quota-gate.sh — QUOTA-GATE-PARITY-01
#
# Unit-tests leadv2-provider-quota-gate.sh directly against fixture quota-cache
# JSON and fixture/overridden ceilings, plus a static drift assertion between
# the three sources of truth for the six declared ceilings (routing yaml,
# leadv2-glm-policy-resolve.py DEFAULT_* constants, leadv2-quota-ceilings.sh).
#
# Isolation: LEADV2_QUOTA_LIVE points at a fake per-provider JSON emitter,
# LEADV2_QUOTA_CACHE_DIR is a scratch dir, ceiling env vars are overridden
# directly (leadv2-quota-ceilings.sh honors an already-exported value via
# ${VAR:-default}). No real HOME state, no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_ROOT="$(cd "${SCRIPTS_ROOT}/../config" && pwd)"
GATE_BIN="${SCRIPTS_ROOT}/leadv2-provider-quota-gate.sh"
GLM_GATE_BIN="${SCRIPTS_ROOT}/leadv2-glm-quota-gate.sh"
CODEX_LIB="${SCRIPTS_ROOT}/lib/leadv2-codex-quota-gate.sh"
CEILINGS_BIN="${CONFIG_ROOT}/leadv2-quota-ceilings.sh"
ROUTING_YAML="${CONFIG_ROOT}/leadv2-routing.yaml"
RESOLVE_PY="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1 -- ${2:-}"; }

unset LEADV2_PROVIDER_QUOTA_GATE LEADV2_CEIL_GLM_WORK LEADV2_CEIL_GLM_REVIEW \
      LEADV2_CEIL_CODEX_WORK LEADV2_CEIL_CODEX_REVIEW LEADV2_CEIL_CLAUDE_WORK \
      LEADV2_CEIL_CLAUDE_REVIEW LEADV2_QUOTA_TTL_GLM LEADV2_QUOTA_TTL_CODEX \
      LEADV2_QUOTA_TTL_ANTHROPIC

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
FIX="${tmp}/fixtures"; mkdir -p "$FIX"
CACHE="${tmp}/cache"; mkdir -p "$CACHE"

# fake quota-live: `fake-live.sh <provider>` echoes $FIX/<provider>.json
FAKE_LIVE="${tmp}/fake-live.sh"
cat > "$FAKE_LIVE" <<'EOF'
#!/usr/bin/env bash
provider="${1:-}"
f="${FAKE_LIVE_FIXDIR}/${provider}.json"
if [[ -n "${FAKE_LIVE_EXIT:-}" ]]; then exit "${FAKE_LIVE_EXIT}"; fi
if [[ -f "$f" ]]; then cat "$f"; else printf '{"status":"unknown"}'; fi
exit 0
EOF
chmod +x "$FAKE_LIVE"

write_fixture() { printf '%s' "$2" > "${FIX}/$1.json"; }  # <provider> <json>

run_gate() {  # <provider> <purpose> -- exports the shared env, prints stdout, sets RC
  local provider="$1" purpose="$2"
  OUT="$(FAKE_LIVE_FIXDIR="$FIX" \
    LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
    LEADV2_QUOTA_CACHE_DIR="$CACHE" \
    LEADV2_QUOTA_CEILINGS="${LEADV2_QUOTA_CEILINGS:-$CEILINGS_BIN}" \
    bash "$GATE_BIN" "$provider" "$purpose" 2>&1)"
  RC=$?
}

if bash -n "$GATE_BIN"; then pass "bash -n clean (leadv2-provider-quota-gate.sh)"; else fail "bash -n leadv2-provider-quota-gate.sh"; fi
if bash -n "$GLM_GATE_BIN"; then pass "bash -n clean (leadv2-glm-quota-gate.sh)"; else fail "bash -n leadv2-glm-quota-gate.sh"; fi
if bash -n "$CODEX_LIB"; then pass "bash -n clean (lib/leadv2-codex-quota-gate.sh)"; else fail "bash -n lib/leadv2-codex-quota-gate.sh"; fi
if bash -n "$CEILINGS_BIN"; then pass "bash -n clean (config/leadv2-quota-ceilings.sh)"; else fail "bash -n config/leadv2-quota-ceilings.sh"; fi

# ── S1 usage error ───────────────────────────────────────────────────────────
run_gate "bogus" "build"
[[ "$RC" == 3 ]] && pass "S1: bad provider -> rc 3" || fail "S1 provider" "rc=$RC out=$OUT"
run_gate "glm" "bogus"
[[ "$RC" == 3 ]] && pass "S1: bad purpose -> rc 3" || fail "S1 purpose" "rc=$RC out=$OUT"

# ── S2 kill switch ───────────────────────────────────────────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}}'
OUT="$(LEADV2_PROVIDER_QUOTA_GATE=0 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'gate disabled' <<<"$OUT" && pass "S2: kill switch -> rc 0, WARN" || fail "S2" "rc=$RC out=$OUT"

# ── S3 quota-live helper missing ─────────────────────────────────────────────
OUT="$(LEADV2_QUOTA_LIVE="${tmp}/does-not-exist.sh" LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: quota-live helper missing' <<<"$OUT" && pass "S3: missing live helper -> fail-open" || fail "S3" "rc=$RC out=$OUT"

# ── S4 quota-live exits non-zero ─────────────────────────────────────────────
OUT="$(FAKE_LIVE_EXIT=1 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: quota-live exited' <<<"$OUT" && pass "S4: live exits non-zero -> fail-open" || fail "S4" "rc=$RC out=$OUT"

# ── S5 malformed JSON ────────────────────────────────────────────────────────
write_fixture glm '{not json'
run_gate glm build
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: malformed glm JSON' <<<"$OUT" && pass "S5: malformed JSON -> fail-open" || fail "S5" "rc=$RC out=$OUT"

# ── S6 status != ok ──────────────────────────────────────────────────────────
write_fixture glm '{"status":"error","error":"network down"}'
run_gate glm build
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: glm quota read is unknown' <<<"$OUT" && pass "S6: status!=ok -> fail-open" || fail "S6" "rc=$RC out=$OUT"

# ── S7 stale cache (age > 2x TTL) ────────────────────────────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":95},"weekly":{"pct":95}}'  # would refuse if read
: > "${CACHE}/glm.json"
old_ts="$(( $(date +%s) - 1000 ))"
touch -t "$(date -r "$old_ts" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@${old_ts}" +%Y%m%d%H%M.%S)" "${CACHE}/glm.json" 2>/dev/null || true
run_gate glm build
if [[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: glm quota-cache stale' <<<"$OUT"; then
  pass "S7: stale cache -> fail-open even though live pct would refuse"
else
  fail "S7" "rc=$RC out=$OUT"
fi
rm -f "${CACHE}/glm.json"

# ── S8 pct < ceiling: allow ──────────────────────────────────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":20}}'
run_gate glm build
[[ "$RC" == 0 ]] && grep -q 'OK — glm' <<<"$OUT" && pass "S8: pct < ceiling -> allow" || fail "S8" "rc=$RC out=$OUT"

# ── S9 pct >= ceiling: refuse ────────────────────────────────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":85},"weekly":{"pct":10}}'  # default glm build ceiling 80
run_gate glm build
[[ "$RC" == 1 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' <<<"$OUT" && grep -q 'REROUTE' <<<"$OUT" \
  && pass "S9: pct >= ceiling -> refuse rc 1" || fail "S9" "rc=$RC out=$OUT"

# ── S10 limit_reached true, no numeric pct (codex) ──────────────────────────
write_fixture codex '{"status":"ok","binding_window":"weekly","windows":[{"kind":"weekly","limit_reached":true,"used_percent":null}]}'
run_gate codex review
[[ "$RC" == 1 ]] && grep -q 'limit_reached' <<<"$OUT" && pass "S10: limit_reached forces pct=100 -> refuse" || fail "S10" "rc=$RC out=$OUT"

# claude ok fixture used by boundary rows below
write_fixture claude '{"status":"ok","accounts":[{"active":true,"seven_day_pct":50,"five_hour_pct":10}]}'

# ── boundary: ceiling 0 -> every read trips ─────────────────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":0},"weekly":{"pct":0}}'
OUT="$(LEADV2_CEIL_GLM_WORK=0 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
  bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 1 ]] && pass "boundary: ceiling=0 refuses even a 0% read" || fail "boundary ceiling=0" "rc=$RC out=$OUT"

# ── boundary: ceiling > 100 -> never trips, WARN inert ──────────────────────
write_fixture glm '{"status":"ok","five_hour":{"pct":100},"weekly":{"pct":100}}'
OUT="$(LEADV2_CEIL_GLM_WORK=150 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
  bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'gate is inert' <<<"$OUT" && pass "boundary: ceiling>100 never trips, WARN inert" || fail "boundary ceiling>100" "rc=$RC out=$OUT"

# ── boundary: non-numeric ceiling -> fail-open ──────────────────────────────
OUT="$(LEADV2_CEIL_GLM_WORK=abc FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_QUOTA_CACHE_DIR="$CACHE" \
  bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: malformed ceiling' <<<"$OUT" && pass "boundary: non-numeric ceiling -> fail-open" || fail "boundary non-numeric" "rc=$RC out=$OUT"

# ── boundary: ceilings file missing -> fail-open ────────────────────────────
OUT="$(LEADV2_QUOTA_CEILINGS="${tmp}/nope.sh" FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q "FAIL-OPEN: ceilings file missing (${tmp}/nope.sh)" <<<"$OUT" && pass "boundary: ceilings file missing names expected path -> fail-open" || fail "boundary ceilings missing" "rc=$RC out=$OUT"

# ── QUOTA-GATE-PARITY-01 fix round 2 ─────────────────────────────────────────

# F4a: timeout=abc -> fallback 8s with a named warn, gate completes.
write_fixture glm '{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}}'
OUT="$(LEADV2_QUOTA_READ_TIMEOUT=abc FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q "LEADV2_QUOTA_READ_TIMEOUT='abc'" <<<"$OUT" && grep -q 'default 8s' <<<"$OUT" \
  && pass "F4a: timeout=abc -> rc 0, warn names the 8s fallback" || fail "F4a" "rc=$RC out=$OUT"

# F4b: timeout=99999 -> clamped to 60s with a named warn; completes promptly.
_F4B_T0="$(date +%s)"
OUT="$(LEADV2_QUOTA_READ_TIMEOUT=99999 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
_F4B_DT=$(( $(date +%s) - _F4B_T0 ))
[[ "$RC" == 0 ]] && grep -q 'clamped to 60s' <<<"$OUT" && (( _F4B_DT < 10 )) \
  && pass "F4b: timeout=99999 -> clamped to 60s, completed in ${_F4B_DT}s" \
  || fail "F4b" "rc=$RC dt=${_F4B_DT}s out=$OUT"

# F4c: timeout=0 -> clamped to 1s and the gate still evaluates (OK line).
OUT="$(LEADV2_QUOTA_READ_TIMEOUT=0 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" glm build 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'clamped to 1s' <<<"$OUT" && grep -q 'OK — glm' <<<"$OUT" \
  && pass "F4c: timeout=0 -> clamped to 1s, gate still evaluates" || fail "F4c" "rc=$RC out=$OUT"

# §4a: limit_reached must refuse EVEN under an inert (>100) ceiling — the
# block signal short-circuits the pct>=ceil comparison instead of losing it.
write_fixture codex '{"status":"ok","limit_reached":true,"binding_window":"primary","windows":[{"kind":"primary","used_percent":4}]}'
OUT="$(LEADV2_CEIL_CODEX_WORK=150 FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" \
  LEADV2_QUOTA_CACHE_DIR="$CACHE" bash "$GATE_BIN" codex build 2>&1)"; RC=$?
[[ "$RC" == 1 ]] && grep -q 'limit_reached' <<<"$OUT" \
  && pass "§4a: limit_reached refuses even with inert ceiling 150 (rc 1)" \
  || fail "§4a inert-ceiling limit_reached" "rc=$RC out=$OUT"

# F3a: GLM_QUOTA_THRESHOLD=abc against the GLM gate — fallback 80 named, rc 0
# (never rc 2: rc 2 is the peak-hours refusal and must not be reachable by a
# config typo). Clock forced out of peak.
GLM_COOLDOWN="$tmp/glm-cooldown"; mkdir -p "$GLM_COOLDOWN"
write_fixture glm '{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}}'
OUT="$(GLM_SIMULATE_UTC_HOUR=12 GLM_QUOTA_THRESHOLD=abc FAKE_LIVE_FIXDIR="$FIX" \
  LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_ARM_COOLDOWN_DIR="$GLM_COOLDOWN" \
  bash "$GLM_GATE_BIN" 2>&1)"; RC=$?
[[ "$RC" != 2 ]] && grep -q 'falling back to 80' <<<"$OUT" \
  && pass "F3a: GLM_QUOTA_THRESHOLD=abc -> warn + fallback 80, never rc 2 (rc=$RC)" \
  || fail "F3a" "rc=$RC out=$OUT"

# F3b: same defect via LEADV2_CEIL_GLM_WORK=abc; a genuinely high reading then
# reroutes by the 80 fallback (rc 1), still never rc 2.
write_fixture glm '{"status":"ok","five_hour":{"pct":85},"weekly":{"pct":10}}'
OUT="$(GLM_SIMULATE_UTC_HOUR=12 LEADV2_CEIL_GLM_WORK=abc FAKE_LIVE_FIXDIR="$FIX" \
  LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_ARM_COOLDOWN_DIR="$GLM_COOLDOWN" \
  bash "$GLM_GATE_BIN" 2>&1)"; RC=$?
[[ "$RC" == 1 ]] && grep -q 'falling back to 80' <<<"$OUT" && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' <<<"$OUT" \
  && pass "F3b: LEADV2_CEIL_GLM_WORK=abc + 85% read -> reroute by fallback 80 (rc 1)" \
  || fail "F3b" "rc=$RC out=$OUT"

# F3 twin: five_hour.pct absent from an otherwise ok payload -> python prints
# the literal None -> non-numeric fail-open (rc 0), never a bash abort.
write_fixture glm '{"status":"ok","five_hour":{},"weekly":{"pct":10}}'
OUT="$(GLM_SIMULATE_UTC_HOUR=12 FAKE_LIVE_FIXDIR="$FIX" \
  LEADV2_QUOTA_LIVE="$FAKE_LIVE" LEADV2_ARM_COOLDOWN_DIR="$GLM_COOLDOWN" \
  bash "$GLM_GATE_BIN" 2>&1)"; RC=$?
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: GLM quota read is non-numeric' <<<"$OUT" \
  && pass "F3c: five_hour.pct absent -> non-numeric fail-open, no abort" \
  || fail "F3c" "rc=$RC out=$OUT"

# F1: top-level limit_reached must OR ahead of the binding window's pct —
# today the window's used_percent=4 returns early past the top-level true.
write_fixture codex '{"status":"ok","limit_reached":true,"binding_window":"primary","windows":[{"kind":"primary","used_percent":4}]}'
F1_PY="$(FAKE_LIVE_FIXDIR="$FIX" LEADV2_QUOTA_LIVE="$FAKE_LIVE" python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("resolve", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.live_codex_weekly_pct(sys.argv[2]))
' "$RESOLVE_PY" "$FAKE_LIVE" 2>&1)"
[[ "$F1_PY" == "100.0" ]] \
  && pass "F1: top-level limit_reached ORs ahead of binding-window pct (100.0)" \
  || fail "F1 top-level limit_reached" "got='$F1_PY'"

# ── claude review passes under ceiling ──────────────────────────────────────
run_gate claude review
[[ "$RC" == 0 ]] && pass "claude review under ceiling -> allow" || fail "claude review" "rc=$RC out=$OUT"

# ── drift assertion: yaml / python DEFAULT_* / ceilings.sh must agree, except
# the documented codex-build 80(py)/90(yaml+ceilings) exception ─────────────
drift_val_yaml_glm_work="$(sed -n 's/.*glm: *{ *work_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"
drift_val_yaml_glm_review="$(sed -n 's/.*glm: *{ *work_pct: *[0-9]*, *review_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"
drift_val_yaml_codex_work="$(sed -n 's/.*codex: *{ *work_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"
drift_val_yaml_codex_review="$(sed -n 's/.*codex: *{ *work_pct: *[0-9]*, *review_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"
drift_val_yaml_claude_work="$(sed -n 's/.*claude: *{ *work_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"
drift_val_yaml_claude_review="$(sed -n 's/.*claude: *{ *work_pct: *[0-9]*, *review_pct: *\([0-9]*\).*/\1/p' "$ROUTING_YAML" | head -1)"

drift_py_codex_build="$(sed -n 's/^DEFAULT_BUILD_THRESHOLD_PCT = \([0-9.]*\).*/\1/p' "$RESOLVE_PY" | head -1)"
drift_py_codex_review="$(sed -n 's/^DEFAULT_REVIEW_THRESHOLD_PCT = \([0-9.]*\).*/\1/p' "$RESOLVE_PY" | head -1)"
drift_py_glm_review="$(sed -n 's/^DEFAULT_GLM_REVIEW_THRESHOLD_PCT = \([0-9.]*\).*/\1/p' "$RESOLVE_PY" | head -1)"
drift_py_claude_review="$(sed -n 's/^DEFAULT_ANTHROPIC_REVIEW_THRESHOLD_PCT = \([0-9.]*\).*/\1/p' "$RESOLVE_PY" | head -1)"

(
  source "$CEILINGS_BIN"
  ok=1
  [[ "${LEADV2_CEIL_GLM_WORK}" == "${drift_val_yaml_glm_work}" ]] || ok=0
  [[ "${LEADV2_CEIL_GLM_REVIEW}" == "${drift_val_yaml_glm_review}" ]] || ok=0
  [[ "${LEADV2_CEIL_GLM_REVIEW}" == "${drift_py_glm_review%.*}" ]] || ok=0
  [[ "${LEADV2_CEIL_CODEX_WORK}" == "${drift_val_yaml_codex_work}" ]] || ok=0
  [[ "${LEADV2_CEIL_CODEX_REVIEW}" == "${drift_val_yaml_codex_review}" ]] || ok=0
  [[ "${LEADV2_CEIL_CODEX_REVIEW}" == "${drift_py_codex_review%.*}" ]] || ok=0
  [[ "${LEADV2_CEIL_CLAUDE_WORK}" == "${drift_val_yaml_claude_work}" ]] || ok=0
  [[ "${LEADV2_CEIL_CLAUDE_REVIEW}" == "${drift_val_yaml_claude_review}" ]] || ok=0
  [[ "${LEADV2_CEIL_CLAUDE_REVIEW}" == "${drift_py_claude_review%.*}" ]] || ok=0
  # documented exception: codex build 80 (py) vs 90 (yaml + ceilings.sh)
  [[ "${drift_py_codex_build%.*}" == "80" ]] || ok=0
  [[ "${LEADV2_CEIL_CODEX_WORK}" == "90" ]] || ok=0
  exit $(( ok == 1 ? 0 : 1 ))
)
if [[ $? -eq 0 ]]; then
  pass "drift: yaml/py/ceilings.sh agree on 5 of 6 values; codex-build exception (80py/90yaml) confirmed by name"
else
  fail "drift: unexpected disagreement between quota-ceiling sources" \
    "yaml_glm=${drift_val_yaml_glm_work}/${drift_val_yaml_glm_review} yaml_codex=${drift_val_yaml_codex_work}/${drift_val_yaml_codex_review} yaml_claude=${drift_val_yaml_claude_work}/${drift_val_yaml_claude_review} py_codex_build=${drift_py_codex_build} py_codex_review=${drift_py_codex_review} py_glm_review=${drift_py_glm_review} py_claude_review=${drift_py_claude_review}"
fi

# A missing generic codex gate is control-plane breakage, not evidence that a
# quota threshold was exceeded.  The wrapper must refuse loudly and name the
# exact dependency path so an operator can repair it.
BROKEN_GATE_ROOT="${tmp}/broken-codex-gate"; mkdir -p "${BROKEN_GATE_ROOT}/lib"
cp "$CODEX_LIB" "${BROKEN_GATE_ROOT}/lib/leadv2-codex-quota-gate.sh"
cat > "${BROKEN_GATE_ROOT}/lib/leadv2-arm-cooldown.sh" <<'EOF'
arm_cooldown_state() { printf 'idle\n'; }
EOF
cat > "${BROKEN_GATE_ROOT}/lib/leadv2-codex-circuit.sh" <<'EOF'
codex_circuit_state() { printf 'closed\n'; }
EOF
GATE_BROKEN_OUT="$(source "${BROKEN_GATE_ROOT}/lib/leadv2-codex-quota-gate.sh"; codex_spawn_gate exec 2>&1)"; RC=$?
[[ "$RC" == 2 ]] && grep -q 'CODEX_REFUSED_QUOTA reason=gate_broken' <<<"$GATE_BROKEN_OUT" \
  && grep -Fq "${BROKEN_GATE_ROOT}/leadv2-provider-quota-gate.sh" <<<"$GATE_BROKEN_OUT" \
  && ! grep -q 'reason=threshold' <<<"$GATE_BROKEN_OUT" \
  && pass "missing provider gate refuses gate_broken with its exact path, never threshold" \
  || fail "missing provider gate" "rc=$RC out=$GATE_BROKEN_OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
