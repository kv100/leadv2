#!/usr/bin/env bash
# dispatch-a24b1588 Item 1: router_v2's own candidate-arm selection never went
# through the DISPATCHABLE_BUILD_ARMS filter (_filter_ladder_to_dispatchable is
# a v1-only call). A stale tenant .claude/ref/leadv2-routing.yaml that still
# lists kimi under router_v2.arms can resurrect it as a dispatchable arm the
# instant LEADV2_ROUTER_V2=1. This suite proves:
#   T1 — a retired arm (kimi) cannot survive into the v2 candidate chain, and
#        the drop is journalled (router=v2), without collapsing the chain.
#   T2 — the naive fix (intersect eligible with DISPATCHABLE_BUILD_ARMS with no
#        vocabulary normalization) is rejected: a canonical-shaped
#        router_v2.arms entry (claude-sonnet) must survive as "sonnet", not be
#        dropped for spelling a different vocabulary than the ladder.
#
# Both FAIL against current HEAD: HEAD's v2 branch (leadv2-dispatch-code.sh,
# router_label == v2) does IFS=',' read straight from the resolver's eligible=
# output into candidate_arms with no filter and no normalization at all.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

bash -n "${SCRIPT_DIR}/test-router-v2-retired-arm.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# ── Fail-closed spawn fence (mirrors test-routing-enforcement-p1.sh's preamble,
#    including LEADV2_DISPATCH_SUBSESSION_BIN, which test-arm-ladder-vocabulary-
#    drift.sh's fence omits — dispatch-a24b1588 explicitly calls that gap out).
for _arm in glm kimi codex; do
  _poison="${TMP_ROOT}/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${_poison}"
  chmod +x "${_poison}"
done
printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "${TMP_ROOT}/poison-sonnet.sh"
chmod +x "${TMP_ROOT}/poison-sonnet.sh"
export LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"
export LEADV2_DISPATCH_SUBSESSION_BIN="${TMP_ROOT}/poison-sonnet.sh"
# Belt-and-suspenders: no spawn is attempted at all in this suite (--no-spawn).
export LEADV2_DISPATCH_SPAWN=0

# ── Fake router_v2 dependency chain. resolve_v2_dispatch (leadv2-dispatch-
#    code.sh:1051) shells out to leadv2-router-v2.sh (filter, resolve),
#    leadv2-task-judge.sh (a REAL `claude -p --model haiku` call) and
#    leadv2-route-bandit.sh. All three are env-overridable
#    (LEADV2_ROUTER_V2_BIN / LEADV2_TASK_JUDGE_BIN / LEADV2_ROUTE_BANDIT_BIN);
#    faking all three keeps this suite fully offline and deterministic instead
#    of depending on the real L1/L2/L3 resolver's own live behaviour.
make_fake_rv2() {
  local path="$1" arm="$2" eligible="$3"
  cat > "${path}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  filter)  printf 'eligible=${eligible}\nfiltered=[]\n' ;;
  resolve) printf 'arm=${arm}\nrule=fake_test\nreason=fake_test\neligible=${eligible}\ncodex_quota_blocked=0\n' ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${path}"
}

make_fake_judge() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
printf '{"work_kind":"build","duration_class":"short","complexity":"simple"}\n'
SH
  chmod +x "${path}"
}

make_fake_bandit() {
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
printf 'samples={}\n'
SH
  chmod +x "${path}"
}

make_tenant_root() {
  local root="$1" arms_block="$2"
  mkdir -p "${root}/.claude/ref"
  cat > "${root}/.claude/ref/leadv2-routing.yaml" <<YAML
router_v2:
${arms_block}
router:
  dispatch_ladder:
    - id: glm
      provider: glm
      model: glm-5.2
      when: [all]
      effort: standard
    - id: codex
      provider: codex
      model: gpt-5.6-terra
      when: [all]
      effort: standard
    - id: sonnet
      provider: anthropic
      model: sonnet
      when: [all]
      effort: standard
YAML
}

# ============================================================================
# T1: stale-tenant kimi resurrection. router_v2.arms still lists kimi (no
# dispatch:false-equivalent exists for router_v2.arms -- retirement there is
# expressed by simply not listing the id, so "still listing kimi" IS the
# resurrection vector, matching the architect's C1-analogue for v2). The fake
# resolver hands back kimi as PRIMARY with eligible=kimi,claude-sonnet -- the
# shape a stale registry produces when kimi hasn't been pulled from arms yet.
# ============================================================================
make_tenant_root "${TMP_ROOT}/t1-root" "  arms:
    - id: kimi
      channel: kimi-coder.sh
      model: moonshotai/kimi-k3-free
      bucket: kimi
    - id: claude-sonnet
      channel: claude-subsession.sh
      model: sonnet
      bucket: anthropic:max_20x"

