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
#   T3 — ROUTER-V2-BYPASSES-ARM-LADDER-FILTER-01 site B (glm_refused_quota_gate
#        reroute): the resolver's ordered= cannot smuggle a retired arm (kimi)
#        back into the post-reroute chain.
#   T4 — site B with an all-retired ordered=: the lane FALLS BACK to the
#        pre-reroute chain (journals router_v2_reorder_failed
#        reason=no_dispatchable_arms) instead of dying at the reroute — a
#        recoverable refusal must not become a dead lane.
#   T5 — site B vocabulary: a canonical claude-sonnet id from the quota-gate
#        reroute survives as "sonnet" (T2's guard, on the sibling site).
#
# Both T1/T2 FAIL against pre-dispatch-a24b1588 HEAD: HEAD's v2 branch
# (leadv2-dispatch-code.sh, router_label == v2) does IFS=',' read straight
# from the resolver's eligible= output into candidate_arms with no filter and
# no normalization at all. T3/T4/T5 FAIL against pre-dispatch-a34485a9 HEAD:
# the quota-gate reroute read the resolver's ordered=/eligible= straight into
# candidate_arms the same way.
#
# SITE A (the LEADV2_ROUTER_V2_QUOTA_FILTER re-resolve) is deliberately NOT
# driven end-to-end here: its guard needs LEADV2_ROUTER_V2=1 AND
# router_label!=v2, but router_label is "v2" exactly when LEADV2_ROUTER_V2=1
# (leadv2-dispatch-code.sh sets it in one place, once) — the branch is
# unreachable at HEAD (founder-confirmed 2026-08-17, option a). The site is
# still rewired through _adopt_v2_chain site=quota_filter so a future guard
# fix cannot re-open the hole; its adopter coverage rides on T3/T4/T5, which
# exercise the SAME helper on the live site B.
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

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

# ── Hermeticity for the spawn-enabled T3-T5 (mirrors test-routing-enforcement-
#    p1.sh): a parent lead/dispatch session exports LEADV2_PROJECT_ROOT /
#    LEADV2_LANE_WORK_ROOT pointing at the REAL repo — inherited, they leak
#    live registry state into the sandbox and can block on real file locks.
unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME LEADV2_EXCLUDED_ARMS
# Skip the post-spawn early-verdict poll window (stub bins never report
# "complete"; the poll would sleep the full default per attempted spawn).
export LEADV2_ARM_EARLY_VERDICT_S=0

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

# ============================================================================
# T3/T4/T5: the glm_refused_quota_gate reroute (site B) — ROUTER-V2-BYPASSES-
# ARM-LADDER-FILTER-01. Driven in v1 router mode (LEADV2_ROUTER_V2 unset):
# site B is router-label-independent, so the v1 ladder (glm,codex,sonnet)
# builds the chain, the fake GLM bin refuses with the quota_gate marker, and
# the reroute consults the stubbed LEADV2_ROUTER_V2_BIN. Spawn is ENABLED for
# these three (LEADV2_DISPATCH_SPAWN=1 overrides the suite fence) — the
# reroute only fires from inside the candidate loop.
# ============================================================================
make_qg_rv2() {  # <path> <eligible> <ordered> — resolve --chain stub for site B
  local path="$1" eligible="$2" ordered="$3"
  cat > "${path}" <<SH
#!/usr/bin/env bash
case "\${1:-}" in
  resolve) printf 'eligible=${eligible}\nordered=${ordered}\nheadroom={}\nvector=[]\ncredits={}\n' ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${path}"
}

make_refusing_glm() {  # quota_gate admission refusal (marker + rc 1 contract)
  local path="$1"
  cat > "${path}" <<'SH'
#!/usr/bin/env bash
echo '[glm-quota-gate] LEADV2_DISPATCH_REFUSED: quota_gate' >&2
exit 1
SH
  chmod +x "${path}"
}

make_qg_root() {  # v1 tenant root: ladder glm,codex,sonnet; router_v2 unused
  make_tenant_root "${TMP_ROOT}/$1-root" "  arms:
    - id: claude-sonnet
      channel: claude-subsession.sh
      model: sonnet
      bucket: anthropic:max_20x"
}

make_refusing_glm "${TMP_ROOT}/qg-refusing-glm.sh"

# ── T3: retired arm (kimi) in the reroute's ordered= is dropped (router=v2,
#    site=quota_gate), sonnet survives, no kimi spawn is ever attempted.
make_qg_root t3
make_qg_rv2 "${TMP_ROOT}/t3-rv2.sh" "glm,kimi" "kimi,sonnet"

t3_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t3-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t3-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2_BIN="${TMP_ROOT}/t3-rv2.sh" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/qg-refusing-glm.sh" \
  LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" 'plugin-only v2-retired-arm T3 quota-gate reroute drops kimi' 2>&1)"
t3_rc=$?

_t3_ordered="$(grep 'route_headroom_chosen' <<<"${t3_out}" | sed -n 's/.*after=glm_quota_gate ordered=//p' | head -1 | cut -d' ' -f1)"
if ! grep -q 'arm_dropped_not_dispatchable arm=kimi.*router=v2.*site=quota_gate' <<<"${t3_out}"; then
  fail 'T3: no arm_dropped_not_dispatchable line for kimi (router=v2 site=quota_gate)' "output=${t3_out}"
