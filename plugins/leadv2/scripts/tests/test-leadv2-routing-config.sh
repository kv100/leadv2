#!/usr/bin/env bash
# tests/test-leadv2-routing-config.sh — PLUGIN-REPO-CARRIES-A-SHADOW-ROUTING-CONFIG-01
# (row 85e7878c), 2026-09-10.
#
# Pins the ONE-resolver + merge contract that ended the shadow-routing defect:
# a tenant file at <root>/.claude/ref/leadv2-routing.yaml used to SUBSTITUTE
# plugins/leadv2/config/leadv2-routing.yaml wholesale (in the plugin repo the
# copy was 229 lines behind canonical), so orders written into canonical did
# not act. Now lib/leadv2-routing-config.sh merges the tenant DELTA over the
# canonical registry and materializes the result.
#
# Fixtures (each maps to a named acceptance row of the brief):
#   C1  main: a CANONICAL cell edit flips the dispatch ladder decision with a
#       tenant file present and untouched (today's live failure, inverted).
#   C2  paired: the same edit in the TENANT wins over canonical.
#   C3  no tenant file: resolver returns the canonical path itself,
#       byte-for-byte (the unchanged behaviour of the three live repos).
#   C4  live delta: this repo's protected_path_patterns stay a SUPERSET of the
#       canonical defaults; a miss is named, not counted.
#   C5  broken tenant: LOUD refusal naming the file, no silent canonical
#       fallback.
#   C6  cache: stable across processes; a SAME-SIZE canonical edit rebuilds
#       (content-keyed, immune to mtime second-granularity); no tmp leftovers.
#   C7  no root: named refusal (rc=3), not PWD luck.
#   C8  real repo shape: canonical and tenant in ONE repo merge and parse;
#       journal line exactly once per build, quiet on a cache hit.
#   C9  list-replace: a tenant list REPLACES, never unions (a tenant must be
#       able to remove a row, not only add one).
#   C10 env override: LEADV2_ROUTING_YAML is returned as-is (hermetic-test
#       seam preserved from every pre-merge reader).
#
# Hermetic: scratch dirs, fixture canonical via LEADV2_ROUTING_YAML_PLUGIN_
# OVERRIDE (the resolver's canonical-tier seam), fixture cache via
# LEADV2_ROUTING_CONFIG_CACHE_DIR. No network, no live quota.
# run-all-triggers: leadv2-routing-config leadv2-routing.yaml leadv2-routing-merge.py leadv2-dispatch-code leadv2-dispatch-product-close leadv2-review-run leadv2-plan-run leadv2-router-v2 leadv2-router codex-task leadv2-cost-estimate leadv2-glm-policy-resolve.py

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-routing-config.sh"
# tests -> scripts -> leadv2 -> plugins -> REPO ROOT: four levels up.
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
[[ -f "${REPO_ROOT}/plugins/leadv2/config/leadv2-routing.yaml" ]] \
  || { echo "ERROR: REPO_ROOT resolved wrong: ${REPO_ROOT}"; exit 1; }
LIVE_CANONICAL="${REPO_ROOT}/plugins/leadv2/config/leadv2-routing.yaml"
LIVE_DELTA="${REPO_ROOT}/.claude/ref/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

bash -n "$LIB" || { echo "ERROR: resolver syntax"; exit 1; }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t lv2rcm)"; trap 'rm -rf "$ROOT"' EXIT

CANON="${ROOT}/canonical.yaml"
TENANT_ROOT="${ROOT}/repo"
mkdir -p "${TENANT_ROOT}/.claude/ref"
CACHE="${ROOT}/cache"; mkdir -p "$CACHE"

