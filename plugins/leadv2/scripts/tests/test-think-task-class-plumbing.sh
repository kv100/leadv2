#!/usr/bin/env bash
# THINK-CLASS-PLUMBING-01: the real admission class must reach the shared
# think resolver.  The two invocations below are resolver-only (no spawn):
# Heavy selects the codex/terra matrix tier while Strategic selects the
# astra/fable/sol tier; dropping the inherited class collapses Strategic to
# the compatibility default Heavy tier.
# run-all-triggers: leadv2-router.sh leadv2-think-model.sh leadv2-dispatch-code.sh leadv2-fanout-classify.sh leadv2-llm-judge.sh leadv2-session-route.sh model-capability.yaml leadv2-routing.yaml
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTER="${SCRIPTS_DIR}/leadv2-router.sh"
WRAPPER="${SCRIPTS_DIR}/lib/leadv2-think-model.sh"
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/test-think-task-class-plumbing.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

cat >"$TMP/quota.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":10,"seven_day_pct":10}]}}'
EOF
chmod +x "$TMP/quota.sh"

cat >"$TMP/routing.yaml" <<'EOF'
router_v2:
  quota_ceilings:
    codex: { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  capability_matrix:
    - { arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, cost: 1, kinds: [plan], sizes: [heavy], think_tiers: [heavy], review: true, protected: true, capability: 4 }
    - { arm: opus, provider: claude, model: opus, tier: high, cost: 2, kinds: [plan], sizes: [heavy], think_tiers: [heavy], review: true, protected: true, capability: 5 }
    - { arm: astra, provider: codex, model: gpt-6-astra, tier: astra, cost: 1, kinds: [plan], sizes: [heavy], think_tiers: [strategic], review: true, protected: true, capability: 6 }
    - { arm: sol, provider: codex, model: gpt-5.6-sol, tier: top, cost: 2, kinds: [plan], sizes: [heavy], think_tiers: [strategic], review: true, protected: true, capability: 5 }
    - { arm: fable, provider: claude, model: fable, tier: high, cost: 3, kinds: [plan], sizes: [heavy], think_tiers: [strategic], review: true, protected: true, capability: 6 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - { kinds: [plan], effort: high }
EOF

cat >"$TMP/capability.yaml" <<'EOF'
codex: { model_id: gpt-5.6-terra }
opus: { model_id: opus }
astra: { model_id: gpt-6-astra }
sol: { model_id: gpt-5.6-sol }
fable: { model_id: fable }
think_stakes:
  default_class: heavy
  classes:
    heavy: { size: heavy, complexity: complex, think_tier: heavy }
    strategic: { size: heavy, complexity: complex, think_tier: strategic }
EOF

resolve() { # $1=class or '-' -> stdout arm
  local class="$1"
  local -a envs=(
    env -u LEADV2_THINK_MODEL -u LEADV2_THINK_CLASS -u LEADV2_THINK_ROLE -u LEADV2_THINK_TASK_ID -u LEADV2_TASK_ID
    LEADV2_TEST_CONTEXT=1 LEADV2_TEST_ROUTER="$ROUTER"
    LEADV2_MODEL_CAPABILITY_YAML="$TMP/capability.yaml"
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml"
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/quota.sh"
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state"
    LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/arbiter.jsonl"
    LEADV2_THINK_DECISIONS_FILE="$TMP/think.log")
  if [[ "$class" == "-" ]]; then
    "${envs[@]}" bash "$WRAPPER"
  else
    "${envs[@]}" LEADV2_TASK_CLASS="$class" bash "$WRAPPER"
  fi
}

heavy="$(resolve Heavy)"
strategic="$(resolve Strategic)"
collapsed="$(resolve -)"
if [[ "$heavy" == "codex" && "$strategic" == "astra" && "$heavy" != "$strategic" ]]; then
  pass "no-spawn class resolves differ: Heavy=codex/terra, Strategic=astra"
else
  fail "expected Heavy=codex and Strategic=astra, got Heavy='$heavy' Strategic='$strategic'"
fi
if [[ "$collapsed" == "$heavy" && "$collapsed" != "$strategic" ]]; then
  pass "negative control: removing LEADV2_TASK_CLASS collapses Strategic to default Heavy ($collapsed)"
else
  fail "class-plumbing negative control did not collapse: Heavy='$heavy' Strategic='$strategic' no-class='$collapsed'"
fi
if grep -q 'class=Heavy arm=codex' "$TMP/think.log" \
   && grep -q 'class=Strategic arm=astra' "$TMP/think.log"; then
  pass "think_model_resolved records the inherited real task class on the census surface"
else
  fail "missing class-bearing resolver rows: $(tr '\n' '|' < "$TMP/think.log")"
fi

# A broken config used to be collapsed into stakes_or_data_missing.  The exact
# fail-open reason now identifies the input surface that needs repair.
missing="$(env LEADV2_TEST_CONTEXT=1 LEADV2_THINK_MODEL=fable \
  LEADV2_THINK_DECISIONS_FILE="$TMP/missing.log" \
  LEADV2_MODEL_CAPABILITY_YAML="$TMP/capability.yaml" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/no-routing.yaml" \
  bash "$ROUTER" think-model --class Heavy 2>/dev/null)"
if [[ "$missing" == "fable" ]] && grep -q 'reason=fail_open_env_candidate_think_config_unreadable' "$TMP/missing.log"; then
  pass "fail-open distinguishes unreadable routing/config input from class or matrix data"
else
  fail "expected precise config fail-open reason, got arm='$missing' row='$(tail -1 "$TMP/missing.log" 2>/dev/null)'"
fi

printf 'SUMMARY: %s pass, %s fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
