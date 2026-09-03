#!/usr/bin/env bash
# FREEPOOL-MUST-ACTUALLY-GET-WORK-01: a Standard lane whose declared writes
# are only tests plus docs/handoff must be admitted to freepool. The +100
# capability floor remains for production Standard work; the arbiter receives
# a dispatcher-proven test_only descriptor and emits that fact on its live
# route line. The negative control mutates only a sibling throwaway dispatcher
# copy so all writes derive as protected, then proves this exact admission
# assertion turns RED before the production dispatcher is re-run GREEN.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/freepool-gets-work.XXXXXX")"
MUTATED_DISPATCH="${SCRIPTS_DIR}/.test-freepool-gets-work-mutated.$$.sh"
cleanup() { rm -rf "${TMP}"; rm -f "${MUTATED_DISPATCH}"; }
trap cleanup EXIT

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

if bash -n "${DISPATCH}" && bash -n "${ARBITER}"; then
  pass 'bash syntax: dispatcher + arbiter'
else
  fail 'bash syntax: dispatcher + arbiter'
fi

cat > "${TMP}/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${ROUTE_TEST_QUOTA}"
EOF
cat > "${TMP}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/live.sh" "${TMP}/free.sh"

quota_json() {
  python3 <<'PY'
import json
print(json.dumps({
  'glm': {'status': 'ok', 'five_hour': {'pct': 99}, 'weekly': {'pct': 99}},
  'codex': {'status': 'ok', 'binding_window': 'primary', 'windows': [{'kind': 'primary', 'used_percent': 20}]},
  'anthropic': {'status': 'ok', 'accounts': [{'active': True, 'five_hour_pct': 20, 'seven_day_pct': 20}]},
}))
PY
}
ROUTE_TEST_QUOTA="$(quota_json)"

REPO="${TMP}/repo"
mkdir -p "${REPO}/.claude/ref" "${REPO}/docs/leadv2" "${REPO}/docs/leadv2/tasks"
git -C "${REPO}" init -q -b main
git -C "${REPO}" config user.email test@example.com
git -C "${REPO}" config user.name test
printf 'seed\n' > "${REPO}/seed"
git -C "${REPO}" add seed && git -C "${REPO}" commit -qm seed
cp "${ROUTING}" "${REPO}/.claude/ref/leadv2-routing.yaml"

WORKER="${TMP}/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$$"\n' > "${WORKER}"
chmod +x "${WORKER}"

dispatch_probe() { # <dispatcher> <label>
  local bin="$1" label="$2"
  (
    cd "${REPO}" || exit 9
    LEADV2_STATE_ROOT="${TMP}/state-${label}" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP}/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP}/arbiter-${label}.json" \
    ROUTE_TEST_QUOTA="${ROUTE_TEST_QUOTA}" \
    CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP}/cache-${label}" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ \
    LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN=/bin/false LEADV2_DISPATCH_SUBSESSION_BIN="${WORKER}" \
    bash "${bin}" "freepool tests-only admission ${label}" \
      --kind code --task-class standard --no-spawn \
      --writes 'tests/freepool-probe.sh,docs/handoff/FREEPOOL/report.md' 2>&1
  )
}

green_out="$(dispatch_probe "${DISPATCH}" green)"; green_rc=$?
printf '%s\n' "${green_out}" > "${TMP}/green.log"
if [[ ${green_rc} -eq 0 ]] && printf '%s\n' "${green_out}" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass 'green: Standard tests/docs-only lane resolves arm=freepool without --protected'
  printf 'EVIDENCE: %s\n' "$(printf '%s\n' "${green_out}" | grep -m1 'route_resolved by=arbiter role=worker arm=freepool')"
else
  fail 'green: Standard tests/docs-only lane resolves arm=freepool without --protected' "rc=${green_rc} $(tail -n 8 "${TMP}/green.log")"
fi
if printf '%s\n' "${green_out}" | grep -q 'protection_derived by=router .*write_class=tests_docs .*writes_protected=0 .*manual_protected=0 .*effective_protected=0'; then
  pass 'green: journal carries deciding test/docs write-set derivation'
else
  fail 'green: journal carries deciding test/docs write-set derivation' "$(grep -m1 protection_derived "${TMP}/green.log" || true)"
fi
if printf '%s\n' "${green_out}" | grep -q 'freepool_floor_mode .*test_only=1' && ! printf '%s\n' "${green_out}" | grep -q 'arm_floor_applied'; then
  pass 'green: Standard tests/docs-only lane is below the preserved capability floor'
else
  fail 'green: Standard tests/docs-only lane is below the preserved capability floor' "$(grep -E 'freepool_floor_mode|arm_floor_applied' "${TMP}/green.log" || true)"
fi

# Negative control A: force the write-set classifier to always return
# protected. The exact tests/docs dispatch must lose freepool admission.
cp "${DISPATCH}" "${MUTATED_DISPATCH}"
python3 - "${MUTATED_DISPATCH}" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = '_writes_class="$(_lane_writes_class "${lane_writes}")"'
if needle not in s:
    raise SystemExit('mutation anchor missing')
open(p, 'w').write(s.replace(needle, '_writes_class="protected"  # MUTATION: always protected', 1))
PY
mutate_rc=$?
if [[ ${mutate_rc} -ne 0 ]]; then
  fail 'negative control A: mutation anchor found'
else
  mutated_out="$(dispatch_probe "${MUTATED_DISPATCH}" mutated)"; mutated_rc=$?
  printf '%s\n' "${mutated_out}" > "${TMP}/mutated.log"
  if [[ ${mutated_rc} -eq 0 ]] && ! printf '%s\n' "${mutated_out}" | grep -q 'route_resolved by=arbiter role=worker arm=freepool' \
     && printf '%s\n' "${mutated_out}" | grep -q 'arm_excluded by=router arm=freepool .*reason=protected_path'; then
    pass 'RED: negative control A always-protected mutation blocks freepool for the tests/docs lane'
  else
    fail 'negative control A: always-protected mutation did not make admission assertion red' "rc=${mutated_rc} $(tail -n 8 "${TMP}/mutated.log")"
  fi
fi

# The production dispatcher remains untouched and the first green run above is
# the restoration proof; re-run after the mutation to prove no sibling-copy
# path leaked into the canonical dispatcher.
restored_out="$(dispatch_probe "${DISPATCH}" restored)"; restored_rc=$?
if [[ ${restored_rc} -eq 0 ]] && printf '%s\n' "${restored_out}" | grep -q 'route_resolved by=arbiter role=worker arm=freepool'; then
  pass 'green: production dispatcher remains freepool-admitting after mutation control'
else
  fail 'green: production dispatcher remains freepool-admitting after mutation control' "rc=${restored_rc}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
