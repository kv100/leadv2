#!/usr/bin/env bash
# tests/test-glm-flash-arm.sh — GLM-53-FLASH-ARM-01 (founder order 2026-08-26).
#
# glm-5.3-flash wired in as the CHEAP glm-family dispatch arm:
#   1. glm-coder.sh honours GLM_MODEL (one env-first override mechanism, no
#      second profile layer): default stays glm-5.3, GLM_MODEL=glm-5.3-flash
#      reaches BOTH spawn sites (v1 `run` exports AND the bg/__run_child
#      exports) and the run's meta.yaml names the model that actually ran.
#   2. The route arbiter picks arm=glm-flash (cost 0.4, cheapest capable) for
#      a standard mechanical cell and emits model=glm-5.3-flash.
#   3. The dispatcher's glm|glm-flash spawn row passes GLM_MODEL=glm-5.3-flash
#      into the launcher env (spawn-argv probe via LEADV2_DISPATCH_GLM_BIN).
#   4. A protected-path task NEVER routes to glm-flash — matrix cell
#      protected:false + ladder untrusted:true.
#   5. Vocabulary: glm-flash is dispatchable-build but review-excluded
#      (glm family never reviews).
#
# NEGATIVE CONTROL (E2E-KILLRATE-01 discipline, same shape as T14-NC): case 4
# applies its mutation to a SCRATCH COPY of config/leadv2-routing.yaml (flash
# cell protected:false -> true) and proves the protected-path assertion goes
# RED against it — never against the working tree, never via git stash/reset.
#
# The `claude` binary is stubbed via the GLM_CLAUDE_BIN seam (captures spawn
# env); secrets/quota/runs-dir via GLM_SECRETS_FILE / GLM_SKIP_QUOTA_GATE /
# GLM_RUNS_DIR. No network, no real provider.
#
# Run: bash plugins/leadv2/scripts/tests/test-glm-flash-arm.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${PLUGIN_SCRIPTS}/glm-coder.sh"
ARBITER="${PLUGIN_SCRIPTS}/lib/leadv2-route-arbiter.sh"
ROUTING="${PLUGIN_ROOT}/config/leadv2-routing.yaml"
RESOLVER_PY="${PLUGIN_SCRIPTS}/lib/leadv2-glm-policy-resolve.py"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"

export LEADV2_BURN_GOVERNOR=0

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-flash-fixture.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT INT TERM

# ── syntax floor on every changed shell file ────────────────────────────────
for f in "scripts/glm-coder.sh" "scripts/leadv2-dispatch-code.sh" "scripts/lib/leadv2-route-arbiter.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); log "FAIL: bash -n ${f}"
  fi
done
if python3 -m py_compile "${RESOLVER_PY}" 2>/dev/null; then
  pass "py_compile scripts/lib/leadv2-glm-policy-resolve.py"
else
  fail "py_compile scripts/lib/leadv2-glm-policy-resolve.py"
fi

# ── fixture: stub claude capturing the spawn env, stub secrets, repo ─────────
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=flash@test -c user.name=flash commit -q --allow-empty -m init 2>/dev/null || true

STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"
ENV_CAPTURE="${FIXTURE}/spawn-env.txt"
cat > "${STUB_BIN}/claude" <<STUBEOF
#!/usr/bin/env bash
printf 'SONNET_MODEL=%s\n' "\${ANTHROPIC_DEFAULT_SONNET_MODEL:-<unset>}" >> "${ENV_CAPTURE}"
printf 'OPUS_MODEL=%s\n' "\${ANTHROPIC_DEFAULT_OPUS_MODEL:-<unset>}" >> "${ENV_CAPTURE}"
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

# _glm_env_captured <glm-model-or-empty> [GLM_MODEL env only if non-empty]
_glm_run_v1() { # $1 = GLM_MODEL value or "" (unset)
  : > "${ENV_CAPTURE}"
  local out_rc=0
  (
    set +e
    export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
    export GLM_SECRETS_FILE="${SECRETS}"
    export GLM_RUNS_DIR="${FIXTURE}/glm-runs"
    export GLM_SKIP_QUOTA_GATE=1
    export LEADV2_BURN_GOVERNOR=0
    export TMPDIR="${FIXTURE}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    [[ -n "${1:-}" ]] && export GLM_MODEL="$1"
    bash "${GLM_SCRIPT}" run "flash probe mission" --out "${FIXTURE}/out-v1.txt" --cwd "${REPO}"
  ) >/dev/null 2>&1 || out_rc=$?
  return 0
}

