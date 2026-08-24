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
[[ "$RC" == 0 ]] && grep -q 'FAIL-OPEN: ceilings file missing' <<<"$OUT" && pass "boundary: ceilings file missing -> fail-open" || fail "boundary ceilings missing" "rc=$RC out=$OUT"

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

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