canonical_v1() {
  cat > "$CANON" <<'YAML'
router:
  dispatch_ladder:
    - id: codex
      provider: codex
      when: [all]
    - id: sonnet
      provider: anthropic
      when: [all]
  glm_policy:
    protected_path_patterns:
      - "*safety*"
    sonnet_exceptions: []
router_v2:
  active_account: max_test
YAML
}
# Same bytes as v1 EXCEPT the two ladder ids swap -- a SAME-SIZE cell edit in
# the canonical file, exactly the shape the live defect used.
canonical_v2() {
  cat > "$CANON" <<'YAML'
router:
  dispatch_ladder:
    - id: sonnet
      provider: codex
      when: [all]
    - id: codex
      provider: anthropic
      when: [all]
  glm_policy:
    protected_path_patterns:
      - "*safety*"
    sonnet_exceptions: []
router_v2:
  active_account: max_test
YAML
}

# resolve <tenant-root> -> prints path; env baked per call.
resolve() {
  LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE="$CANON" \
  LEADV2_ROUTING_CONFIG_CACHE_DIR="$CACHE" \
  LEADV2_ROUTING_YAML="${LV2_RC_ENV:-}" \
    bash -c 'source "$1"; leadv2_routing_config_path "$2"' _ "$LIB" "$1" 2>/dev/null
}

# The dispatch-decision probe: first dispatch_ladder arm, parsed exactly the
# way leadv2-dispatch-code.sh parses its ladder (yaml.safe_load, first row).
ladder_first() {
  python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
ladder = (d.get("router") or {}).get("dispatch_ladder") or []
print(ladder[0].get("id", "") if ladder else "")
' "$1"
}

merged_patterns() {
  python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
pats = ((d.get("router") or {}).get("glm_policy") or {}).get("protected_path_patterns") or []
for p in pats: print(p)
' "$1"
}

# ── C1: canonical cell edit flips the decision, tenant untouched ─────────────
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "*safety*"\n      - "*onlymine*"\n' \
  > "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml"
canonical_v1
p1="$(resolve "$TENANT_ROOT")" || { fail "C1 resolve v1" "resolver rc!=0"; p1=""; }
[[ "${p1}" == "$CACHE/"* ]] && pass "C1a: tenant present -> MATERIALIZED merged path" \
  || fail "C1a: merged path" "got '${p1}'"
tenant_before="$(cksum < "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml")"
d1="$(ladder_first "$p1")"
[[ "$d1" == "codex" ]] && pass "C1b: v1 dispatch decision = codex (canonical cell)" \
  || fail "C1b: v1 decision" "expected codex, got '${d1}'"
canonical_v2   # SAME-SIZE cell edit in CANONICAL only; tenant untouched
p2="$(resolve "$TENANT_ROOT")" || { fail "C1 resolve v2" "resolver rc!=0"; p2=""; }
d2="$(ladder_first "$p2")"
[[ "$d2" == "sonnet" ]] \
  && pass "C1c: canonical edit (tenant untouched) flips decision codex->sonnet" \
  || fail "C1c: MAIN FIXTURE" "canonical edit changed nothing: still '${d2}' (the pre-fix substitution behaviour)"
[[ "$(cksum < "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml")" == "$tenant_before" ]] \
  && pass "C1d: tenant file byte-identical across the canonical edit" \
  || fail "C1d: tenant untouched" "tenant file changed during C1"

# ── C2: the same edit in the TENANT wins over canonical ──────────────────────
canonical_v1
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "*safety*"\n      - "*onlymine*"\n  dispatch_ladder:\n    - id: glm\n      provider: glm\n      when: [all]\n' \
  > "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml"
t1="$(resolve "$TENANT_ROOT")"
[[ "$(ladder_first "$t1")" == "glm" ]] && pass "C2a: tenant ladder wins over canonical" \
  || fail "C2a: tenant wins" "expected glm, got '$(ladder_first "$t1")'"
# same-size cell edit in the TENANT (glm->kimi, 3 bytes->3 bytes), canonical
# untouched. Python rewrite, not sed -i: BSD and GNU -i differ.
python3 - "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p).read()
assert s.count("id: glm") == 1
io.open(p, "w").write(s.replace("id: glm", "id: kimi"))
PY
t2="$(resolve "$TENANT_ROOT")"
[[ "$(ladder_first "$t2")" == "kimi" ]] && pass "C2b: tenant edit flips decision glm->kimi" \
  || fail "C2b: tenant edit" "expected kimi, got '$(ladder_first "$t2")'"