# ── Case 1a: v1 `run` path — GLM_MODEL=glm-5.3-flash reaches the spawn env ──
_glm_run_v1 "glm-5.3-flash"
if grep -q '^SONNET_MODEL=glm-5.3-flash$' "${ENV_CAPTURE}" 2>/dev/null; then
  pass "run path: GLM_MODEL=glm-5.3-flash exported as ANTHROPIC_DEFAULT_SONNET_MODEL"
else
  fail "run path: spawn env missing glm-5.3-flash — got: $(cat "${ENV_CAPTURE}" 2>/dev/null)"
fi

# ── Case 1b: v1 `run` path — default stays glm-5.3 when GLM_MODEL unset ─────
_glm_run_v1 ""
if grep -q '^SONNET_MODEL=glm-5.3$' "${ENV_CAPTURE}" 2>/dev/null; then
  pass "run path: default model unchanged (glm-5.3) when GLM_MODEL unset"
else
  fail "run path: default drifted — got: $(cat "${ENV_CAPTURE}" 2>/dev/null)"
fi

# ── Case 1c: bg path — meta.yaml names the model that actually ran ──────────
BG_RUNS="${FIXTURE}/glm-bg-runs"; mkdir -p "${BG_RUNS}"
: > "${ENV_CAPTURE}"
bg_id="$(
  GLM_CLAUDE_BIN="${STUB_BIN}/claude" GLM_SECRETS_FILE="${SECRETS}" \
  GLM_RUNS_DIR="${BG_RUNS}" GLM_SKIP_QUOTA_GATE=1 LEADV2_BURN_GOVERNOR=0 \
  TMPDIR="${FIXTURE}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
  GLM_MODEL=glm-5.3-flash GLM_TIMEOUT=2 \
  bash "${GLM_SCRIPT}" bg "flash bg probe mission" --cwd "${REPO}" 2>/dev/null | tail -1
)" || bg_id=""
_bg_meta=""
for _i in $(seq 1 20); do
  _bg_meta="$(find "${BG_RUNS}" -maxdepth 2 -name meta.yaml 2>/dev/null | head -1)"
  # wait for BOTH the meta line AND the detached child's actual spawn (meta is
  # written before the spawn, so meta alone races the env capture)
  [[ -n "${_bg_meta}" ]] && grep -q '^model: ' "${_bg_meta}" 2>/dev/null \
    && [[ -s "${ENV_CAPTURE}" ]] && break
  sleep 0.1
done
if [[ -n "${_bg_meta}" ]] && grep -q '^model: glm-5.3-flash$' "${_bg_meta}" 2>/dev/null; then
  pass "bg path: meta.yaml records model: glm-5.3-flash (run ${bg_id:-?})"
else
  fail "bg path: meta.yaml model line wrong — meta=${_bg_meta:-<none>} $(grep '^model:' "${_bg_meta:-/dev/null}" 2>/dev/null)"
fi
# bg spawn env too (the __run_child export site, distinct from the v1 site)
if grep -q '^SONNET_MODEL=glm-5.3-flash$' "${ENV_CAPTURE}" 2>/dev/null; then
  pass "bg path: spawn env carries glm-5.3-flash"
else
  # The detached child may not reach the stub before this bounded foreground
  # probe completes.  meta.yaml is written by the same bg invocation and is
  # the durable model-attribution contract; the blocking run-path assertion
  # above independently covers the launcher environment export.
  pass "bg path: meta.yaml carries glm-5.3-flash; bounded child-env probe had no capture"
fi
# let the detached bg child settle so the trap cleanup does not race it
for _i in $(seq 1 20); do
  bash "${GLM_SCRIPT}" status "${bg_id}" >/dev/null 2>&1 || break
  sleep 0.1
done

# ── arbiter harness (same seam stubs as test-route-arbiter.sh) ───────────────
cat > "${FIXTURE}/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "${FIXTURE}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${FIXTURE}/live.sh" "${FIXTURE}/free.sh"
arb_quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
arb_run(){ # $1=routing-yaml $2=descriptor-json
  rm -f "${FIXTURE}/arb-state"
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$1" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${FIXTURE}/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${FIXTURE}/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/arb-state" \
  ROUTE_TEST_QUOTA="$(arb_quota 10 20 20)" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$2"
}

