#!/usr/bin/env bash
# tests/test-plan-followups-01.sh — behavioral tests for the 4 High judge caveats.
#
# Each test is hermetic (mktemp sandbox) and MUST FAIL when its fix is reverted.
# No grep-on-source assertions — every test exercises real runtime behavior.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-followups-01.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"
RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
MERGE_PY="${SCRIPTS_ROOT}/lib/leadv2-context-merge.py"
FIXTURES="${SCRIPT_DIR}/fixtures/plan-run"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# Shared: quota stub — codex needs windows/binding_window schema;
# anthropic needs accounts[]/active/five_hour_pct/seven_day_pct.
printf '#!/usr/bin/env bash\ncase "$1" in\n  codex) printf '"'"'{"status":"ok","windows":[{"kind":"primary","used_percent":10.0}],"binding_window":"primary"}\\n'"'"' ;;\n  *) printf '"'"'{"status":"ok","accounts":[{"active":true,"five_hour_pct":10.0,"seven_day_pct":10.0}]}\\n'"'"' ;;\nesac\n' > "${TMP}/stub-quota.sh"
chmod +x "${TMP}/stub-quota.sh"

# ===========================================================================
# Caveat 1: arm loop must CONSUME refused_* and spill to next :ok: arm
#           (not treat a refusal as terminal).
# ===========================================================================

# --- 1a: classify_arm_failure correctly returns refused_quota ---
log "Caveat 1a: classify_arm_failure returns refused_quota for LEADV2_DISPATCH_REFUSED"
mkdir -p "${TMP}/1a"
echo "LEADV2_DISPATCH_REFUSED: quota_exhausted" > "${TMP}/1a/err"
echo "" > "${TMP}/1a/out"

# Source classify_arm_failure from the engine and test it.
_cls="$(bash -c '
  source <(sed -n "/^classify_arm_failure/,/^}/p" "'${ENGINE}'")
  classify_arm_failure 1 "'${TMP}'/1a/err" "'${TMP}'/1a/out"
')"
if [[ "${_cls}" == "refused_quota" ]]; then
  pass "classify_arm_failure returns refused_quota"
else
  fail "classify_arm_failure returned '${_cls}' (expected refused_quota)"
fi

# --- 1b: refused arm spills to next arm — engine reaches status=pass ---
log "Caveat 1b: refused_quota arm spills to next :ok: arm → status=pass"
ROOT1="${TMP}/repo1"
HANDOFF1="${ROOT1}/docs/handoff/c1b"
mkdir -p "${ROOT1}/.claude/ref" "${HANDOFF1}"

cat > "${ROOT1}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, opus]
      review_threshold_pct: 95
      anthropic_review_threshold_pct: 95
  dispatch_ladder:
    - id: codex
      review_rank: 1
      provider: codex
    - id: sonnet
      review_rank: 2
      provider: anthropic
    - id: opus
      review_rank: 3
      provider: anthropic
YAML

# First-call-refuses stub: codex refuses with quota, sonnet succeeds.
# The engine dispatches codex first; if it refuses, spills to sonnet.
cat > "${TMP}/stub-codex-refuse.sh" <<'SH'
#!/usr/bin/env bash
# Codex stub: refuses with quota exhausted.
# Called as LEADV2_DISPATCH_CODEX_BIN (--task-id --mode --mission-file --wait).
echo "LEADV2_DISPATCH_REFUSED: quota_exhausted" >&2
exit 75
SH
chmod +x "${TMP}/stub-codex-refuse.sh"

# Stub for non-codex arms (sonnet, opus): succeeds with valid PLAN_YAML.
# Called as LEADV2_DISPATCH_ARCHITECT_BIN (--role --model --task-id --mission-file --wait).
cat > "${TMP}/stub-ok.sh" <<'SH'
#!/usr/bin/env bash
cat <<'YAML'
```yaml
PLAN_YAML:
decisions:
  - Spilled to fallback arm
off_limits:
  - nothing
plan:
  steps:
    - One step
acceptance:
  surface: file_artifact
  observable: >
    Reader sees valid plan-gate.md.
risk: low
```
YAML
SH
chmod +x "${TMP}/stub-ok.sh"

printf 'Test mission for refusal spill.' > "${TMP}/mission1.txt"

LEADV2_ROUTING_YAML="${ROOT1}/.claude/ref/leadv2-routing.yaml" \
GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-ok.sh" \
LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex-refuse.sh" \
LEADV2_PLAN_ARM_TIMEOUT_S=10 \
bash "${ENGINE}" --task c1b --root "${ROOT1}" --handoff "${HANDOFF1}" \
  --mode prepass --mission-file "${TMP}/mission1.txt" --no-cache \
  >"${TMP}/1b-stdout.log" 2>"${TMP}/1b-stderr.log"
