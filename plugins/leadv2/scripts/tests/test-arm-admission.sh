#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code leadv2-dispatch-code.sh leadv2-route-arbiter
# tests/test-arm-admission.sh — ARMS-ADMISSION-01.
#
# Three defects, one suite, all against FIXTURE routing data (fictitious arm
# names "trusted-arm" / "cheap-arm" / "free-arm" — never glm/glm-flash/
# freepool) so nothing here can be satisfied by an arm-id literal anywhere in
# the admission decision path:
#
#   1. --protected used to ban every untrusted arm wholesale, even for work
#      that writes nothing (review/audit). It must ban them only when the
#      task's own kind writes production code.
#   2. The legacy resolver's base-arm was pinned to a single hardcoded id, so
#      the cheap/mechanical tier could never win as primary on that path.
#      The base arm must come from the same cost-ranked routing data every
#      other pick comes from.
#   3. The dispatch ladder (_build_candidate_chain, raw --task-class) and the
#      route arbiter (SIZE_MAP-folded task_class) could disagree on whether
#      an untrusted arm is admissible at task_class=light.
#
# Case 5 (no name literals in the admission decision) is not a separate
# assertion — every case below runs against the alien-named arm-id fixture;
# if _build_candidate_chain, _select_base_arm or route_arbiter's cell filter
# keyed on "freepool"/"glm-flash" by string, every case here would still be
# exercising the SAME code paths and would fail identically, since those
# strings never appear in the fixture arm ids. (Provider ids below ARE the
# real glm/codex/claude/freepool vocabulary — leadv2-route-arbiter.sh's
# quota-utilization reader (util()/capped()) hardcodes that specific
# 4-provider set for reading LIVE QUOTA, a pre-existing, orthogonal
# limitation unrelated to arm admission; the ARM ids it ranks/admits stay
# alien throughout.)
#
# Run: bash plugins/leadv2/scripts/tests/test-arm-admission.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
ARBITER="${PLUGIN_SCRIPTS}/lib/leadv2-route-arbiter.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/arm-admission-fixture.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT INT TERM

# Snapshot the repo state BEFORE this suite touches anything, so the hygiene
# check at the end can prove "byte-identical" even when the caller's tree
# already carries other lane changes (this suite must add nothing new, not
# require a pristine tree it does not own).
_hygiene_before="$(git -C "${PLUGIN_ROOT}" diff -- . 2>/dev/null)"
_hygiene_status_before="$(git -C "${PLUGIN_ROOT}" status --porcelain -- . 2>/dev/null)"

# ── syntax floor on every changed shell file ────────────────────────────────
for f in "scripts/leadv2-dispatch-code.sh" "scripts/lib/leadv2-route-arbiter.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    pass "bash -n ${f} (incl. 3.2)"
  else
    fail "bash -n ${f}"
  fi
done

# ── fixture routing yaml: fictitious arm ids, real provider vocabulary ─────
# trusted-arm  — the only protected:true cell, all kinds, all sizes. provider
#                claude (arbiter's trusted-quota-reader provider).
# cheap-arm    — untrusted, mechanical-only (code/docs), cost 0.4 (cheapest),
#                sizes standard only. Stands in for the "glm-flash" role.
#                provider glm.
# free-arm     — untrusted, review/audit-capable too, cost 1, sizes
#                standard+bulk. Stands in for the "freepool" role. provider
#                freepool (the arbiter's own health-gated free-tier path).
ROUTING="${FIXTURE}/routing.yaml"
cat > "${ROUTING}" <<'YAML'
router_v2:
  capability_matrix:
    - { arm: trusted-arm, provider: claude, model: t1, cost: 5, kinds: [code, docs, review, audit], sizes: [standard, heavy, bulk], protected: true }
    - { arm: cheap-arm, provider: glm, model: c1, cost: 0.4, kinds: [code, docs], sizes: [standard], protected: false }
    - { arm: free-arm, provider: freepool, model: f1, cost: 1, kinds: [code, docs, review, audit], sizes: [standard, bulk], protected: false }