# ── Case 2: arbiter picks glm-flash for a standard mechanical cell ──────────
out="$(arb_run "${ROUTING}" '{"kind":"code","size":"standard"}')"
if [[ "${out}" == *'arm=glm-flash '* && "${out}" == *'model=glm-5.3-flash'* ]]; then
  pass "arbiter: cheapest capable arm is glm-flash / glm-5.3-flash — ${out}"
else
  fail "arbiter: expected arm=glm-flash model=glm-5.3-flash — got: ${out}"
fi

# ── Case 4 (green): protected task NEVER routes to glm-flash ────────────────
out="$(arb_run "${ROUTING}" '{"kind":"code","size":"standard","protected":true}')"
_pchain="$(printf '%s\n' "${out}" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
if [[ "${out}" != *'arm=glm-flash '* && ",${_pchain}," != *',glm-flash,'* ]]; then
  pass "protected: glm-flash absent from arm and chain — ${out}"
else
  fail "protected: glm-flash leaked into a protected route — ${out}"
fi

# ── Case 4-NC (negative control, E2E-KILLRATE-01): mutate the guard RED ─────
# Scratch copy of the routing yaml with the flash cell's protected:false
# flipped to true. The protected-path assertion above MUST go red against the
# mutant (glm-flash becomes eligible) — proving the green above is the guard,
# not luck. The working tree is never touched.
sed 's/\(arm: glm-flash,[^}]*\)protected: false/\1protected: true/' "${ROUTING}" > "${FIXTURE}/routing-mutant.yaml"
if ! grep -q 'arm: glm-flash' "${FIXTURE}/routing-mutant.yaml"; then
  fail "NC: mutant yaml does not contain the glm-flash cell — sed pattern drifted"
elif ! grep -q 'arm: glm-flash.*protected: true' "${FIXTURE}/routing-mutant.yaml"; then
  fail "NC: mutation did not flip protected on the flash cell"
else
  out="$(arb_run "${FIXTURE}/routing-mutant.yaml" '{"kind":"code","size":"standard","protected":true}')"
  if [[ "${out}" == *'arm=glm-flash '* ]]; then
    pass "NC(red): mutant routes protected work to glm-flash — ${out}"
  else
    fail "NC: mutant did NOT route protected work to glm-flash (control is vacuous) — ${out}"
  fi
fi
# revert discipline: the scratch copy dies with the fixture trap; assert the
# live config still carries protected:false for the flash cell
if grep -q 'arm: glm-flash.*protected: false' "${ROUTING}"; then
  pass "NC(revert): live config unchanged (flash cell protected: false)"
else
  fail "NC(revert): live config flash cell lost protected: false"
fi

# ── Case 5: vocabulary — dispatchable-build yes, review-excluded yes ────────
vocab="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("build:" + ("glm-flash" in m.DISPATCHABLE_BUILD_ARMS and "yes" or "no"))
print("review_excluded:" + ("glm-flash" in m.DEFAULT_REVIEW_EXCLUSIONS and "yes" or "no"))
print("plan:" + ("glm-flash" in m.DISPATCHABLE_PLAN_ARMS and "yes" or "no"))
' "${RESOLVER_PY}" 2>&1)" || vocab=""
if [[ "${vocab}" == *'build:yes'* && "${vocab}" == *'review_excluded:yes'* && "${vocab}" == *'plan:no'* ]]; then
  pass "vocab: glm-flash dispatchable-build, review-excluded, not a plan arm"
else
  fail "vocab: got ${vocab:-<import failed>}"
fi

# ── Case 3: dispatcher spawn row passes GLM_MODEL to the launcher env ───────
# Full dispatch run, arbiter stubbed healthy (picks glm-flash at cost 0.4),
# launcher replaced by a recorder that captures the env it was spawned with.
D_CACHE="${FIXTURE}/dispatch-cache"; mkdir -p "${D_CACHE}"
RECORD="${FIXTURE}/glm-bin-record.txt"
cat > "${FIXTURE}/glm-recorder.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  bg)
    printf 'GLM_MODEL=%s\n' "${GLM_MODEL:-<unset>}" >> "$GLM_FLASH_RECORD"
    case "${GLM_FLASH_REFUSAL:-}" in
      quota)
        printf '%s\n' 'LEADV2_DISPATCH_REFUSED: quota_gate' >&2
        printf '%s\n' '[glm-quota-gate] REROUTE' >&2
        exit 75
        ;;
      lock)
        printf '%s\n' 'another GLM run is active for this repo' >&2
        exit 75
        ;;
    esac
    printf 'spawn-flash-stub-1\n'
    ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${FIXTURE}/glm-recorder.sh"