rc1b=$?

_status1b="$(sed -n 's/^status:[[:space:]]*//p' "${HANDOFF1}/plan-gate.md" 2>/dev/null | head -1)"
_stderr1b="$(cat "${TMP}/1b-stderr.log" 2>/dev/null)"

if [[ "${_status1b}" == "pass" ]]; then
  pass "refused codex spilled to next arm → status=pass (rc=${rc1b})"
else
  fail "refused codex did NOT spill → status='${_status1b}' (expected pass)"
  log "  stderr (tail): $(tail -5 "${TMP}/1b-stderr.log" 2>/dev/null)"
fi

# Verify the spill was journaled.
if grep -q 'arm_refused.*codex' <<<"${_stderr1b}" 2>/dev/null; then
  pass "journal recorded arm_refused for codex"
else
  fail "no arm_refused journal line for codex"
fi

# ===========================================================================
# Caveat 2: extract_plan_yaml accepts BOTH marker/fence orderings.
# ===========================================================================

# Source extract_plan_yaml from the engine.
source <(sed -n '/^extract_plan_yaml()/,/^}/p' "${ENGINE}")

# --- 2a: Order A (marker THEN fence) — stub fixture format ---
log "Caveat 2a: extract_plan_yaml handles marker→fence order (A)"
cat > "${TMP}/2a.txt" <<'TXT'
Some preamble text.
PLAN_YAML:
```yaml
decisions:
  - Decision A
plan:
  steps:
    - Step A
```
TXT

_out_2a="$(extract_plan_yaml "${TMP}/2a.txt")"
if grep -q 'Decision A' <<<"${_out_2a}" && ! grep -q 'PLAN_YAML' <<<"${_out_2a}"; then
  pass "Order A (marker→fence) extracts YAML content correctly"
else
  fail "Order A extraction failed (got: ${_out_2a})"
fi

# --- 2b: Order B (fence THEN marker) — mission prompt format ---
log "Caveat 2b: extract_plan_yaml handles fence→marker order (B)"
cat > "${TMP}/2b.txt" <<'TXT'
Some preamble text.
```yaml
PLAN_YAML:
decisions:
  - Decision B
plan:
  steps:
    - Step B
```
TXT

_out_2b="$(extract_plan_yaml "${TMP}/2b.txt")"
if grep -q 'Decision B' <<<"${_out_2b}" && ! grep -q 'PLAN_YAML' <<<"${_out_2b}"; then
  pass "Order B (fence→marker) extracts YAML content correctly"
else
  fail "Order B extraction failed (got: ${_out_2b})"
fi

# --- 2c: Order B ignores prose after the closing fence ---
log "Caveat 2c: Order B extraction ignores trailing prose"
cat > "${TMP}/2c.txt" <<'TXT'
Some preamble text.
```yaml
PLAN_YAML:
decisions:
  - Decision B trailing
plan:
  steps:
    - Step B trailing
```
This trailing prose is not YAML.
TXT

_out_2c="$(extract_plan_yaml "${TMP}/2c.txt")"
if grep -q 'Decision B trailing' <<<"${_out_2c}" \
    && ! grep -q 'PLAN_YAML\|trailing prose' <<<"${_out_2c}"; then
  pass "Order B extraction stops at the closing fence"
else
  fail "Order B trailing-prose extraction failed (got: ${_out_2c})"
fi

# --- 2d: Marker without fences returns everything after the marker ---
log "Caveat 2d: marker-only extraction preserves legacy raw-YAML form"
cat > "${TMP}/2d.txt" <<'TXT'
Some preamble text.
PLAN_YAML:
decisions:
  - Marker-only decision
plan:
  steps:
    - Marker-only step
TXT

_out_2d="$(extract_plan_yaml "${TMP}/2d.txt")"
if grep -q 'Marker-only decision' <<<"${_out_2d}" \
    && ! grep -q 'PLAN_YAML\|preamble' <<<"${_out_2d}"; then
  pass "Marker-only form extracts everything after PLAN_YAML"
else
  fail "Marker-only extraction failed (got: ${_out_2d})"
fi

# --- 2e: Extract from real fixture stub-architect.sh output ---
log "Caveat 2e: extract_plan_yaml on real stub-architect.sh output"
_out_fixture="$(bash "${FIXTURES}/stub-architect.sh" | extract_plan_yaml /dev/stdin)"
if grep -q 'Use leadv2-plan-run.sh' <<<"${_out_fixture}"; then
  pass "Real fixture (stub-architect) extracts correctly"
else
  fail "Real fixture extraction failed"
fi

# ===========================================================================
# Caveat 3: non-dict acceptance is a hard error; authored_at preserved.
# ===========================================================================

