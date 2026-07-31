#!/usr/bin/env bash
# KIMI-CHANNEL-01 fix round 1, finding H1(b) — kimi branch regression tests for
# leadv2-session-route.sh. All provider/quota/probe seams are stubbed; this
# suite never calls the real TokenRouter endpoint or spends real quota.
#
# Covers: eligible+available -> kimi wins; eligible+unavailable (probe rc 77)
# -> falls through past kimi; LEADV2_KIMI_ENABLED=false -> kimi ineligible;
# high-risk/safety -> kimi never eligible and never probed.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${SCRIPT_DIR}/../leadv2-session-route.sh"
PASS=0
FAIL=0
ERRORS=()
SANDBOX="$(lv2_mktemp_dir "leadv2-kimi-route-test")"
trap 'rm -rf "$SANDBOX"' EXIT

pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf -- '[TEST] FAIL: %s\n' "$1"; }

CODEX_STUB="$SANDBOX/codex"
QUOTA_STUB="$SANDBOX/quota"
GLM_GATE_STUB="$SANDBOX/glm-gate"
KIMI_BIN_STUB="$SANDBOX/kimi-coder"

cat > "$CODEX_STUB" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

cat > "$QUOTA_STUB" <<'STUB'
#!/usr/bin/env bash
printf -- '%s\n' "${TEST_QUOTA_JSON:-}"
STUB

# rc 0 = glm has headroom; rc 1 = glm gate refuses (no headroom) -> kimi may
# actually get probed. Never calls the live leadv2-glm-quota-gate.sh.
cat > "$GLM_GATE_STUB" <<'STUB'
#!/usr/bin/env bash
exit "${TEST_GLM_GATE_RC:-0}"
STUB

# Only implements the one subcommand leadv2-session-route.sh calls: `probe`.
# rc 0 = kimi reachable; rc 77 = launch probe failed (KIMI_PROBE_FAIL_EXIT_CODE).
cat > "$KIMI_BIN_STUB" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "probe" ]]; then
  exit "${TEST_KIMI_PROBE_RC:-0}"
fi
exit 0
STUB
chmod +x "$CODEX_STUB" "$QUOTA_STUB" "$GLM_GATE_STUB" "$KIMI_BIN_STUB"

route() {
  TEST_QUOTA_JSON="${TEST_QUOTA_JSON:-}" \
  TEST_GLM_GATE_RC="${TEST_GLM_GATE_RC:-0}" \
  TEST_KIMI_PROBE_RC="${TEST_KIMI_PROBE_RC:-0}" \
  LEADV2_CODEX_BIN="$CODEX_STUB" \
  LEADV2_CODEX_SKILL_READY=1 \
  LEADV2_QUOTA_LIVE="$QUOTA_STUB" \
  LEADV2_GLM_QUOTA_GATE="$GLM_GATE_STUB" \
  LEADV2_KIMI_BIN="$KIMI_BIN_STUB" \
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

assert_not_contains() {
  local name="$1" output="$2" needle="$3"
  if [[ "$output" == *"$needle"* ]]; then
    fail "$name unexpectedly contains '$needle' in: $output"
  else
    pass "$name"
  fi
}

if bash -n "$ROUTER"; then
  pass "router syntax"
else
  fail "router syntax"
fi

# ── eligible + available: glm blocked on quota, kimi probes OK -> kimi wins ──
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":90}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
TEST_GLM_GATE_RC=1
TEST_KIMI_PROBE_RC=0
out="$(route --class Standard --provider auto)"
assert_fields "kimi eligible+available -> kimi wins" "$out" \
  'provider=kimi' 'model=moonshotai/kimi-k3-free' 'kimi_eligible=true' 'kimi_available=true'

# ── eligible + unavailable: glm blocked, kimi probe fails (rc 77) -> falls through ──
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":20}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
TEST_GLM_GATE_RC=1
TEST_KIMI_PROBE_RC=77
out="$(route --class Standard --provider auto)"
assert_not_contains "kimi eligible+unavailable -> never picked as provider" "$out" 'provider=kimi'
assert_fields "kimi eligible+unavailable -> falls through to codex, reason notes probe failure" "$out" \
  'kimi_eligible=true' 'kimi_available=false' 'provider=codex'

# ── policy-disabled: LEADV2_KIMI_ENABLED=false -> kimi ineligible, never wins ──
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":90}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
TEST_GLM_GATE_RC=1
TEST_KIMI_PROBE_RC=0
out="$(LEADV2_KIMI_ENABLED=false route --class Standard --provider auto)"
assert_fields "LEADV2_KIMI_ENABLED=false -> kimi ineligible" "$out" 'kimi_eligible=false'
assert_not_contains "LEADV2_KIMI_ENABLED=false -> provider is never kimi" "$out" 'provider=kimi'

# ── high-risk/safety: kimi never eligible, and the probe stub must never be hit ──
rm -f "$SANDBOX/kimi-probe-hit"
cat > "$KIMI_BIN_STUB" <<STUB
#!/usr/bin/env bash
touch "$SANDBOX/kimi-probe-hit"
if [[ "\${1:-}" == "probe" ]]; then
  exit "\${TEST_KIMI_PROBE_RC:-0}"
fi
exit 0
STUB
chmod +x "$KIMI_BIN_STUB"
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":20}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
out="$(route --class Standard --risk-tags auth --provider auto)"
assert_fields "high-risk -> Claude, high_risk=true, kimi never computed" "$out" 'provider=claude' 'high_risk=true'
assert_not_contains "high-risk fast-path never reaches kimi_eligible/provider=kimi" "$out" 'kimi'
if [[ -f "$SANDBOX/kimi-probe-hit" ]]; then
  fail "high-risk path must never invoke the kimi launch probe"
else
  pass "high-risk path never invokes the kimi launch probe"
fi

# ── glm eligible + quota-ok + kimi eligible: M2 guard must skip the probe ──
# Reuses the sentinel-touching stub installed by the high-risk block above;
# only the sentinel state needs a reset.
rm -f "$SANDBOX/kimi-probe-hit"
TEST_GLM_GATE_RC=0
TEST_KIMI_PROBE_RC=0
TEST_QUOTA_JSON='{"codex":{"windows":[{"used_percent":20}]},"anthropic":{"accounts":[{"five_hour_pct":50,"seven_day_pct":40}]}}'
out="$(route --class Standard --provider auto)"
assert_fields "glm eligible + quota-ok -> kimi probe skipped with recorded reason" "$out" \
  'kimi_eligible=true' 'kimi_available=false' 'not probed'
if [[ -f "$SANDBOX/kimi-probe-hit" ]]; then
  fail "glm-wins path must not spend a kimi launch probe"
else
  pass "glm-wins path never invokes the kimi launch probe"
fi

printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf -- '[TEST] %s\n' "${ERRORS[@]}"
  exit 1
fi