router:
  dispatch_ladder:
    - id: trusted-arm
      provider: claude
      model: t1
      when: [all]
    - id: cheap-arm
      provider: glm
      model: c1
      when: [trivial, light, standard]
      untrusted: true
    - id: free-arm
      provider: freepool
      model: f1
      when: [light, standard, bulk]
      untrusted: true
YAML

# ── harness: extract the real _build_candidate_chain (+ its ladder loader)
#    from the production script, byte for byte — never a reimplementation.
build_chain_harness() { # <out-file> <start-arm>
  local out="$1" start_arm="$2"
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\nemit() { :; }\nlog_err() { :; }\n'
    sed -n '/^_load_dispatch_ladder()/,/^}$/p' "${DISPATCH}"
    sed -n '/^_build_candidate_chain()/,/^}$/p' "${DISPATCH}"
    printf 'ROUTING_YAML="%s"\nDC_PROTECTED="${DC_PROTECTED:-0}"\nDC_SAFETY="${DC_SAFETY:-0}"\nDC_KIND="${DC_KIND:-}"\nDC_TASK_CLASS="${DC_TASK_CLASS:-standard}"\n' "${ROUTING}"
    printf '_load_dispatch_ladder\ncandidate_arms=()\n_build_candidate_chain "%s" TEST0000\nprintf "%%s\\n" "${candidate_arms[*]:-}"\n' "${start_arm}"
  } > "${out}"
}

# ── harness: extract the real _select_base_arm from the production script.
select_base_arm_harness() { # <out-file>
  local out="$1"
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\n'
    sed -n '/^_select_base_arm()/,/^}$/p' "${DISPATCH}"
    printf 'ROUTING_YAML="%s"\nDC_PROTECTED="${DC_PROTECTED:-0}"\nDC_SAFETY="${DC_SAFETY:-0}"\nDC_KIND="${DC_KIND:-}"\nDC_TASK_CLASS="${DC_TASK_CLASS:-standard}"\n_select_base_arm\n' "${ROUTING}"
  } > "${out}"
}

has_arm() { # <space-separated-list> <arm>
  local hay=" $1 " needle=" $2 "
  [[ "${hay}" == *"${needle}"* ]]
}

# ── harness: extract the real _select_base_arm + resolve_arm from the
#    production script, byte for byte, and drive resolve_arm's OWN resolver
#    invocation (the actual call site at "--base-arm ${_base_arm}") -- not
#    _select_base_arm in isolation. GLM_POLICY_RESOLVER is pointed at a stub
#    that records the argv it was invoked with to $RESOLVER_SEEN_FILE, so the
#    test can assert on what resolve_arm actually handed the resolver.
resolve_arm_harness() { # <out-file> <resolver-stub-py>
  local out="$1" stub="$2"
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\n'
    sed -n '/^_select_base_arm()/,/^}$/p' "${DISPATCH}"
    sed -n '/^resolve_arm()/,/^}$/p' "${DISPATCH}"
    printf 'ROUTING_YAML="%s"\nGLM_POLICY_RESOLVER="%s"\nDC_PROTECTED="${DC_PROTECTED:-0}"\nDC_SAFETY="${DC_SAFETY:-0}"\nDC_KIND="${DC_KIND:-}"\nDC_TASK_CLASS="${DC_TASK_CLASS:-standard}"\nDC_SUBSYSTEM_COUNT="${DC_SUBSYSTEM_COUNT:-0}"\nDC_INTERACTIVE="${DC_INTERACTIVE:-0}"\nDC_UI_JUDGMENT="${DC_UI_JUDGMENT:-0}"\nDC_GLM_FAILURES="${DC_GLM_FAILURES:-0}"\nDC_GLM_LOCK_BUSY="${DC_GLM_LOCK_BUSY:-0}"\nresolve_arm\n' "${ROUTING}" "${stub}"
  } > "${out}"
}
cat > "${FIXTURE}/resolver-stub.py" <<'PY'
import os, sys
with open(os.environ["RESOLVER_SEEN_FILE"], "w") as f:
    f.write(" ".join(sys.argv[1:]))
print("arm=stub")
print("rule=none")
print("reason=stub")
print("tier=")
PY

