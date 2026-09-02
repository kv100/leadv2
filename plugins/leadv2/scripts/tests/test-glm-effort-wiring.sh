#!/usr/bin/env bash
# tests/test-glm-effort-wiring.sh — GLM-EFFICIENCY-01 (founder order 2026-09-02).
#
# RESOLVED_EFFORT is WIRED into the GLM spawn (was EFFORT-IS-NOT-WIRED-01:
# journaled `effort_dropped` on every GLM dispatch):
#   1. The dispatcher maps the RAW task class to a Z.AI effort value and
#      passes GLM_EFFORT into the glm-coder.sh launcher env, journaling
#      `effort_applied ... mechanism=flag` (no live spawn — recorder bin).
#      Mapping: trivial|light|bulk -> low, standard -> high, heavy|strategic
#      -> max; review/verify roles -> high.
#   2. glm-coder.sh appends `--effort <v>` to BOTH claude spawn sites (v1
#      `run` and bg/__run_child) when GLM_EFFORT is set; omits the flag when
#      unset or outside the accepted vocabulary (low|medium|high|max —
#      fail-open to the provider default `max`).
#   3. Arm pick by class (founder ruling on the GLM-EFFICIENCY-01 ask,
#      q-bba84179): the capability matrix, not a script literal.
#
# Mechanism evidence (live probes, 2026-09-02):
#   - `claude -p --help` (CC 2.1.258) documents `--effort <level>`.
#   - docs.z.ai/devpack/latest-model.md: Claude Code's effort reaches Z.AI as
#     `output_config.effort`; low|medium|high|max accepted, default max.
#   - Raw api/anthropic probe, same prompt: output_tokens 130 (low) vs 369
#     (max) — the field measurably changes the response.
#
# The `claude` binary is stubbed via the GLM_CLAUDE_BIN seam (captures argv +
# env); the launcher via LEADV2_DISPATCH_GLM_BIN (captures its env); secrets/
# quota/runs-dir via GLM_SECRETS_FILE / GLM_SKIP_QUOTA_GATE / GLM_RUNS_DIR.
# No network, no real provider.
#
# Run: bash plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
GLM_SCRIPT="${PLUGIN_SCRIPTS}/glm-coder.sh"
DISPATCH="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"

export LEADV2_BURN_GOVERNOR=0

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-effort-fixture.XXXXXX")"
trap 'rm -rf "${FIXTURE}"; for m in ${NC_MUTANTS:-}; do rm -f "${m}"; done' EXIT INT TERM

# ── syntax floor on every changed shell file ────────────────────────────────
for f in "scripts/glm-coder.sh" "scripts/leadv2-dispatch-code.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); log "FAIL: bash -n ${f}"
  fi
done

# ── fixture: stub claude capturing spawn ARGV + env, stub secrets, repo ──────
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q 2>/dev/null || true
git -C "${REPO}" -c user.email=effort@test -c user.name=effort commit -q --allow-empty -m init 2>/dev/null || true

STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"
ARGV_CAPTURE="${FIXTURE}/spawn-argv.txt"
cat > "${STUB_BIN}/claude" <<STUBEOF
#!/usr/bin/env bash
printf 'ARGV=%s\n' "\$*" | tr '\n' ' ' >> "${ARGV_CAPTURE}"
printf 'GLM_EFFORT=%s\n' "\${GLM_EFFORT:-<unset>}" >> "${ARGV_CAPTURE}"
printf '%s\n' '{"type":"system","subtype":"init","model":"stub"}'
exit 0
STUBEOF
chmod +x "${STUB_BIN}/claude"

SECRETS="${FIXTURE}/zai.env"
printf 'ZAI_AUTH_TOKEN=stub-token-for-test\n' > "${SECRETS}"
chmod 600 "${SECRETS}"

# ── Part B1: v1 `run` path — GLM_EFFORT=low reaches the spawn argv ──────────
_effort_run_v1() { # $1 = GLM_EFFORT value or "" (unset)
  : > "${ARGV_CAPTURE}"
  (
    set +e
    export GLM_CLAUDE_BIN="${STUB_BIN}/claude"
    export GLM_SECRETS_FILE="${SECRETS}"
    export GLM_RUNS_DIR="${FIXTURE}/glm-runs"
    export GLM_SKIP_QUOTA_GATE=1
    export LEADV2_BURN_GOVERNOR=0
    export TMPDIR="${FIXTURE}"
    export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}"
    [[ -n "${1:-}" ]] && export GLM_EFFORT="$1"
    bash "${GLM_SCRIPT}" run "effort probe mission" --out "${FIXTURE}/out-v1.txt" --cwd "${REPO}"
  ) >/dev/null 2>&1
  return 0
}

