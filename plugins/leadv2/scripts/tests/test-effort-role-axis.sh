#!/usr/bin/env bash
# EFFORT-IS-NOT-A-FUNCTION-OF-CLASS-ALONE-01 (founder 2026-09-14): effort must
# depend on ROLE and class together, not on class alone. think_stakes.classes
# (config/model-capability.yaml) maps BOTH heavy and strategic onto the
# identical size=heavy/complexity=complex row, so kind/size/complexity alone
# can never separate an architect-prepass call from a judge call at the same
# class -- that collapse is exactly what test-think-task-class-plumbing.sh's
# fixture measures (class=Heavy arm=codex effort=high, class=Strategic
# arm=astra effort=high -- different arm, identical effort). This suite
# proves the fix: a `role` field now rides the think descriptor
# (leadv2-router.sh _think_build_desc) and the arbiter's effort_matrix can key
# on it (leadv2-route-arbiter.sh TASK_EFFORT_KEYS `roles`), so two think
# resolves at the SAME class with DIFFERENT roles produce DIFFERENT effort --
# and removing the role-keyed row collapses them back to one value.
# run-all-triggers: leadv2-router.sh leadv2-route-arbiter.sh leadv2-routing.yaml leadv2-think-model.sh model-capability.yaml
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROUTER="${SCRIPTS_DIR}/leadv2-router.sh"
WRAPPER="${SCRIPTS_DIR}/lib/leadv2-think-model.sh"
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/test-effort-role-axis.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

cat >"$TMP/quota.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":10,"seven_day_pct":10}]}}'
EOF
chmod +x "$TMP/quota.sh"

cat >"$TMP/capability.yaml" <<'EOF'
astra: { model_id: gpt-6-astra }
think_stakes:
  default_class: heavy
  classes:
    heavy: { size: heavy, complexity: complex, think_tier: heavy }
    strategic: { size: heavy, complexity: complex, think_tier: strategic }
EOF

# With-role-axis fixture: a `roles` row wins for judge/diagnose ahead of the
# generic kinds:[plan,audit,review] row -- the production shape added by this
# change (config/leadv2-routing.yaml router_v2.effort_matrix).
cat >"$TMP/routing-with-role.yaml" <<'EOF'
router_v2:
  quota_ceilings:
    codex: { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  capability_matrix:
    - { arm: astra, provider: codex, model: gpt-6-astra, tier: astra, cost: 1, kinds: [plan, review], sizes: [heavy], think_tiers: [strategic], review: true, protected: true, capability: 6 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - { roles: [judge, diagnose], effort: low }
    - { kinds: [plan, audit, review], effort: high }
    - { default: true, effort: medium }
EOF

# Negative control fixture: same matrix, minus the roles row -- the axis under
# test removed, nothing else touched.
cat >"$TMP/routing-no-role.yaml" <<'EOF'
router_v2:
  quota_ceilings:
    codex: { work_pct: 95, review_pct: 98 }
    claude: { work_pct: 95, review_pct: 95 }
  capability_matrix:
    - { arm: astra, provider: codex, model: gpt-6-astra, tier: astra, cost: 1, kinds: [plan, review], sizes: [heavy], think_tiers: [strategic], review: true, protected: true, capability: 6 }
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix:
    - { kinds: [plan, audit, review], effort: high }
    - { default: true, effort: medium }
EOF

resolve() { # $1=role $2=routing-yaml-basename $3=think-log-path -> stdout arm
  local role="$1" routing="$2" log="$3"
  env -u LEADV2_THINK_MODEL -u LEADV2_THINK_CLASS -u LEADV2_THINK_ROLE -u LEADV2_THINK_TASK_ID -u LEADV2_TASK_ID \
    LEADV2_TEST_CONTEXT=1 LEADV2_TEST_ROUTER="$ROUTER" \
    LEADV2_MODEL_CAPABILITY_YAML="$TMP/capability.yaml" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/$routing" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/quota.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$role-$routing" \
    LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/arbiter-$role-$routing.jsonl" \
    LEADV2_THINK_DECISIONS_FILE="$log" \
    LEADV2_THINK_ROLE="$role" LEADV2_THINK_CLASS=Strategic \
    bash "$WRAPPER"
}

# --- (1)/(2): same class (Strategic), different roles -> different effort ---
with_log="$TMP/with-role.log"
arch_arm="$(resolve architect-prepass routing-with-role.yaml "$with_log")"
judge_arm="$(resolve judge routing-with-role.yaml "$with_log")"
arch_effort="$(grep 'role=architect-prepass ' "$with_log" | tail -1 | sed -n 's/.*effort=\([^ ]*\).*/\1/p')"
judge_effort="$(grep 'role=judge ' "$with_log" | tail -1 | sed -n 's/.*effort=\([^ ]*\).*/\1/p')"

if [[ -n "$arch_arm" && -n "$judge_arm" ]]; then
  pass "both think roles resolved an arm (architect-prepass=$arch_arm judge=$judge_arm)"
else
  fail "expected both roles to resolve an arm, got architect-prepass='$arch_arm' judge='$judge_arm'"
fi

if [[ "$arch_effort" == "high" && "$judge_effort" == "low" && "$arch_effort" != "$judge_effort" ]]; then
  pass "same class (Strategic), different roles -> different effort: architect-prepass=high judge=low"
else
  fail "expected architect-prepass=high judge=low, got architect-prepass='$arch_effort' judge='$judge_effort' (log: $(tr '\n' '|' < "$with_log"))"
fi

# --- (3) negative control: drop the roles row -> both collapse to one value ---
no_role_log="$TMP/no-role.log"
resolve architect-prepass routing-no-role.yaml "$no_role_log" >/dev/null
resolve judge routing-no-role.yaml "$no_role_log" >/dev/null
arch_effort_nr="$(grep 'role=architect-prepass ' "$no_role_log" | tail -1 | sed -n 's/.*effort=\([^ ]*\).*/\1/p')"
judge_effort_nr="$(grep 'role=judge ' "$no_role_log" | tail -1 | sed -n 's/.*effort=\([^ ]*\).*/\1/p')"

if [[ "$arch_effort_nr" == "high" && "$judge_effort_nr" == "high" && "$arch_effort_nr" == "$judge_effort_nr" ]]; then
  pass "negative control: removing the roles row collapses architect-prepass and judge back to the same effort (high)"
else
  fail "expected the role axis removed to collapse both to 'high', got architect-prepass='$arch_effort_nr' judge='$judge_effort_nr' (log: $(tr '\n' '|' < "$no_role_log"))"
fi

printf 'SUMMARY: %s pass, %s fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