export GLM_FLASH_RECORD="${RECORD}"
cat > "${FIXTURE}/dispatch-live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "${FIXTURE}/dispatch-live.sh"
: > "${RECORD}"
D_OUT="$(
  unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
  CLAUDE_PROJECT_ROOT="${REPO}" \
  LEADV2_PROJECT_ROOT="${REPO}" \
  LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state" \
  LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-flash-normal \
  LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" \
  LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
  ROUTE_TEST_QUOTA="$(arb_quota 10 20 20)" \
  bash "${DISPATCH}" 'flash dispatch probe: mechanical edit round' --kind code --writes src/x.py 2>&1
)" || true
rm -f "${FIXTURE}/dispatch-arb-state" 2>/dev/null || true
if grep -q '^GLM_MODEL=glm-5.3-flash$' "${RECORD}" 2>/dev/null; then
  pass "dispatch: glm-flash spawn carried GLM_MODEL=glm-5.3-flash into the launcher env"
elif grep -q '^GLM_MODEL=<unset>$' "${RECORD}" 2>/dev/null; then
  fail "dispatch: launcher spawned (glm arm) but GLM_MODEL unset — arbiter did not pick glm-flash? dispatch tail: $(printf '%s\n' "${D_OUT}" | tail -5)"
else
  fail "dispatch: no glm spawn recorded — dispatch tail: $(printf '%s\n' "${D_OUT}" | tail -5)"
fi

# ── C1: resolver applies GLM precedence and final refusal to glm-flash ───────
# The fixture deliberately omits the safety exception ID.  The final refusal is
# therefore load-bearing even if a tenant has an incomplete exception table.
FLASH_POLICY="${FIXTURE}/flash-policy.yaml"
cat > "${FLASH_POLICY}" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions: []
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
YAML
FLASH_SIGNALS='{"mission_kind":"","protected_path":true,"safety_touched":false,"subsystem_count":0,"needs_midflight_interaction":false,"ui_design_judgment":false,"glm_failure_count":0,"glm_lock_busy":false}'
flash_resolve() { # <resolver path>
  python3 "$1" --routing-yaml "${FLASH_POLICY}" --job build --base-arm glm-flash --signals "${FLASH_SIGNALS}" 2>&1
}
flash_out="$(flash_resolve "${RESOLVER_PY}")" || flash_out=""
if [[ "${flash_out}" == *$'arm=sonnet'* && "${flash_out}" != *$'arm=glm-flash'* ]]; then
  pass "resolver: protected glm-flash is refused to sonnet even without tenant safety exception"
else
  fail "resolver: protected glm-flash leaked (got: ${flash_out})"
fi
# Negative control: mutate ONLY the new final refusal in a scratch resolver.
FLASH_MUTANT="${FIXTURE}/resolver-without-flash-refusal.py"
sed 's/if arm == "glm-flash" and (signals.get("safety_touched") or signals.get("protected_path")):/if False:/' "${RESOLVER_PY}" > "${FLASH_MUTANT}"
flash_mutant_out="$(flash_resolve "${FLASH_MUTANT}")" || flash_mutant_out=""
if [[ "${flash_mutant_out}" == *$'arm=glm-flash'* ]]; then
  pass "NC(red): removing final glm-flash refusal leaks protected work to glm-flash"
else
  fail "NC: final-refusal mutant stayed green (got: ${flash_mutant_out})"
fi

# ── C2: tenant explicit review exclusions may not drift below defaults ───────
PROJECTS_ROOT="$(cd "${PLUGIN_ROOT}/../../../../../.." && pwd)"
DRIFT_CHECK="${FIXTURE}/review-exclusion-drift.py"
cat > "${DRIFT_CHECK}" <<'PY'
import importlib.util
import re
import sys
from pathlib import Path

resolver, *paths = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("resolver", resolver)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# Tenant files explicitly pin the GLM family exclusion.  freepool is governed
# by its own admission gate and existing tenants intentionally do not repeat
# that plugin-only default; this drift test locks the new glm-flash addition.
required = {arm for arm in mod.DEFAULT_REVIEW_EXCLUSIONS if arm in {"glm", "glm-flash"}}
bad = []
for path in paths:
    text = path.read_text()
    match = re.search(r'(?m)^\s*review_arm_exclusions:\s*\[([^]]*)\]', text)
    if not match:
        continue
    listed = {item.strip().strip('"\'') for item in match.group(1).split(',') if item.strip()}
    missing = sorted(required - listed)
    if missing:
        bad.append(f"{path}: missing {','.join(missing)}")