_effort_run_v1 "low"
if grep -q '^ARGV=.*--effort low' "${ARGV_CAPTURE}" 2>/dev/null; then
  pass "run path: GLM_EFFORT=low -> spawn argv carries --effort low"
else
  fail "run path: --effort low missing from argv — got: $(grep '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null | head -1)"
fi

# ── Part B2: v1 `run` path — GLM_EFFORT unset omits the flag (no drift) ──────
_effort_run_v1 ""
if grep -q '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null && ! grep -q '^ARGV=.*--effort' "${ARGV_CAPTURE}" 2>/dev/null; then
  pass "run path: GLM_EFFORT unset -> no --effort flag (provider default max, pre-lane spawn shape)"
else
  fail "run path: --effort leaked with GLM_EFFORT unset — got: $(grep '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null | head -1)"
fi

# ── Part B3: v1 `run` path — out-of-vocabulary value omits the flag ─────────
_effort_run_v1 "ultramax"
if grep -q '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null && ! grep -q '^ARGV=.*--effort' "${ARGV_CAPTURE}" 2>/dev/null; then
  pass "run path: GLM_EFFORT=ultramax rejected by whitelist -> flag omitted (fail-open)"
else
  fail "run path: out-of-vocabulary effort reached argv — got: $(grep '^ARGV=' "${ARGV_CAPTURE}" 2>/dev/null | head -1)"
fi

# ── Part B4: bg path — __run_child spawn argv carries --effort too ───────────
BG_RUNS="${FIXTURE}/glm-bg-runs"; mkdir -p "${BG_RUNS}"
: > "${ARGV_CAPTURE}"
bg_id="$(
  GLM_CLAUDE_BIN="${STUB_BIN}/claude" GLM_SECRETS_FILE="${SECRETS}" \
  GLM_RUNS_DIR="${BG_RUNS}" GLM_SKIP_QUOTA_GATE=1 LEADV2_BURN_GOVERNOR=0 \
  TMPDIR="${FIXTURE}" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
  GLM_EFFORT=low GLM_TIMEOUT=2 \
  bash "${GLM_SCRIPT}" bg "effort bg probe mission" --cwd "${REPO}" 2>/dev/null | tail -1
)" || bg_id=""
for _i in $(seq 1 50); do
  [[ -s "${ARGV_CAPTURE}" ]] && break
  sleep 0.2
done
if grep -q '^ARGV=.*--effort low' "${ARGV_CAPTURE}" 2>/dev/null; then
  pass "bg path: __run_child spawn argv carries --effort low"
else
  fail "bg path: bounded child-argv probe had no --effort capture (run ${bg_id:-?})"
fi
# let the detached bg child settle so the trap cleanup does not race it
for _i in $(seq 1 20); do
  bash "${GLM_SCRIPT}" status "${bg_id}" >/dev/null 2>&1 || break
  sleep 0.1
done

# ── Part A: dispatcher maps class -> GLM_EFFORT and journals effort_applied ──
# Full dispatch runs, arbiter stubbed healthy, launcher replaced by a recorder
# that captures the env it was spawned with. No live spawn anywhere.
D_CACHE="${FIXTURE}/dispatch-cache"; mkdir -p "${D_CACHE}"
RECORD="${FIXTURE}/glm-bin-record.txt"
JOURNAL_RECORD="${FIXTURE}/journal-record.txt"
cat > "${FIXTURE}/glm-recorder.sh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  bg)
    printf 'GLM_MODEL=%s GLM_EFFORT=%s\n' "\${GLM_MODEL:-<unset>}" "\${GLM_EFFORT:-<unset>}" >> "${RECORD}"
    printf 'spawn-effort-stub\n'
    ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${FIXTURE}/glm-recorder.sh"
cat > "${FIXTURE}/journal.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${JOURNAL_RECORD}"
EOF
chmod +x "${FIXTURE}/journal.sh"
cat > "${FIXTURE}/dispatch-live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":20,"seven_day_pct":20}]}}'
EOF
chmod +x "${FIXTURE}/dispatch-live.sh"