run_arbiter() { # <routing-yaml> <descriptor-json>
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$1" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${FIXTURE}/quota-live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${FIXTURE}/freepool-gate.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/state-$$-${RANDOM}.json" \
  bash -c "source '${ARBITER}'; route_arbiter worker '$2'"
}
cat > "${FIXTURE}/quota-live.sh" <<'STUB'
#!/usr/bin/env bash
printf '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","windows":[]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":10,"seven_day_pct":10}]}}\n'
STUB
chmod +x "${FIXTURE}/quota-live.sh"
cat > "${FIXTURE}/freepool-gate.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${FIXTURE}/freepool-gate.sh"

# ══════════════════════════════════════════════════════════════════════════
# Case 1: protected lane, work writes production code (kind=code, default)
#         ⇒ untrusted arms excluded, as today.
# ══════════════════════════════════════════════════════════════════════════
h1="${FIXTURE}/h1.sh"; build_chain_harness "${h1}" "trusted-arm"
out1="$(DC_PROTECTED=1 DC_KIND=code bash "${h1}")"
if [[ "${out1}" == "trusted-arm" ]]; then
  pass "case1 (ladder): protected + kind=code excludes cheap-arm/free-arm — got '${out1}'"
else
  fail "case1 (ladder): expected only 'trusted-arm', got '${out1}'"
fi

arb1="$(run_arbiter "${ROUTING}" '{"kind":"code","size":"standard","protected":true,"task":"case1"}')"
if [[ "${arb1}" == arm=trusted-arm\ * ]]; then
  pass "case1 (arbiter): protected + kind=code picks trusted-arm — ${arb1}"
else
  fail "case1 (arbiter): expected arm=trusted-arm, got '${arb1}'"
fi

# ══════════════════════════════════════════════════════════════════════════
# Case 2: protected lane, work is review/audit only ⇒ an untrusted arm IS a
#         candidate.
# ══════════════════════════════════════════════════════════════════════════
h2="${FIXTURE}/h2.sh"; build_chain_harness "${h2}" "trusted-arm"
out2="$(DC_PROTECTED=1 DC_KIND=review bash "${h2}")"
if has_arm "${out2}" "free-arm"; then
  pass "case2 (ladder): protected + kind=review admits free-arm — got '${out2}'"
else
  fail "case2 (ladder): expected free-arm in chain, got '${out2}'"
fi

arb2="$(run_arbiter "${ROUTING}" '{"kind":"review","size":"standard","protected":true,"task":"case2"}')"
if [[ "${arb2}" == *free-arm* ]]; then
  pass "case2 (arbiter): protected + kind=review reaches free-arm — ${arb2}"
else
  fail "case2 (arbiter): expected free-arm reachable, got '${arb2}'"
fi

# ══════════════════════════════════════════════════════════════════════════
# Case 3: task_class=light ⇒ ladder and arbiter agree on free-arm admission.
# ══════════════════════════════════════════════════════════════════════════
h3="${FIXTURE}/h3.sh"; build_chain_harness "${h3}" "trusted-arm"
out3="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=light bash "${h3}")"
ladder_admits_free=0
has_arm "${out3}" "free-arm" && ladder_admits_free=1

arb3="$(run_arbiter "${ROUTING}" '{"kind":"code","size":"light","protected":false,"task":"case3"}')"
arbiter_admits_free=0
[[ "${arb3}" == *free-arm* ]] && arbiter_admits_free=1

if [[ "${ladder_admits_free}" == "${arbiter_admits_free}" && "${ladder_admits_free}" == "1" ]]; then
  pass "case3: ladder and arbiter agree free-arm is admissible at light (ladder='${out3}' arbiter='${arb3}')"
else
  fail "case3: ladder/arbiter disagree at light — ladder_admits=${ladder_admits_free} ('${out3}') arbiter_admits=${arbiter_admits_free} ('${arb3}')"
fi

# ══════════════════════════════════════════════════════════════════════════
# Case 4: a mechanical build task ⇒ cheap-arm (glm-flash's role) appears as
#         the resolver's own base-arm pick — cheapest capable, not pinned.
# ══════════════════════════════════════════════════════════════════════════
h4="${FIXTURE}/h4.sh"; select_base_arm_harness "${h4}"
out4="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=standard bash "${h4}")"
if [[ "${out4}" == "cheap-arm" ]]; then
  pass "case4: mechanical build task resolves base-arm=cheap-arm (cheapest capable) — got '${out4}'"
