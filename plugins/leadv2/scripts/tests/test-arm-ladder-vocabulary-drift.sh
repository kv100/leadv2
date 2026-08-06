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
for _arm in glm kimi codex subsession; do
  printf '#!/usr/bin/env bash\necho "POISON: %s invoked" >&2\nexit 99\n' "${_arm}" > "${_tmp_poisons}/poison-${_arm}.sh"
  chmod +x "${_tmp_poisons}/poison-${_arm}.sh"
done
export LEADV2_DISPATCH_GLM_BIN="${_tmp_poisons}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${_tmp_poisons}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${_tmp_poisons}/poison-codex.sh"
# ARM-LADDER-KIMI-RESURRECTED-01 follow-up (round 1b, item 1): this fence was
# missing LEADV2_DISPATCH_SUBSESSION_BIN, leaving a real subsession spawn
# reachable if this suite ever exercises the actual dispatch path rather than
# just the resolver/dispatchable-set helpers. Close the gap so no case here
# can shell out to a live provider.
export LEADV2_DISPATCH_SUBSESSION_BIN="${_tmp_poisons}/poison-subsession.sh"
export LEADV2_DISPATCH_SPAWN=0
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

# ============================================================================
# Case 4: router_v2.arms ids, after claude-<model> normalization, are a subset
#         of DISPATCHABLE_BUILD_ARMS (or advisory non-build ids). kimi must be
#         specifically absent -- ARM-LADDER-KIMI-RESURRECTED-01 follow-up: v2's
#         own registry must not resurrect a retired arm either.
# ============================================================================
_v2_arms_list="$(python3 -c '
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
arms = (d.get("router_v2") or {}).get("arms") or []
for e in arms:
    print(e.get("id", ""))
' "$ROUTING_YAML" 2>/dev/null)"

_v2_normalized_list=""
for _id in ${_v2_arms_list}; do
  case "${_id}" in
    claude-*) _norm="${_id#claude-}" ;;
    *) _norm="${_id}" ;;
  esac
  _v2_normalized_list="${_v2_normalized_list} ${_norm}"
done

# advisory ids that are legitimately in router_v2.arms but never spawn as a
# build arm: opus is intercepted as lead judgment before any spawn case;
# haiku has no spawn case today (dispatch-a24b1588 R2, tracked as a follow-up
# thread) but is not retired config the way kimi is, so it is not a
# resurrection risk -- the new dispatchable filter drops and journals it.
_v2_advisory="opus haiku"

_v2_ok=1
for _id in ${_v2_normalized_list}; do
  _found=0
  for _d in ${DISPATCHABLE} ${_v2_advisory}; do
    [[ "${_id}" == "${_d}" ]] && { _found=1; break; }
  done
  [[ "${_found}" == "1" ]] || { _v2_ok=0; break; }
done

if [[ "${_v2_ok}" == "1" && "${_v2_normalized_list}" != *"kimi"* ]]; then
  pass "case4: router_v2.arms (normalized: ${_v2_normalized_list}) ⊆ DISPATCHABLE_BUILD_ARMS ∪ advisory; kimi absent"
else
  fail "case4: router_v2.arms (normalized: ${_v2_normalized_list}) contains an id outside DISPATCHABLE_BUILD_ARMS ∪ advisory, or kimi is present"
fi

# ============================================================================
# Case 5: v1/v2 agreement -- the dispatchable set derived from
#         router.dispatch_ladder must equal the dispatchable set derived from
#         router_v2.arms (after normalization). A divergence between the two
#         independently-maintained arm registries fails here.
# ============================================================================
_v1_dispatchable_sorted="$(printf '%s\n' ${_yaml_list} | sort -u | tr '\n' ' ')"
_v2_dispatchable_only=""
for _id in ${_v2_normalized_list}; do
  for _d in ${DISPATCHABLE}; do
    [[ "${_id}" == "${_d}" ]] && { _v2_dispatchable_only="${_v2_dispatchable_only} ${_id}"; break; }
  done
done
_v2_dispatchable_sorted="$(printf '%s\n' ${_v2_dispatchable_only} | sort -u | tr '\n' ' ')"

if [[ "${_v1_dispatchable_sorted}" == "${_v2_dispatchable_sorted}" ]]; then
  pass "case5: v1 dispatchable set (${_v1_dispatchable_sorted}) == v2 dispatchable set (${_v2_dispatchable_sorted})"
else
  fail "case5: v1/v2 divergence -- v1=(${_v1_dispatchable_sorted}) v2=(${_v2_dispatchable_sorted})"
fi