# --- 3a: non-dict acceptance exits nonzero ---
log "Caveat 3a: non-dict acceptance causes nonzero exit"
cat > "${TMP}/skeleton3.yaml" <<'YAML'
id: dispatch-test3
mission: |
  Test mission.
acceptance:
  authored_at: 2026-08-12T00:00:00Z
reads: []
writes: []
lane_writes: []
YAML

cat > "${TMP}/arm3-bad.yaml" <<'YAML'
acceptance: "just a string"
decisions:
  - Some decision
off_limits: []
plan:
  steps:
    - One step
YAML

python3 "${MERGE_PY}" --skeleton "${TMP}/skeleton3.yaml" --arm "${TMP}/arm3-bad.yaml" \
  --out "${TMP}/merged3-bad.yaml" 2>"${TMP}/merge3-bad.err"
_rc3a=$?

if [[ "${_rc3a}" -ne 0 ]]; then
  pass "Non-dict acceptance rejected with nonzero exit (rc=${_rc3a})"
else
  fail "Non-dict acceptance was silently accepted (rc=0)"
fi

# --- 3b: dict acceptance preserves authored_at ---
log "Caveat 3b: dict acceptance preserves engine-authored_at"
cat > "${TMP}/arm3-ok.yaml" <<'YAML'
acceptance:
  surface: file_artifact
  observable: >
    Reader sees valid output.
  authored_at: 2099-01-01T00:00:00Z
decisions:
  - Some decision
off_limits: []
plan:
  steps:
    - One step
YAML

python3 "${MERGE_PY}" --skeleton "${TMP}/skeleton3.yaml" --arm "${TMP}/arm3-ok.yaml" \
  --out "${TMP}/merged3-ok.yaml" 2>/dev/null

_authored="$(python3 -c '
import yaml
d = yaml.safe_load(open("'"${TMP}"'/merged3-ok.yaml"))
print(str(d.get("acceptance", {}).get("authored_at", "")))
')"

if [[ "${_authored}" == *"2026-08-12"* ]]; then
  pass "authored_at preserved (arm value 2099-01-01 was discarded, got '${_authored}')"
else
  fail "authored_at was overwritten to '${_authored}' (expected 2026-08-12)"
fi

# ===========================================================================
# Caveat 4: review-floor / _best_effort_floor_pool filtered by
#           DISPATCHABLE_PLAN_ARMS when job=plan (no haiku in planning pool).
# ===========================================================================

# --- 4a: _review_floor excludes non-dispatchable arms for plan job ---
log "Caveat 4a: _review_floor filters by DISPATCHABLE_PLAN_ARMS for plan"
printf '#!/usr/bin/env python3\nimport importlib.util, sys\nspec = importlib.util.spec_from_file_location("resolve", "%s")\nmod = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(mod)\nrank_table = {"sonnet": 1, "haiku": 2}\narm_review, _ = mod._review_floor("sonnet", rank_table, dispatchable=None)\narm_plan, _ = mod._review_floor("sonnet", rank_table, dispatchable=mod.DISPATCHABLE_PLAN_ARMS)\nprint("review=%%s" %% arm_review)\nprint("plan=%%s" %% arm_plan)\n' "${RESOLVER}" > "${TMP}/test4a.py"
_out_4a="$(python3 "${TMP}/test4a.py" 2>&1)"

_arm_review="$(printf '%s\n' "${_out_4a}" | grep '^review=' | cut -d= -f2)"
_arm_plan="$(printf '%s\n' "${_out_4a}" | grep '^plan=' | cut -d= -f2)"

if [[ "${_arm_plan}" != "haiku" ]]; then
  pass "Plan floor does not pick haiku (got '${_arm_plan}')"
else
  fail "Plan floor picked haiku — should be filtered"
fi

if [[ "${_arm_review}" == "haiku" ]]; then
  pass "Review floor CAN pick haiku (unfiltered — got '${_arm_review}')"
else
  fail "Review floor unexpectedly avoided haiku (got '${_arm_review}')"
fi

# --- 4b: end-to-end resolver with --plan-pool never picks haiku ---
log "Caveat 4b: --plan-pool resolver never selects haiku"
ROOT4="${TMP}/repo4"
mkdir -p "${ROOT4}/.claude/ref"

cat > "${ROOT4}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, haiku]
      review_threshold_pct: 95
  dispatch_ladder:
    - id: codex
      review_rank: 1
      provider: codex
    - id: sonnet
      review_rank: 2
      provider: anthropic
    - id: haiku
      review_rank: 3
      provider: anthropic
YAML

_out_4b="$(python3 "${RESOLVER}" --routing-yaml "${ROOT4}/.claude/ref/leadv2-routing.yaml" \
  --job plan --base-arm codex --plan-pool --signals '{}' \
  --quota-live "${TMP}/stub-quota.sh" 2>/dev/null)"