elif [[ -z "${_t3_ordered}" ]]; then
  fail 'T3: no post-reroute route_headroom_chosen ordered= line' "rc=${t3_rc} output=${t3_out}"
elif grep -q 'kimi' <<<"${_t3_ordered}" || grep -q 'model=kimi' <<<"${t3_out}"; then
  fail 'T3: kimi survived into the post-reroute chain or was spawned' "ordered='${_t3_ordered}' output=${t3_out}"
else
  pass 'T3: quota-gate reroute drops kimi (router=v2 site=quota_gate), chain='"${_t3_ordered}"
fi

# ── T4: stub returns ONLY retired arms -> adopt empties -> the lane falls back
#    to the pre-reroute chain (codex,sonnet both attempted) instead of dying at
#    the reroute. journals router_v2_reorder_failed reason=no_dispatchable_arms.
make_qg_root t4
make_qg_rv2 "${TMP_ROOT}/t4-rv2.sh" "kimi" "kimi"

t4_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t4-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t4-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2_BIN="${TMP_ROOT}/t4-rv2.sh" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/qg-refusing-glm.sh" \
  LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" 'plugin-only v2-retired-arm T4 all-retired reroute falls back' 2>&1)"
t4_rc=$?

if ! grep -q 'router_v2_reorder_failed task=.* rc=0 reason=no_dispatchable_arms' <<<"${t4_out}"; then
  fail 'T4: no router_v2_reorder_failed reason=no_dispatchable_arms line' "output=${t4_out}"
elif ! grep -q 'dispatch_rolled_back reason=all_arms_not_dispatchable_v2.*site=quota_gate' <<<"${t4_out}"; then
  fail 'T4: no dispatch_rolled_back all_arms_not_dispatchable_v2 site=quota_gate line' "output=${t4_out}"
elif ! grep -q 'spawn_failed by=router model=codex' <<<"${t4_out}" \
   || ! grep -q 'spawn_failed by=router model=sonnet' <<<"${t4_out}"; then
  fail 'T4: lane died at the reroute instead of falling back to the pre-reroute chain' "rc=${t4_rc} output=${t4_out}"
elif grep -q 'model=kimi' <<<"${t4_out}"; then
  fail 'T4: kimi was attempted despite the all-retired adopt' "output=${t4_out}"
else
  pass 'T4: all-retired reroute falls back to the pre-reroute chain (codex+sonnet attempted, no dead lane)'
fi

# ── T5: canonical claude-sonnet id from the reroute normalizes to sonnet and
#    survives the filter (T2's guard on site B — the naive intersect would
#    have emptied the chain here too).
make_qg_root t5
make_qg_rv2 "${TMP_ROOT}/t5-rv2.sh" "claude-sonnet" "claude-sonnet"

t5_out="$(CLAUDE_PROJECT_ROOT="${TMP_ROOT}/t5-root" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/t5-cache" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2_BIN="${TMP_ROOT}/t5-rv2.sh" \
  LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/qg-refusing-glm.sh" \
  LEADV2_DISPATCH_SPAWN=1 \
  bash "${DISPATCH_BIN}" 'plugin-only v2-retired-arm T5 quota-gate claude-sonnet normalizes' 2>&1)"
t5_rc=$?

_t5_ordered="$(grep 'route_headroom_chosen' <<<"${t5_out}" | sed -n 's/.*after=glm_quota_gate ordered=//p' | head -1 | cut -d' ' -f1)"
if [[ -z "${_t5_ordered}" ]]; then
  fail 'T5: no post-reroute route_headroom_chosen ordered= line (claude-sonnet dropped instead of normalized?)' "rc=${t5_rc} output=${t5_out}"
elif [[ "${_t5_ordered}" != *sonnet* ]] || [[ "${_t5_ordered}" == *claude-sonnet* ]]; then
  fail 'T5: post-reroute chain does not contain normalized "sonnet"' "ordered='${_t5_ordered}' output=${t5_out}"
elif grep -q 'arm_dropped_not_dispatchable arm=sonnet' <<<"${t5_out}"; then
  fail 'T5: normalized sonnet was wrongly dropped' "output=${t5_out}"
else
  pass 'T5: quota-gate reroute normalizes claude-sonnet -> sonnet (ordered='"${_t5_ordered}"')'
fi

# ── Terminal poison-marker assertion (proves the fence held, not just that it
#    was set — mirrors test-routing-enforcement-p1.sh Test 7).
if grep -q 'POISON:' <<<"${t1_out}${t2_out}${t3_out}${t4_out}${t5_out}"; then
  fail 'poison fence' 'a POISON marker appears in captured output -- a real provider bin was invoked'
else
  pass 'poison fence held -- no real provider bin invoked across T1/T2/T3/T4/T5'
fi

printf '\n================================================\n'
printf '  router-v2-retired-arm suite: FAIL=%s\n' "${FAIL}"
printf '================================================\n'

exit "${FAIL}"