# ── C3: no tenant file -> canonical as-is, byte-for-byte ─────────────────────
NOTENANT="${ROOT}/notenant"; mkdir -p "$NOTENANT"
p3="$(resolve "$NOTENANT")"
[[ "$p3" == "$CANON" ]] && pass "C3: no tenant -> canonical path itself (persona-engine-today bytes)" \
  || fail "C3: no-tenant" "expected '${CANON}', got '${p3}'"

# ── C4: live delta stays a SUPERSET of canonical default patterns ────────────
c4err="${ROOT}/c4.err"
missing="$(python3 - "$LIVE_CANONICAL" "$LIVE_DELTA" 2>"$c4err" <<'PY'
import sys, yaml
base = yaml.safe_load(open(sys.argv[1])) or {}
delta = yaml.safe_load(open(sys.argv[2])) or {}
b = ((base.get("router") or {}).get("glm_policy") or {}).get("protected_path_patterns") or []
d = ((delta.get("router") or {}).get("glm_policy") or {}).get("protected_path_patterns") or []
# an empty delta prints every default as missing -- the fail NAMES them
for p in b:
    if p not in d:
        print(p)
PY
)"; c4rc=$?
if [[ $c4rc -ne 0 ]]; then
  fail "C4a: live delta superset" "probe failed rc=${c4rc}: $(head -c 200 "$c4err")"
elif [[ -z "$missing" ]]; then
  pass "C4a: live delta protected_path_patterns is a superset of canonical defaults"
else
  fail "C4a: live delta superset" "missing glob(s) from canonical defaults: ${missing//$'\n'/ }"
fi

# ── C5: broken tenant -> loud refusal, never a canonical fallback ────────────
BROKEN="${ROOT}/broken"; mkdir -p "${BROKEN}/.claude/ref"
printf 'router: [oops\n  bad::: yaml here\n' > "${BROKEN}/.claude/ref/leadv2-routing.yaml"
LV2_RC_ENV="" out5="$(LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE="$CANON" \
  LEADV2_ROUTING_CONFIG_CACHE_DIR="$CACHE" \
  bash -c 'source "$1"; leadv2_routing_config_path "$2"' _ "$LIB" "$BROKEN" 2>"${BROKEN}/err")"; rc5=$?
[[ $rc5 -eq 1 ]] && pass "C5a: broken tenant -> rc=1 refusal" \
  || fail "C5a: broken tenant rc" "expected 1, got ${rc5}"
[[ -z "$out5" ]] && pass "C5b: refusal yields NO path (no silent fallback)" \
  || fail "C5b: no fallback path" "stdout was '${out5}'"
grep -q "${BROKEN}/.claude/ref/leadv2-routing.yaml" "${BROKEN}/err" \
  && pass "C5c: refusal names the broken file" \
  || fail "C5c: names the file" "stderr: $(head -c 200 "${BROKEN}/err")"

# ── C6: cache stability + same-size edit rebuild + no tmp leftovers ──────────
# patterns-only tenant (no ladder key): the ladder comes from canonical, so a
# canonical edit must be visible through the cache.
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "*safety*"\n      - "*onlymine*"\n' \
  > "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml"
canonical_v1
a1="$(resolve "$TENANT_ROOT")"
a2="$(resolve "$TENANT_ROOT")"
[[ "$a1" == "$a2" && -s "$a1" ]] && pass "C6a: repeated resolve -> same cached path" \
  || fail "C6a: cache stable" "'${a1}' vs '${a2}'"
canonical_v2   # same-size edit; a mtime-keyed cache could serve stale bytes here
b1="$(resolve "$TENANT_ROOT")"
[[ "$b1" != "$a1" ]] && pass "C6b: same-size canonical edit -> new cache entry (content-keyed)" \
  || fail "C6b: content-keyed cache" "same path '${a1}' after a content change"
[[ "$(ladder_first "$b1")" == "sonnet" ]] && pass "C6c: rebuilt cache carries the edit" \
  || fail "C6c: rebuilt content" "decision still '$(ladder_first "$b1")'"