make_fake_rv2  "${TMP_ROOT}/t1-rv2.sh"    "kimi" "kimi,claude-sonnet"
make_fake_judge "${TMP_ROOT}/t1-judge.sh"
make_fake_bandit "${TMP_ROOT}/t1-bandit.sh"

t1_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t1-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t1-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2=1 \
  LEADV2_ROUTER_V2_BIN="${TMP_ROOT}/t1-rv2.sh" \
  LEADV2_TASK_JUDGE_BIN="${TMP_ROOT}/t1-judge.sh" \
  LEADV2_ROUTE_BANDIT_BIN="${TMP_ROOT}/t1-bandit.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only v2-retired-arm T1 stale tenant kimi' 2>&1)"
t1_rc=$?

if grep -qE 'candidate_chain.*arms=[^ ]*kimi' <<<"${t1_out}"; then
  fail 'T1: kimi survives into v2 candidate_chain' "output=${t1_out}"
elif ! grep -q 'arm_dropped_not_dispatchable arm=kimi' <<<"${t1_out}"; then
  fail 'T1: no arm_dropped_not_dispatchable line for kimi' "output=${t1_out}"
elif ! grep -q 'arm_dropped_not_dispatchable arm=kimi.*router=v2' <<<"${t1_out}"; then
  fail 'T1: kimi drop line missing router=v2' "output=${t1_out}"
elif [[ ${t1_rc} -eq 4 ]]; then
  fail 'T1: chain collapsed to all_arms_exhausted instead of falling back to sonnet' "rc=${t1_rc} output=${t1_out}"
else
  pass 'T1: retired arm kimi dropped from v2 chain (router=v2), no collapse (rc='"${t1_rc}"')'
fi

# ============================================================================
# T2: canonical-shaped router_v2.arms (claude-sonnet, claude-haiku — no kimi).
# Guards against the naive fix: intersecting v2's eligible= with
# DISPATCHABLE_BUILD_ARMS BEFORE normalizing claude-<model> -> <model> would
# drop claude-sonnet too (it matches no id in {glm,codex,sonnet} verbatim),
# emptying the chain and turning every v2 dispatch into all_arms_exhausted --
# a resurrection bug traded for a total-outage bug. Must resolve to a chain
# containing "sonnet", not "claude-sonnet", and must not exit 4.
# ============================================================================
make_fake_rv2 "${TMP_ROOT}/t2-rv2.sh" "claude-sonnet" "claude-sonnet,claude-haiku"
make_fake_judge "${TMP_ROOT}/t2-judge.sh"
make_fake_bandit "${TMP_ROOT}/t2-bandit.sh"

t2_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t1-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t2-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2=1 \
  LEADV2_ROUTER_V2_BIN="${TMP_ROOT}/t2-rv2.sh" \
  LEADV2_TASK_JUDGE_BIN="${TMP_ROOT}/t2-judge.sh" \
  LEADV2_ROUTE_BANDIT_BIN="${TMP_ROOT}/t2-bandit.sh" \
  bash "${DISPATCH_BIN}" 'plugin-only v2-retired-arm T2 canonical claude- ids' 2>&1)"
t2_rc=$?

_t2_chain="$(grep 'candidate_chain' <<<"${t2_out}" | sed -n 's/.*arms=//p' | head -1)"
if [[ ${t2_rc} -eq 4 ]] || grep -q 'all_arms_not_dispatchable_v2\|all_arms_exhausted' <<<"${t2_out}"; then
  fail 'T2: canonical claude-sonnet chain collapsed to an exhaustion refusal' "rc=${t2_rc} output=${t2_out}"
elif [[ "${_t2_chain}" != *sonnet* ]] || [[ "${_t2_chain}" == *claude-sonnet* ]]; then
  fail 'T2: candidate_chain does not contain normalized "sonnet"' "chain='${_t2_chain}' output=${t2_out}"
else
  pass 'T2: claude-sonnet normalizes to sonnet and survives the filter (chain='"'${_t2_chain}'"')'
fi

# ── Terminal poison-marker assertion (proves the fence held, not just that it
#    was set — mirrors test-routing-enforcement-p1.sh Test 7).
if grep -q 'POISON:' <<<"${t1_out}${t2_out}"; then
  fail 'poison fence' 'a POISON marker appears in captured output -- a real provider bin was invoked'
else
  pass 'poison fence held -- no real provider bin invoked across T1/T2'
fi

printf '\n================================================\n'
printf '  router-v2-retired-arm suite: FAIL=%s\n' "${FAIL}"
printf '================================================\n'

exit "${FAIL}"