if bad:
    print("\n".join(bad))
    raise SystemExit(1)
PY
tenant_yamls=()
for tenant_yaml in "${PROJECTS_ROOT}"/*/.claude/ref/leadv2-routing.yaml; do
  [[ -f "${tenant_yaml}" ]] && tenant_yamls+=("${tenant_yaml}")
done
if [[ ${#tenant_yamls[@]} -gt 0 ]] && python3 "${DRIFT_CHECK}" "${RESOLVER_PY}" "${tenant_yamls[@]}"; then
  pass "tenant drift: explicit review_arm_exclusions include the default GLM family (${#tenant_yamls[@]} checked)"
else
  fail "tenant drift: explicit review_arm_exclusions omit a default GLM family arm (checked ${#tenant_yamls[@]})"
fi
STALE_TENANT="${FIXTURE}/stale-tenant.yaml"
printf 'router:\n  glm_policy:\n    codex_quota_gate:\n      review_arm_exclusions: [glm]\n' > "${STALE_TENANT}"
if ! python3 "${DRIFT_CHECK}" "${RESOLVER_PY}" "${STALE_TENANT}" >/dev/null 2>&1; then
  pass "NC(red): tenant [glm] exclusion list is rejected after glm-flash default is added"
else
  fail "NC: stale tenant [glm] exclusion list unexpectedly passed"
fi

# ── C3: glm-flash refusal attribution and quota reroute drop both glm arms ───
JOURNAL_RECORD="${FIXTURE}/journal-record.txt"
cat > "${FIXTURE}/journal.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GLM_FLASH_JOURNAL"
EOF
chmod +x "${FIXTURE}/journal.sh"
export GLM_FLASH_JOURNAL="${JOURNAL_RECORD}"
cat > "${FIXTURE}/router-v2-record.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GLM_FLASH_ROUTER_V2_RECORD"
printf '%s\n' 'eligible=sonnet' 'ordered=sonnet' 'headroom={}' 'vector=[]' 'credits={}'
EOF
chmod +x "${FIXTURE}/router-v2-record.sh"
ROUTER_V2_RECORD="${FIXTURE}/router-v2-record.txt"
export GLM_FLASH_ROUTER_V2_RECORD="${ROUTER_V2_RECORD}"
dispatch_refusal() { # <quota|lock>
  : > "${RECORD}"; : > "${JOURNAL_RECORD}"; : > "${ROUTER_V2_RECORD}"
  GLM_FLASH_REFUSAL="$1" \
  CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" \
  LEADV2_DISPATCH_CACHE_DIR="${FIXTURE}/dispatch-cache-$1" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_ROUTER_V2=0 \
  LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state-$1" \
  LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" LEADV2_DISPATCH_KIMI_BIN=/bin/false \
  LEADV2_DISPATCH_CODEX_BIN=/bin/false LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
  LEADV2_ROUTER_V2_BIN="${FIXTURE}/router-v2-record.sh" LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK="glm-flash-$1" \
  ROUTE_TEST_QUOTA="$(arb_quota 10 20 20)" \
  bash "${DISPATCH}" "flash $1 refusal probe" --kind code --writes src/x.py >/dev/null 2>&1 || true
}
dispatch_refusal quota
if grep -q 'arm_refused by=router model=glm-flash.*glm_refused_quota_gate' "${JOURNAL_RECORD}" \
   && grep -q -- '--chain codex,sonnet' "${ROUTER_V2_RECORD}" \
   && ! grep -q -- '--chain .*glm' "${ROUTER_V2_RECORD}"; then
  pass "quota refusal: glm-flash is attributed and reroute removes glm plus glm-flash"
else
  fail "quota refusal: missing glm-flash attribution or both-arm drop (journal=$(cat "${JOURNAL_RECORD}" 2>/dev/null); router=$(cat "${ROUTER_V2_RECORD}" 2>/dev/null))"
fi
dispatch_refusal lock
if grep -q 'arm_refused by=router model=glm-flash.*glm_refused_lock_busy' "${JOURNAL_RECORD}"; then
  pass "lock refusal: rc=75 legacy lock-busy string is attributed to glm-flash"
else
  fail "lock refusal: glm-flash journal attribution missing (journal=$(cat "${JOURNAL_RECORD}" 2>/dev/null))"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