else
  fail "case4: expected base-arm=cheap-arm, got '${out4}'"
fi

# base-arm never special-cased ahead of data: a protected task must NOT pick
# the untrusted cheap-arm even though it is cheaper.
out4p="$(DC_PROTECTED=1 DC_KIND=code DC_TASK_CLASS=standard bash "${h4}")"
if [[ "${out4p}" == "trusted-arm" ]]; then
  pass "case4b: protected mechanical task still resolves base-arm=trusted-arm — got '${out4p}'"
else
  fail "case4b: expected base-arm=trusted-arm on a protected task, got '${out4p}'"
fi

# ══════════════════════════════════════════════════════════════════════════
# Case 5: resolve_arm's OWN resolver call (the real call site: the
#         "--base-arm ${_base_arm}" argv element it builds and hands to
#         GLM_POLICY_RESOLVER) must carry cheap-arm, not a hardcoded
#         constant. Case 4 alone cannot catch a regression where resolve_arm
#         stops using _select_base_arm's output -- this drives resolve_arm()
#         itself and inspects the argv a stub resolver actually received.
# ══════════════════════════════════════════════════════════════════════════
h5="${FIXTURE}/h5.sh"; resolve_arm_harness "${h5}" "${FIXTURE}/resolver-stub.py"
seen5="${FIXTURE}/resolver-seen.txt"
rm -f "${seen5}"
RESOLVER_SEEN_FILE="${seen5}" DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=standard bash "${h5}" >/dev/null
seen5_val="$(cat "${seen5}" 2>/dev/null || printf '')"
if [[ "${seen5_val}" == *"--base-arm cheap-arm"* ]]; then
  pass "case5: resolve_arm's own resolver invocation carries base-arm=cheap-arm — argv='${seen5_val}'"
else
  fail "case5: expected '--base-arm cheap-arm' in resolve_arm's resolver argv, got '${seen5_val}'"
fi

# ══════════════════════════════════════════════════════════════════════════
# Mutation proofs (E2E-KILLRATE-01 discipline): mutate the PRODUCTION
# function body in a scratch copy, prove the correct-code case goes RED under
# the mutation, then re-prove GREEN against the unmutated tree. Never against
# the working tree itself.
# ══════════════════════════════════════════════════════════════════════════

# Mutation A: revert the writes_prod split in _build_candidate_chain back to
# the old blanket protected/safety strip — case2 (protected + review admits
# free-arm) must go RED (free-arm excluded again).
mutant_dispatch_a="${FIXTURE}/dispatch-mutantA.sh"
sed 's/"\${DC_SAFETY:-0}" == "1" || ( "\${DC_PROTECTED:-0}" == "1" \&\& "\${_writes_prod}" == "1" )/"${DC_SAFETY:-0}" == "1" || "${DC_PROTECTED:-0}" == "1"/' \
  "${DISPATCH}" > "${mutant_dispatch_a}"
if ! grep -q '"\${DC_SAFETY:-0}" == "1" || "\${DC_PROTECTED:-0}" == "1" ]]; then' "${mutant_dispatch_a}"; then
  fail "NC mutationA: sed pattern drifted, mutant file unchanged from production"
else
  DISPATCH="${mutant_dispatch_a}"
  hA="${FIXTURE}/hA.sh"; build_chain_harness "${hA}" "trusted-arm"
  DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
  outA="$(DC_PROTECTED=1 DC_KIND=review bash "${hA}")"
  if ! has_arm "${outA}" "free-arm"; then
    pass "NC(red) mutationA: reverting the writes_prod split re-excludes free-arm from review work — got '${outA}'"
  else
    fail "NC mutationA: mutant did not flip case2 (control is vacuous) — got '${outA}'"
  fi
fi