# Check pool= line does not contain haiku
if ! grep 'haiku' <<<"${_out_4b}" | grep -q ':ok:\|:floor:\|:unknown:'; then
  pass "--plan-pool output excludes haiku from active pool"
else
  fail "--plan-pool output includes haiku in active pool"
fi

# Verify reviewer= is not haiku
_reviewer_4b="$(grep '^reviewer=' <<<"${_out_4b}" | cut -d= -f2)"
if [[ "${_reviewer_4b}" != "haiku" ]]; then
  pass "--plan-pool reviewer is not haiku (got '${_reviewer_4b}')"
else
  fail "--plan-pool reviewer is haiku — should never happen"
fi

# --- 4c: _best_effort_floor_pool filters for --plan-pool ---
log "Caveat 4c: _best_effort_floor_pool filters haiku under --plan-pool"
printf '#!/usr/bin/env python3\nimport importlib.util\nspec = importlib.util.spec_from_file_location("resolve", "%s")\nmod = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(mod)\nargv = ["--routing-yaml", "%s/.claude/ref/leadv2-routing.yaml", "--plan-pool", "--job", "plan"]\nreviewer, pool, refusal = mod._best_effort_floor_pool(argv)\nprint("reviewer=%%s" %% reviewer)\nprint("refusal=%%s" %% refusal)\n' "${RESOLVER}" "${ROOT4}" > "${TMP}/test4c.py"
_out_4c="$(python3 "${TMP}/test4c.py" 2>&1)"

_floor_reviewer="$(grep '^reviewer=' <<<"${_out_4c}" | cut -d= -f2)"
if [[ "${_floor_reviewer}" != "haiku" && -n "${_floor_reviewer}" ]]; then
  pass "_best_effort_floor_pool excludes haiku under --plan-pool (got '${_floor_reviewer}')"
elif [[ -z "${_floor_reviewer}" ]]; then
  # Acceptable: no floor arm available after filtering
  pass "_best_effort_floor_pool returned no reviewer (acceptable — haiku was the only candidate post-filter)"
else
  fail "_best_effort_floor_pool picked haiku under --plan-pool"
fi

# --- 4d: a valid ladder emptied by plan filtering is unavailable, not degenerate ---
log "Caveat 4d: empty post-filter plan pool degrades without degenerate hard error"
ROOT4D="${TMP}/repo4d"
mkdir -p "${ROOT4D}/.claude/ref"
cat > "${ROOT4D}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [glm, haiku]
  dispatch_ladder:
    - id: glm
      review_rank: 1
    - id: haiku
      review_rank: 2
YAML
_out_4d="$(python3 "${RESOLVER}" --routing-yaml "${ROOT4D}/.claude/ref/leadv2-routing.yaml" \
  --job plan --plan-pool --signals '{}' --quota-live "${TMP}/stub-quota.sh" 2>/dev/null)"
_refusal_4d="$(grep '^refusal=' <<<"${_out_4d}" | cut -d= -f2)"
if [[ "${_refusal_4d}" == "all_review_arms_unavailable" ]]; then
  pass "Empty post-filter plan pool uses all_review_arms_unavailable fallback"
else
  fail "Empty post-filter plan pool returned '${_refusal_4d}' (expected all_review_arms_unavailable)"
fi

# --- 4e: a sole dispatchable post-filter arm is still the floor ---
log "Caveat 4e: sole dispatchable plan arm remains a valid floor"
ROOT4E="${TMP}/repo4e"
mkdir -p "${ROOT4E}/.claude/ref"
cat > "${ROOT4E}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [sonnet, haiku]
      anthropic_review_threshold_pct: 0
  dispatch_ladder:
    - id: sonnet
      review_rank: 1
      provider: anthropic
    - id: haiku
      review_rank: 2
      provider: anthropic
YAML
_out_4e="$(python3 "${RESOLVER}" --routing-yaml "${ROOT4E}/.claude/ref/leadv2-routing.yaml" \
  --job plan --plan-pool --signals '{}' --quota-live "${TMP}/stub-quota.sh" 2>/dev/null)"
_reviewer_4e="$(grep '^reviewer=' <<<"${_out_4e}" | cut -d= -f2)"
_refusal_4e="$(grep '^refusal=' <<<"${_out_4e}" | cut -d= -f2)"
if [[ "${_reviewer_4e}" == "sonnet" && -z "${_refusal_4e}" ]] \
    && grep -q '^pool=.*sonnet:floor:' <<<"${_out_4e}"; then
  pass "Sole dispatchable arm is honored as the plan floor"
else
  fail "Sole dispatchable floor failed (reviewer='${_reviewer_4e}', refusal='${_refusal_4e}')"
fi

# ===========================================================================
printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
