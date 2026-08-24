#!/usr/bin/env bash
# Deterministic provider/model router tests. All provider and quota probes are
# stubbed; this suite never calls a real model or consumes subscription quota.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${SCRIPT_DIR}/../leadv2-session-route.sh"
PASS=0
FAIL=0
ERRORS=()
SANDBOX="$(lv2_mktemp_dir "leadv2-route-test")"
trap 'rm -rf "$SANDBOX"' EXIT

pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf -- '[TEST] FAIL: %s\n' "$1"; }

CODEX_STUB="$SANDBOX/codex"
QUOTA_STUB="$SANDBOX/quota"
GLM_GATE_OK_STUB="$SANDBOX/glm-gate-ok"
GLM_GATE_REFUSE_STUB="$SANDBOX/glm-gate-refuse"

cat > "$CODEX_STUB" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  exit 0
fi
exit 0
STUB

cat > "$QUOTA_STUB" <<'STUB'
#!/usr/bin/env bash
printf -- '%s\n' "${TEST_QUOTA_JSON:-}"
STUB

# GLM-FIRST-01 (2026-07-16): auto-mode routes to GLM first when eligible+quota-OK, so
# every case below must pin the GLM quota gate rather than let the router shell out to
# the REAL leadv2-glm-quota-gate.sh -- this file's own header promises "All provider and
# quota probes are stubbed; this suite never calls a real model or consumes subscription
# quota," and the unstubbed gate silently broke that promise (discovered live during
# PLUGIN-RACING-RESERVE-01: every auto-route case returned provider=glm regardless of
# scenario, driven by whatever the real subscription's quota happened to be that run).
cat > "$GLM_GATE_OK_STUB" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

cat > "$GLM_GATE_REFUSE_STUB" <<'STUB'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate' >&2
exit 1
STUB
chmod +x "$CODEX_STUB" "$QUOTA_STUB" "$GLM_GATE_OK_STUB" "$GLM_GATE_REFUSE_STUB"

route() {
  TEST_QUOTA_JSON="${TEST_QUOTA_JSON:-}" \
  LEADV2_CODEX_BIN="$CODEX_STUB" \
  LEADV2_CODEX_SKILL_READY=1 \
  LEADV2_QUOTA_LIVE="$QUOTA_STUB" \
  LEADV2_GLM_QUOTA_GATE="${LEADV2_GLM_QUOTA_GATE:-$GLM_GATE_OK_STUB}" \
  LEADV2_KIMI_ENABLED="${LEADV2_KIMI_ENABLED:-0}" \
    "$ROUTER" "$@"
}

assert_fields() {
  local name="$1" output="$2"
  shift 2
  local expected
  for expected in "$@"; do
    if [[ "$output" != *"$expected"* ]]; then
      fail "$name missing '$expected' in: $output"
      return
    fi
  done
  pass "$name"
}

if bash -n "$ROUTER"; then
  pass "router syntax"
else
  fail "router syntax"
fi

TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":20}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
out="$(route --class Standard --provider auto)"
assert_fields "routine Standard -> GLM (GLM-FIRST-01)" "$out" \
  'provider=glm' 'model=glm-5.3' 'effort=medium'

out="$(route --class Light --provider auto)"
assert_fields "Light -> GLM (GLM-FIRST-01)" "$out" \
  'provider=glm' 'model=glm-5.3' 'effort=low'

out="$(route --class Heavy --provider auto)"
assert_fields "Heavy -> Claude Opus" "$out" \
  'provider=claude' 'model=opus' 'effort=high' 'high_risk=true'

out="$(route --class Standard --risk-tags auth --provider codex)"
assert_fields "high-risk tag blocks explicit Codex" "$out" \
  'provider=claude' 'model=opus' 'high_risk=true'

# GLM-FIRST-01 means GLM (and, if enabled, kimi) win auto-routing whenever they are
# eligible+available, so a fallback-to-Claude assertion only actually exercises the
# codex-quota/codex-missing branch if GLM is made unavailable here too -- otherwise the
# router never reaches the codex check at all and the fallback chain isn't observed.
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":90}]}}'
out="$(LEADV2_GLM_QUOTA_GATE="$GLM_GATE_REFUSE_STUB" route --class Standard --provider auto)"
assert_fields "Codex quota threshold -> Claude fallback (GLM+kimi unavailable)" "$out" \
  'provider=claude' 'model=sonnet' 'codex_used_percent=90' 'reached policy threshold'

TEST_QUOTA_JSON='{}'
out="$(LEADV2_CODEX_BIN="$SANDBOX/missing-codex" LEADV2_CODEX_SKILL_READY=1 \
  LEADV2_QUOTA_LIVE="$QUOTA_STUB" LEADV2_GLM_QUOTA_GATE="$GLM_GATE_REFUSE_STUB" \
  LEADV2_KIMI_ENABLED=0 "$ROUTER" --class Standard --provider auto)"
assert_fields "missing Codex CLI -> Claude fallback (GLM+kimi unavailable)" "$out" \
  'provider=claude' 'model=sonnet' 'codex binary unavailable'

out="$(route --class Standard --provider claude)"
assert_fields "explicit Claude override" "$out" \
  'provider=claude' 'model=sonnet' 'explicit provider override: claude'

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf -- '[TEST] %s\n' "${ERRORS[@]}"
  exit 1
fi
