#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: glm-coder.sh leadv2-dispatch-code.sh
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
# fix-round-3 (C3): an empty arg must UNSET GLM_EFFORT, not merely skip
# exporting it -- a bare `export` skip leaves any ambient GLM_EFFORT (e.g.
# this very suite running inside a GLM lane, which the dispatcher exports)
# inherited by the subshell, turning the "unset -> no flag" assertion red.
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
    if [[ -n "${1:-}" ]]; then
      export GLM_EFFORT="$1"
      bash "${GLM_SCRIPT}" run "effort probe mission" --out "${FIXTURE}/out-v1.txt" --cwd "${REPO}"
    else
      unset GLM_EFFORT
      env -u GLM_EFFORT bash "${GLM_SCRIPT}" run "effort probe mission" --out "${FIXTURE}/out-v1.txt" --cwd "${REPO}"
    fi
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
  : > "${JOURNAL_RECORD}"
  (
    # FOREIGN-PROJECT-ROOT-GUARD-01: env roots are trusted only when cwd's git
    # toplevel agrees, so cd into the throwaway repo like every other suite.
    cd "${REPO}" || exit 97
    # fix-round-3 (C3, same hazard as _effort_run_v1): scrub any ambient
    # GLM_EFFORT (e.g. this suite running inside a live GLM lane) so the
    # dispatcher's own class-map computation is what reaches the recorder,
    # never an inherited leftover.
    unset GLM_EFFORT
    unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME
    CLAUDE_PROJECT_ROOT="${REPO}" \
    LEADV2_PROJECT_ROOT="${REPO}" \
    LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_REQUIRE_PHASES=0 \
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

# Class -> expected effort. fix-round-3 (C2): DC_TASK_CLASS is ALWAYS
# Title-case at runtime (Trivial/Light/Standard/Heavy/Strategic -- see
# _admission_classify), never the lowercase strings the map's own case arms
# happen to use, so the end-to-end probe must drive the dispatcher with the
# real shape or it can pass through the `*)` fallback and never touch the
# map at all (exactly the R2 critical finding). Three distinct effort
# values across Light/Standard/Heavy so a coincidental fallback match can't
# fake a pass.
class_expect() {
  case "$1" in
    Light)    printf 'low' ;;
    Standard) printf 'high' ;;
    Heavy)    printf 'max' ;;
    *)        printf '' ;;
  esac
}

for cls in Light Standard Heavy; do
  _dispatch_for_class "${cls}"
  want="$(class_expect "${cls}")"
  if grep -q "^GLM_MODEL=[^ ]* GLM_EFFORT=${want}\$" "${RECORD}" 2>/dev/null; then
    pass "dispatch: task-class ${cls} -> launcher env GLM_EFFORT=${want} (end-to-end)"
  else
    fail "dispatch: task-class ${cls} expected GLM_EFFORT=${want} — got: $(cat "${RECORD}" 2>/dev/null | head -1)"
  fi
  # Prove the MAP fired (source=class_map), not the RESOLVED_EFFORT fallback
  # coincidentally agreeing with `want` -- this is the assertion the R2
  # critical finding says was missing.
  if grep -q "effort_applied by=router.*effort=${want} mechanism=flag source=class_map" "${JOURNAL_RECORD}" 2>/dev/null; then
    pass "dispatch: task-class ${cls} journal proves class_map fired (source=class_map, effort=${want})"
  else
    fail "dispatch: task-class ${cls} journal did not prove class_map fired — got: $(grep -E 'effort_(applied|dropped)' "${JOURNAL_RECORD}" 2>/dev/null | head -2)"
  fi
done

# ── Part A2: the full class map, unit-level ──────────────────────────────────
# The map itself is one extracted function (_glm_effort_for_class, testable
# in isolation per the test-arm-admission.sh convention); assert every raw
# class AND its Title-case runtime shape against it, plus an unrecognized
# class to prove the fallback path (source=fallback) is real and distinct
# from a map hit (source=class_map) -- fix-round-3 (C2) negative case.
MAP_SRC="${FIXTURE}/map-extract.sh"
{
  sed -n '/^_glm_effort_for_class()/,/^}$/p' "${DISPATCH}"
  printf 'RESOLVED_EFFORT="%s"\n' "${RESOLVED_EFFORT:-}"
  printf 'for c in trivial light bulk standard heavy strategic Light Standard Heavy bogus-cls; do printf "%%s=%%s\\n" "$c" "$(_glm_effort_for_class "$c")"; done\n'
} > "${MAP_SRC}"
MAP_OUT="$(bash "${MAP_SRC}" 2>&1)" || MAP_OUT=""
map_check() { # <class> <want-effort> <want-source>
  if [[ "${MAP_OUT}" == *"$1=$2 $3"* ]]; then
    pass "class map: ${1} -> ${2} (source=${3})"
  else
    fail "class map: ${1} expected ${2}/${3} — got: $(printf '%s\n' "${MAP_OUT}" | grep "^$1=" || echo "<missing>")"
  fi
}
map_check trivial low class_map
map_check light low class_map
map_check bulk low class_map
map_check standard high class_map
map_check heavy max class_map
map_check strategic max class_map
map_check Light low class_map
map_check Standard high class_map
map_check Heavy max class_map
map_check bogus-cls high fallback

# ── NEGATIVE CONTROL (fix-round-3 point 3): delete the map body ─────────────
# The R2 critical finding: with the whole case body deleted, the old e2e
# assertions stayed green (they checked only the effort VALUE, which the
# fallback happened to reproduce). Prove that can't happen again: strip the
# three map arms from the SAME extracted function and confirm every class
# now reports source=fallback, never class_map.
MAP_MUT_SRC="${FIXTURE}/map-extract-mutant.sh"
{
  sed -n '/^_glm_effort_for_class()/,/^}$/p' "${DISPATCH}" | \
    sed -e "/'low' 'class_map'/d" -e "/'high' 'class_map'/d" -e "/'max' 'class_map'/d"
  printf 'RESOLVED_EFFORT="%s"\n' "${RESOLVED_EFFORT:-}"
  printf 'for c in trivial light bulk standard heavy strategic; do printf "%%s=%%s\\n" "$c" "$(_glm_effort_for_class "$c")"; done\n'
} > "${MAP_MUT_SRC}"
MAP_MUT_OUT="$(bash "${MAP_MUT_SRC}" 2>&1)" || MAP_MUT_OUT=""
if [[ -n "${MAP_MUT_OUT}" ]] && ! printf '%s\n' "${MAP_MUT_OUT}" | grep -q 'class_map'; then
  pass "NC(map-body,red): deleting the class map body drives every class to source=fallback (detectable)"
else
  fail "NC(map-body): mutant with the map body deleted still reports source=class_map somewhere — got: ${MAP_MUT_OUT}"
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
  # fix-round-3 (C3, same hazard as _effort_run_v1): scrub ambient GLM_EFFORT
  # so the mutant's stripped pass-through is what the recorder sees, never an
  # inherited leftover masking the mutation.
  unset GLM_EFFORT
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