# Mutation B: revert _select_base_arm's cost ranking to a hardcoded pick —
# case4 (mechanical task resolves the cheapest capable arm) must go RED.
mutant_dispatch_b="${FIXTURE}/dispatch-mutantB.sh"
sed 's/print(capable\[0\]\.get("arm") or "glm")/print("trusted-arm")/' \
  "${DISPATCH}" > "${mutant_dispatch_b}"
if ! grep -q 'print("trusted-arm")' "${mutant_dispatch_b}"; then
  fail "NC mutationB: sed pattern drifted, mutant file unchanged from production"
else
  DISPATCH="${mutant_dispatch_b}"
  hB="${FIXTURE}/hB.sh"; select_base_arm_harness "${hB}"
  DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
  outB="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=standard bash "${hB}")"
  if [[ "${outB}" != "cheap-arm" ]]; then
    pass "NC(red) mutationB: hardcoding the base-arm pick loses cheap-arm — got '${outB}'"
  else
    fail "NC mutationB: mutant did not flip case4 (control is vacuous) — got '${outB}'"
  fi
fi

# Mutation C: revert the routing-yaml light fix (drop "light" from free-arm's
# ladder `when:`) — case3's ladder side must go RED (arbiter still admits,
# ladder no longer does, so they disagree again).
mutant_routing_c="${FIXTURE}/routing-mutantC.yaml"
sed 's/when: \[light, standard, bulk\]/when: [standard, bulk]/' "${ROUTING}" > "${mutant_routing_c}"
if ! grep -q 'when: \[standard, bulk\]' "${mutant_routing_c}"; then
  fail "NC mutationC: sed pattern drifted, mutant yaml unchanged"
else
  hC="${FIXTURE}/hC.sh"
  ROUTING_SAVE="${ROUTING}"
  ROUTING="${mutant_routing_c}"
  build_chain_harness "${hC}" "trusted-arm"
  ROUTING="${ROUTING_SAVE}"
  outC="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=light bash "${hC}")"
  if ! has_arm "${outC}" "free-arm"; then
    pass "NC(red) mutationC: dropping 'light' from free-arm's when: makes the ladder disagree with the arbiter again — ladder='${outC}'"
  else
    fail "NC mutationC: mutant did not flip ladder admission (control is vacuous) — ladder='${outC}'"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════
# Post-mutation GREEN re-proof: the unmutated working tree still passes
# case2 / case3 / case4 exactly as at the top of this file.
# ══════════════════════════════════════════════════════════════════════════
out2b="$(DC_PROTECTED=1 DC_KIND=review bash "${h2}")"
has_arm "${out2b}" "free-arm" && pass "post-mutation GREEN: case2 still passes" || fail "post-mutation GREEN: case2 regressed"
out3b="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=light bash "${h3}")"
has_arm "${out3b}" "free-arm" && pass "post-mutation GREEN: case3 (ladder) still passes" || fail "post-mutation GREEN: case3 (ladder) regressed"
out4b="$(DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=standard bash "${h4}")"
[[ "${out4b}" == "cheap-arm" ]] && pass "post-mutation GREEN: case4 still passes" || fail "post-mutation GREEN: case4 regressed"
rm -f "${seen5}"
RESOLVER_SEEN_FILE="${seen5}" DC_PROTECTED=0 DC_KIND=code DC_TASK_CLASS=standard bash "${h5}" >/dev/null
seen5b_val="$(cat "${seen5}" 2>/dev/null || printf '')"
[[ "${seen5b_val}" == *"--base-arm cheap-arm"* ]] && pass "post-mutation GREEN: case5 still passes" || fail "post-mutation GREEN: case5 regressed"

# ── repo hygiene: no repo path or real state root touched by this suite ────
_hygiene_after="$(git -C "${PLUGIN_ROOT}" diff -- . 2>/dev/null)"
_hygiene_status_after="$(git -C "${PLUGIN_ROOT}" status --porcelain -- . 2>/dev/null)"
if [[ "${_hygiene_before}" == "${_hygiene_after}" && "${_hygiene_status_before}" == "${_hygiene_status_after}" ]]; then
  pass "repo hygiene: this suite left every repo path byte-identical (fixture-only mutation)"
else
  fail "repo hygiene: this suite changed the working tree it does not own"
fi

printf '\n[SUMMARY] PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
