#!/usr/bin/env bash
# ARM-LADDER-KIMI-RESURRECTED-01: structural drift guard.
#
# Asserts that the legacy hardcoded fallback list and the yaml-loaded ladder
# are both subsets of DISPATCHABLE_BUILD_ARMS in leadv2-glm-policy-resolve.py.
# Kimi must not appear in either list (founder order 2026-08-04, 3398d11).
#
# Anti-tautology: this test FAILS at the base commit (1b8692e) because:
#   - the legacy fallback contains kimi, which is not in DISPATCHABLE_BUILD_ARMS
#   - the yaml ladder has kimi without dispatch:false
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH="$SCRIPTS_ROOT/leadv2-dispatch-code.sh"
RESOLVER_PY="$SCRIPTS_ROOT/lib/leadv2-glm-policy-resolve.py"
ROUTING_YAML="$SCRIPTS_ROOT/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$SCRIPT_DIR/test-arm-ladder-vocabulary-drift.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Spawn fence (same preamble as the p1 suite).
_tmp_poisons="$(mktemp -d)"
for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nexit 99\n' > "${_tmp_poisons}/poison-${_arm}.sh"
  chmod +x "${_tmp_poisons}/poison-${_arm}.sh"
done
export LEADV2_DISPATCH_GLM_BIN="${_tmp_poisons}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${_tmp_poisons}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${_tmp_poisons}/poison-codex.sh"
trap 'rm -rf "${_tmp_poisons}"' EXIT

# Read DISPATCHABLE_BUILD_ARMS from the resolver via importlib (not regex).
DISPATCHABLE="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_BUILD_ARMS)))
' "$RESOLVER_PY" 2>&1)" || { echo "ERROR: cannot import DISPATCHABLE_BUILD_ARMS"; exit 1; }

# ============================================================================
# Case 1: legacy hardcoded fallback (_LADDER_IDS when yaml is absent) must be
#         a subset of DISPATCHABLE_BUILD_ARMS. Forces the fallback by pointing
#         ROUTING_YAML at /dev/null.
# ============================================================================
_legacy_list="$(sed -n '/^_load_dispatch_ladder()/,/^}$/p' "$DISPATCH" \
  | sed -n '/Fallback: legacy hardcoded/,/^  fi$/p' \
  | grep '_LADDER_IDS=' \
  | sed 's/.*_LADDER_IDS=(\(.*\)).*/\1/')"

_legacy_ok=1
for _id in ${_legacy_list}; do
  _found=0
  for _d in ${DISPATCHABLE}; do
    [[ "${_id}" == "${_d}" ]] && { _found=1; break; }
  done
  [[ "${_found}" == "1" ]] || { _legacy_ok=0; break; }
done

if [[ "${_legacy_ok}" == "1" ]]; then
  pass "case1: legacy fallback list (${_legacy_list}) ⊆ DISPATCHABLE_BUILD_ARMS (${DISPATCHABLE})"
else
  fail "case1: legacy fallback has '${_id}' not in DISPATCHABLE_BUILD_ARMS (${DISPATCHABLE})"
fi

# ============================================================================
# Case 2: yaml-loaded ladder against the production routing yaml — every entry
#         the loader yields must be in DISPATCHABLE_BUILD_ARMS. This is the
#         assertion that fails at 1b8692e (kimi has no dispatch:false).
# ============================================================================
_yaml_list="$(python3 -c '
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
ladder = (d.get("router") or {}).get("dispatch_ladder") or []
for e in ladder:
    if e.get("dispatch", True) is False:
        continue
    print(e.get("id", ""))
' "$ROUTING_YAML" 2>/dev/null)"

_yaml_ok=1
for _id in ${_yaml_list}; do
  _found=0
  for _d in ${DISPATCHABLE}; do
    [[ "${_id}" == "${_d}" ]] && { _found=1; break; }
  done
  [[ "${_found}" == "1" ]] || { _yaml_ok=0; break; }
done

if [[ "${_yaml_ok}" == "1" ]]; then
  pass "case2: yaml ladder (${_yaml_list}) ⊆ DISPATCHABLE_BUILD_ARMS (${DISPATCHABLE})"
else
  fail "case2: yaml ladder has '${_id}' not in DISPATCHABLE_BUILD_ARMS (${DISPATCHABLE})"
fi

# ============================================================================
# Case 3: kimi must not appear in either list (founder order 2026-08-04).
# ============================================================================
if [[ "${_legacy_list}" != *"kimi"* ]]; then
  pass "case3a: kimi absent from legacy fallback list"
else
  fail "case3a: kimi found in legacy fallback list — resurrected as a build arm"
fi

if [[ "${_yaml_list}" != *"kimi"* ]]; then
  pass "case3b: kimi absent from yaml-loaded ladder"
else
  fail "case3b: kimi found in yaml-loaded ladder — not filtered by dispatch:false"
fi

log ""
log "================================================"
log "  arm-ladder vocabulary-drift suite: PASS=$PASS FAIL=$FAIL"
log "================================================"

[[ "$FAIL" -eq 0 ]]