# ============================================================================
# Case 6: _dispatchable_arms()'s fail-open fallback literal ("glm codex
#         sonnet") must itself be a subset of DISPATCHABLE_BUILD_ARMS. This is
#         the guard the design calls out explicitly: a broken importlib read
#         must never quietly become a second hand-kept exclusion list that
#         drifts from routing config and resurrects a retired arm (e.g. kimi)
#         through the fallback path instead of the yaml path.
# ============================================================================
_fallback_literal="$(sed -n '/^_dispatchable_arms()/,/^}$/p' "$DISPATCH" \
  | grep '_dispatchable="glm codex sonnet"' \
  | sed 's/.*_dispatchable="\(.*\)".*/\1/' | head -1)"

if [[ -z "${_fallback_literal}" ]]; then
  fail "case6: could not locate _dispatchable_arms() fail-open fallback literal in ${DISPATCH}"
else
  _fallback_ok=1
  for _id in ${_fallback_literal}; do
    _found=0
    for _d in ${DISPATCHABLE}; do
      [[ "${_id}" == "${_d}" ]] && { _found=1; break; }
    done
    [[ "${_found}" == "1" ]] || { _fallback_ok=0; break; }
  done
  if [[ "${_fallback_ok}" == "1" && "${_fallback_literal}" != *"kimi"* ]]; then
    pass "case6: _dispatchable_arms() fail-open fallback (${_fallback_literal}) ⊆ DISPATCHABLE_BUILD_ARMS; kimi absent"
  else
    fail "case6: _dispatchable_arms() fail-open fallback (${_fallback_literal}) is not ⊆ DISPATCHABLE_BUILD_ARMS, or kimi is present"
  fi
fi

# ============================================================================
# Case 7: _dispatchable_arms() runtime fail-open behaviour. When the importlib
#         read of DISPATCHABLE_BUILD_ARMS genuinely fails (lib/ missing under
#         a sandboxed SCRIPT_DIR), the function must (a) still return a usable
#         fallback set on stdout, (b) journal "dispatchable_arms_read_failed"
#         on stderr/log so the fallback is never silent, and (c) that fallback
#         must not contain a retired arm. Exercises the live function body,
#         not just the literal text (case6) -- the two together prove both
#         "the code says the right thing" and "the code does the right thing".
# ============================================================================
_c7_tmp="$(mktemp -d)"
_c7_func="$(sed -n '/^_dispatchable_arms()/,/^}$/p' "$DISPATCH")"
_c7_script="${_c7_tmp}/run.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'SCRIPT_DIR="%s/no-lib-here"\n' "${_c7_tmp}"
  printf 'SCRIPT_NAME=test-c7\n'
  printf 'log()  { printf "[%%s] %%s\\n" "$SCRIPT_NAME" "$*" >&2; }\n'
  printf 'emit() { local jtype="$1"; shift; log "$*"; }\n'
  printf '%s\n' "${_c7_func}"
  printf '_dispatchable_arms "case7-sig8"\n'
} > "${_c7_script}"
chmod +x "${_c7_script}"

_c7_stdout="$(bash "${_c7_script}" 2>"${_c7_tmp}/stderr.log")"
_c7_stderr="$(cat "${_c7_tmp}/stderr.log")"
rm -rf "${_c7_tmp}"

_c7_ok=1
_c7_reason=""
if [[ -z "${_c7_stdout}" ]]; then
  _c7_ok=0; _c7_reason="empty stdout (no fallback returned)"
elif [[ "${_c7_stdout}" == *"kimi"* ]]; then
  _c7_ok=0; _c7_reason="fallback contains kimi: '${_c7_stdout}'"
elif ! grep -q "dispatchable_arms_read_failed" <<<"${_c7_stderr}"; then
  _c7_ok=0; _c7_reason="no dispatchable_arms_read_failed journal line (stderr='${_c7_stderr}')"
else
  for _id in ${_c7_stdout}; do
    _found=0
    for _d in ${DISPATCHABLE}; do
      [[ "${_id}" == "${_d}" ]] && { _found=1; break; }
    done
    [[ "${_found}" == "1" ]] || { _c7_ok=0; _c7_reason="fallback id '${_id}' not in DISPATCHABLE_BUILD_ARMS"; break; }
  done
fi

if [[ "${_c7_ok}" == "1" ]]; then
  pass "case7: forced importlib-read failure journals dispatchable_arms_read_failed and returns fallback (${_c7_stdout}) ⊆ DISPATCHABLE_BUILD_ARMS, kimi absent"
else
  fail "case7: ${_c7_reason}"
fi

log ""
log "================================================"
log "  arm-ladder vocabulary-drift suite: PASS=$PASS FAIL=$FAIL"
log "================================================"

[[ "$FAIL" -eq 0 ]]