_dispatch_for_class() { # $1 = task class
  : > "${RECORD}"
  (
    # FOREIGN-PROJECT-ROOT-GUARD-01: env roots are trusted only when cwd's git
    # toplevel agrees, so cd into the throwaway repo like every other suite.
    cd "${REPO}" || exit 97
    unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
    CLAUDE_PROJECT_ROOT="${REPO}" \
    LEADV2_PROJECT_ROOT="${REPO}" \
    LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state" \
    LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-effort-"$1" \
    LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" \
    LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
    LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
    LEADV2_WRITESET_PENDING_WINDOW_SEC=0 \
    bash "${DISPATCH}" "effort dispatch probe: $1 class" --kind code --task-class "$1" --writes "src/effort-probe-$1-$RANDOM.py" 2>&1
  ) >/dev/null 2>&1
  rm -f "${FIXTURE}/dispatch-arb-state" 2>/dev/null || true
}

# Class -> expected effort (docs/handoff/GLM-EFFICIENCY-01/report.md mapping
# table; trivial|light share the `low` tier, heavy carries `max`).
class_expect() {
  case "$1" in
    trivial|light) printf 'low' ;;
    standard)      printf 'high' ;;
    heavy)         printf 'max' ;;
    *)             printf '' ;;
  esac
}

for cls in trivial light; do
  _dispatch_for_class "${cls}"
  want="$(class_expect "${cls}")"
  if grep -q "^GLM_MODEL=[^ ]* GLM_EFFORT=${want}\$" "${RECORD}" 2>/dev/null; then
    pass "dispatch: task-class ${cls} -> launcher env GLM_EFFORT=${want} (end-to-end)"
  else
    fail "dispatch: task-class ${cls} expected GLM_EFFORT=${want} — got: $(cat "${RECORD}" 2>/dev/null | head -1)"
  fi
done

# ── Part A2: the full class map, unit-level ──────────────────────────────────
# Standard/Heavy/Strategic intentionally never reach a DIRECT worker dispatch
# (the admission classifier routes them phases-side), so the end-to-end probe
# above can only carry trivial/light. The map itself is one extracted function
# (_glm_effort_for_class, testable in isolation per the test-arm-admission.sh
# convention); assert every class against it here.
MAP_SRC="${FIXTURE}/map-extract.sh"
{
  sed -n '/^_glm_effort_for_class()/,/^}$/p' "${DISPATCH}"
  printf 'RESOLVED_EFFORT="%s"\n' "${RESOLVED_EFFORT:-}"
  printf 'for c in trivial light bulk standard heavy strategic bogus-cls; do printf "%%s=%%s\\n" "$c" "$(_glm_effort_for_class "$c")"; done\n'
} > "${MAP_SRC}"
MAP_OUT="$(bash "${MAP_SRC}" 2>&1)" || MAP_OUT=""
map_check() { # <class> <want>
  if [[ "${MAP_OUT}" == *"$1=$2"* ]]; then
    pass "class map: ${1} -> ${2}"
  else
    fail "class map: ${1} expected ${2} — got: $(printf '%s\n' "${MAP_OUT}" | grep "^$1=" || echo "<missing>")"
  fi
}
map_check trivial low
map_check light low
map_check bulk low
map_check standard high
map_check heavy max
map_check strategic max
if grep -q 'effort_applied by=router.*mechanism=flag source=class_map' "${JOURNAL_RECORD}" 2>/dev/null \
  && ! grep -q 'effort_dropped' "${JOURNAL_RECORD}" 2>/dev/null; then
  pass "dispatch: journal carries effort_applied mechanism=flag (no effort_dropped remains)"
else
  fail "dispatch: journal missing effort_applied or still has effort_dropped — got: $(grep -E 'effort_(applied|dropped)' "${JOURNAL_RECORD}" 2>/dev/null | head -2)"
fi

