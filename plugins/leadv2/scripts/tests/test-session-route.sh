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

# HEAVY-TIER-VS-SAFETY-OPUS-01: the Heavy (think-tier) cases must be deterministic.
# The live resolver (leadv2-router.sh think-model) needs python3+PyYAML to read
# model-capability.yaml; without PyYAML (e.g. a bare Linux container) it degrades
# to the documented opus fallback, which made 'model=fable' platform-dependent.
# Stub the resolver via its own documented test hook (leadv2-think-model.sh
# honours LEADV2_TEST_ROUTER) — same stubbing discipline as the GLM gate above.
THINK_MODEL_STUB="$SANDBOX/think-router"
cat > "$THINK_MODEL_STUB" <<'STUB'
#!/usr/bin/env bash
# test stub: stand in for `leadv2-router.sh think-model`
printf 'fable\n'
STUB
chmod +x "$CODEX_STUB" "$QUOTA_STUB" "$GLM_GATE_OK_STUB" "$GLM_GATE_REFUSE_STUB" "$THINK_MODEL_STUB"

route() {
  TEST_QUOTA_JSON="${TEST_QUOTA_JSON:-}" \
  LEADV2_CODEX_BIN="$CODEX_STUB" \
  LEADV2_CODEX_SKILL_READY=1 \
  LEADV2_QUOTA_LIVE="$QUOTA_STUB" \
  LEADV2_GLM_QUOTA_GATE="${LEADV2_GLM_QUOTA_GATE:-$GLM_GATE_OK_STUB}" \
  LEADV2_KIMI_ENABLED="${LEADV2_KIMI_ENABLED:-0}" \
  LEADV2_TEST_ROUTER="${LEADV2_TEST_ROUTER:-$THINK_MODEL_STUB}" \
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

# HEAVY-TIER-VS-SAFETY-OPUS-01: Heavy-as-a-class is the THINK tier since
# FABLE-THINK-TIER-01 R4 (see PLANNER-MODELS-DECISION-01, leadv2.md:74-75) —
# the Claude arm resolves through the think-model resolver (fable; opus only
# as the resolver's own fallback). The old 'model=opus' assertion was stale
# doctrine from when CLAUDE_HEAVY_MODEL was hard-pinned to opus.
out="$(route --class Heavy --provider auto)"
assert_fields "Heavy (think tier) -> Claude fable" "$out" \
  'provider=claude' 'model=fable' 'effort=high' 'high_risk=true'

# HEAVY-TIER-VS-SAFETY-OPUS-01: a TAG-forced high-risk route is a SAFETY route,
# pinned to opus regardless of the think tier (leadv2.md:82 "Opus (Heavy or
# safety verdict)", leadv2.md:142, model-routing.md:30).
out="$(route --class Standard --risk-tags auth --provider codex)"
assert_fields "high-risk tag blocks explicit Codex" "$out" \
  'provider=claude' 'model=opus' 'high_risk=true'

# HEAVY-TIER-VS-SAFETY-OPUS-01 R2 (lead adjudication, fix-round-2.md): safety
# OUTRANKS the think tier. A Heavy class with a hard-safety tag (auth,rls,
# safety,publish,security) pins opus — a pin that yields to the class check is
# not a pin.
out="$(route --class Heavy --risk-tags safety --provider auto)"
assert_fields "Heavy + safety tag -> opus (safety outranks think tier)" "$out" \
  'provider=claude' 'model=opus' 'high_risk=true'

# ...but 'arch' is carved out: it names difficulty, not consequence, and
# PLANNER-MODELS-DECISION-01 deliberately pins Heavy planning/architecture to
# the think tier. Heavy + arch (and no other high-risk tag) keeps the think arm.
out="$(route --class Heavy --risk-tags arch --provider auto)"
assert_fields "Heavy + arch tag stays think-tier (arch carve-out)" "$out" \
  'provider=claude' 'model=fable' 'high_risk=true'

# On a non-Heavy class both tag kinds keep round-1 behaviour (safety pin).
out="$(route --class Standard --risk-tags safety --provider codex)"
assert_fields "Standard + safety tag pins opus" "$out" \
  'provider=claude' 'model=opus' 'high_risk=true'
out="$(route --class Standard --risk-tags arch --provider codex)"
assert_fields "Standard + arch tag pins opus" "$out" \
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