leftovers="$(find "$CACHE" -name '.merge-*' 2>/dev/null | head -1)"
[[ -z "$leftovers" ]] && pass "C6d: no .merge-* tmp leftovers (atomic publish)" \
  || fail "C6d: tmp leftovers" "$leftovers"

# ── C7: no root -> named refusal ─────────────────────────────────────────────
out7="$(env -u PROJECT_ROOT bash -c 'source "$1"; leadv2_routing_config_path' _ "$LIB" 2>"${ROOT}/err7")"; rc7=$?
[[ $rc7 -eq 3 ]] && pass "C7a: no root -> rc=3" || fail "C7a: no-root rc" "expected 3, got ${rc7}"
grep -q "no project root" "${ROOT}/err7" && pass "C7b: refusal names the reason" \
  || fail "C7b: reason named" "stderr: $(head -c 200 "${ROOT}/err7")"

# ── C8: real repo shape (canonical + delta in one repo), journal once ────────
CACHE8="${ROOT}/cache8"; mkdir -p "$CACHE8"
err8a="${ROOT}/err8a"; err8b="${ROOT}/err8b"
p8="$(LEADV2_ROUTING_CONFIG_CACHE_DIR="$CACHE8" \
  bash -c 'source "$1"; leadv2_routing_config_path "$2"' _ "$LIB" "$REPO_ROOT" 2>"$err8a")"; rc8=$?
[[ $rc8 -eq 0 && -n "$p8" ]] && pass "C8a: plugin-repo root resolves (same-repo canon+tenant)" \
  || fail "C8a: same-repo merge" "rc=${rc8} out='${p8}'"
python3 -c "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
v2 = d.get('router_v2') or {}
r = d.get('router') or {}
assert v2.get('active_account'), 'missing canonical active_account'
assert ((r.get('glm_policy') or {}).get('protected_path_patterns')), 'missing tenant patterns'
" "$p8" 2>/dev/null \
  && pass "C8b: merged carries canonical keys AND tenant patterns" \
  || fail "C8b: merged shape" "see ${p8}"
grep -q "^\[leadv2-routing-config\] merged canonical=.* tenant=.* overridden=" "$err8a" \
  && pass "C8c: build journal line names canonical+tenant+override count" \
  || fail "C8c: journal line" "stderr: $(head -c 200 "$err8a")"
p8b="$(LEADV2_ROUTING_CONFIG_CACHE_DIR="$CACHE8" \
  bash -c 'source "$1"; leadv2_routing_config_path "$2"' _ "$LIB" "$REPO_ROOT" 2>"$err8b")"
[[ ! -s "$err8b" && "$p8b" == "$p8" ]] && pass "C8d: cache hit is quiet (journal only on build)" \
  || fail "C8d: quiet hit" "stderr: $(head -c 200 "$err8b")"

# ── C9: a tenant list REPLACES, never unions ─────────────────────────────────
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "*onlymine*"\n' \
  > "${TENANT_ROOT}/.claude/ref/leadv2-routing.yaml"
canonical_v1
p9="$(resolve "$TENANT_ROOT")"
np9="$(merged_patterns "$p9" | wc -l | tr -d ' ')"
only9="$(merged_patterns "$p9" | grep -c 'onlymine')"
[[ "$np9" == "1" && "$only9" == "1" ]] && pass "C9: tenant list REPLACES canonical (1 pattern, not union)" \
  || fail "C9: list-replace" "merged patterns: $(merged_patterns "$p9" | tr '\n' ' ')"

# ── C10: env override returned as-is (hermetic seam preserved) ───────────────
printf 'router_v2:\n  active_account: env_override_acct\n' > "${ROOT}/env-override.yaml"
p10="$(LV2_RC_ENV="${ROOT}/env-override.yaml" resolve "$TENANT_ROOT")"
[[ "$p10" == "${ROOT}/env-override.yaml" ]] && pass "C10: LEADV2_ROUTING_YAML returned as-is" \
  || fail "C10: env override" "got '${p10}'"

printf 'test-leadv2-routing-config: %d pass, %d fail\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