# ── NEGATIVE CONTROL (red first): drop the effort pass-through ──────────────
# Scratch copies only — never the working tree, never git stash/reset.
# The mutant must live in the REAL scripts dir: the dispatcher derives its own
# SCRIPT_DIR from $0 and every lib/ sibling path follows it, so a copy in the
# fixture cannot even source its helpers. Trap-removed temp name, never a
# working-tree diff.
MUT_DISPATCH="$(mktemp "${DISPATCH%/*}/dispatch-nc-mutant.XXXXXX")"
NC_MUTANTS="${NC_MUTANTS:-}${MUT_DISPATCH} "
# Remove the env pass-through AND demote the journal line, i.e. revert the
# wiring while keeping the script runnable:
sed -e 's/ GLM_EFFORT="\${_glm_effort}"//' \
    -e 's/effort_applied by=router/effort_dropped by=router/' \
    "${DISPATCH}" > "${MUT_DISPATCH}" 2>/dev/null || true
if [[ ! -s "${MUT_DISPATCH}" ]]; then
  fail "NC: mutant dispatcher copy failed to build"
fi
: > "${RECORD}"
: > "${JOURNAL_RECORD}"
(
  cd "${REPO}" || exit 97
  unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
  CLAUDE_PROJECT_ROOT="${REPO}" \
  LEADV2_PROJECT_ROOT="${REPO}" \
  LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state-nc" \
  LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-effort-nc \
  LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" \
  LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false \
  LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false \
  LEADV2_WRITESET_PENDING_WINDOW_SEC=0 \
  bash "${MUT_DISPATCH}" "effort NC probe: trivial" --kind code --task-class trivial --writes "src/effort-probe-nc-$RANDOM.py" 2>&1
) >/dev/null 2>&1
rm -f "${FIXTURE}/dispatch-arb-state-nc" 2>/dev/null || true
if grep -q 'GLM_EFFORT=<unset>' "${RECORD}" 2>/dev/null; then
  pass "NC(red): dropping the pass-through leaves the launcher env without GLM_EFFORT (part A red)"
else
  fail "NC: mutant still passed GLM_EFFORT — got: $(cat "${RECORD}" 2>/dev/null | head -1)"
fi
if grep -q 'effort_dropped by=router' "${JOURNAL_RECORD}" 2>/dev/null \
  && ! grep -q 'effort_applied' "${JOURNAL_RECORD}" 2>/dev/null; then
  pass "NC(red): mutant journal reverted to effort_dropped (journal assertion red)"
else
  fail "NC: mutant journal did not revert — got: $(grep -E 'effort_(applied|dropped)' "${JOURNAL_RECORD}" 2>/dev/null | tail -2)"
fi

# ── Part C: arm pick — trivial/light AND standard route to glm-flash ────────
# Founder ruling on ask q-bba84179 (2026-09-02, option b): the flash-preferred
# policy is correct (credit weight ⅓, not 3x); the fix is the data-only cost
# correction 0.4 -> 0.33 in the capability matrix. No arm ever gets
# special-cased in a script: light folds into the 'standard' matrix cell
# (SIZE_MAP), and the arbiter's cheapest-capable sort does the rest.
ROUTING_YAML="${PLUGIN_ROOT}/config/leadv2-routing.yaml"
if python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])) or {}; cells=(d.get('router_v2') or {}).get('capability_matrix') or []; flash=[c for c in cells if c.get('arm')=='glm-flash']; sys.exit(0 if flash and flash[0].get('cost')==0.33 else 1)" "${ROUTING_YAML}" 2>/dev/null; then
  pass "routing yaml: parses; glm-flash cell cost corrected to 0.33"
else
  fail "routing yaml: missing/invalid or glm-flash cost != 0.33"
fi
# shellcheck disable=SC1091
source "${PLUGIN_SCRIPTS}/lib/leadv2-route-arbiter.sh" 2>/dev/null || true
arb_pick() { # <size> -> arbiter worker line
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="${ROUTING_YAML}" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/arb-state-c" \
  route_arbiter worker "{\"kind\":\"code\",\"size\":\"$1\"}" 2>/dev/null
}
for size in light standard; do
  out="$(arb_pick "${size}")"
  if [[ "${out}" == *'arm=glm-flash '* && "${out}" == *'model=glm-5.3-flash'* ]]; then
    pass "arbiter: ${size}-size code work picks glm-flash / glm-5.3-flash"
  else
    fail "arbiter: ${size}-size expected arm=glm-flash — got: ${out:-<arbiter failed>}"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
log "passed=${PASS} failed=${FAIL}"
if [[ ${FAIL} -eq 0 ]]; then
  exit 0
fi
exit 1
