#!/usr/bin/env bash
# tests/test-phase-bootstrap-grace-cannot-skip-plan.sh — PHASE-PREFIX-AT-RECORD-01
# run-all-triggers: leadv2-dispatch-code leadv2-phase-record
#
# The defect (row f37fadb8f474, measured 2026-09-12): the mandatory-phase
# guard's one-shot bootstrap grace ADMITTED a lane at dispatch time, and then
# nothing ever forced plan/gate1 to exist before `build` was recorded — two
# Standard lanes (bd7f811eb05c / 4c06462a1a71) ran in build >1h holding
# exactly `classify: done` + `build: running`. The second half of the same
# defect: once build existed without plan/gate1, the grace no longer applied,
# so re-dispatch was refused forever (DISPATCH-PHASE-DEADLOCK-01) — 109 stale
# `build:running` records were hand-moved aside three times in one evening.
#
# The fix this suite pins (founder order 2026-09-12, CONTRACT: PHASE-PREFIX in
# docs/handoff/DECISION-LAYER-CONTRACT/decision.md):
#   1. The grace may ADMIT a lane, but `build` (and every phase >= build) must
#      not be RECORDABLE until the class's mandatory pre-build prefix exists —
#      the check lives in leadv2-phase-record.sh _record_prefix_check (the ONE
#      writer), exit 6, and dispatch's site-1 build stamp ABORTS on it (exit 3)
#      so no worker ever starts on an unmet ladder.
#   2. A lane whose non-classify records are ALL `running` on a POSITIVELY
#      dead lane (liveness verdict dead:*) is re-admitted through the ladder —
#      resumable by recording the printed remedies, never by hand-moving
#      phase files. STALENESS RULE: only a positive death verdict reclaims;
#      alive/silent/unknown never does (never reclaim on a guess).
#   3. The guard is NOT weakened: a fresh lane under explicit scope=full
#      (LEADV2_REQUIRE_PHASES=1) is still refused (G2 parity in
#      test-phase-precondition.sh), and the bootstrap grace is TIME-BOUNDED
#      (LEADV2_BOOTSTRAP_GRACE_MAX_S, default 86400s) — a classify-only lane
#      past the bound is a named anomaly, not a standing bypass.
#
# Part A drives leadv2-phase-record.sh directly (the writer's contract).
# Part B drives leadv2-dispatch-code.sh end to end (the same hermetic-fixture
# discipline as test-dispatch-refuses-a-dead-premise.sh: real dispatch script,
# fake launchers/journal/judge/liveness ONE LEVEL BELOW it — never a stub of
# the function under test).
#
# Cases:
#   A1  Standard classify-only  -> build rc=6, nothing written, stderr names
#                                  plan+gate1, journal phase_record_refused
#                                  reason=pre_build_prefix
#   A2  + plan (real brief)     -> build still rc=6, missing gate1
#   A3  + gate1 (--reason)      -> build rc=0, build.yaml written
#   A4  Light class             -> build rc=0 (owes neither plan nor gate1)
#   A5  classless legacy lane   -> build rc=0 (fail-open, no class in store)
#   A6  REQUIRE_PHASES=0        -> build rc=0 (kill-switch parity at the writer)
#   A7  plan n/a + gate1 n/a    -> build rc=0 (governance records exempt)
#   A8  review on grace lane    -> rc=6 (EVERY phase >= build, not just build)
#   B1  fresh Standard dispatch -> bootstrap-admit journal line, then
#                                  dispatch_refused reason=build_prefix_unmet,
#                                  exit 3, worker NEVER spawned
#   B2  record the remedies, re-dispatch the SAME mission -> rc=0, worker
#                                  spawned (the deadlock is gone)
#   B3  classify+build:running, liveness dead:* -> phase_precondition_stale_
#                                  running_readmit, NO phase_precondition_refused
#                                  line, build.yaml untouched by hand; after
#                                  remedies -> re-dispatch rc=0 + spawn
#   B4  same seed, liveness alive -> phase_precondition_refused, no readmit
#                                  (never reclaim on a guess)
#   B5  fresh lane, REQUIRE_PHASES=1 (scope=full) -> phase_precondition_refused,
#                                  exit 3, no spawn (guard not weakened)
#   B6  classify-only backdated past the grace -> bootstrap_grace_expired +
#                                  refused; young classify-only -> bootstrap
#                                  admit (B6b) — the grace is time-bounded
#   T0  bash -n on all three scripts
#
# Negative controls (run via leadv2-mutation-control.sh; each anchor verified
# count==1 before the run — an unanchored sed that matches nothing is a silent
# no-op, and two controls rotted that way this week):
#   NC1 (requirement 1) — gut the record-site phase gate:
#       file leadv2-phase-record.sh
#       sed  s/build|test|review|deploy|live_verify|e2e|close) ;;/buildx|testx|reviewx|deployx|live_verifyx|e2ex|closex) ;;/
#       -> build becomes recordable on a grace lane -> A1/A3/B1/B2 RED
#   NC2 (requirement 2) — make the readmit verdict unreachable:
#       file leadv2-dispatch-code.sh
#       sed  s/"${_pp_verdict}" == dead:\*/"${_pp_verdict}" == dead__never:*/
#       -> B3's readmit journal line never appears -> B3 RED
#   NC3 (requirement 3) — let bootstrap apply under scope=full too:
#       file leadv2-phase-record.sh
#       sed  s/local _lane_bootstrap=0/local _lane_bootstrap=1/
#       -> B5's phase_precondition_refused line never appears -> B5 RED
#
# Run: bash plugins/leadv2/scripts/tests/test-phase-bootstrap-grace-cannot-skip-plan.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
# zsh safety (same as test-dispatch-refuses-a-dead-premise.sh): BASH_SOURCE is
# absent under zsh; fall back to $0 when it names a real file.
_t_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t_src" && -f "${0:-}" ]]; then _t_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PHASE_RECORD="${SCRIPTS_ROOT}/leadv2-phase-record.sh"
DISPATCH_SH="${SCRIPTS_ROOT}/leadv2-dispatch-cod""e.sh"
SUITE_SELF="$(cd "$(dirname "$_t_src")" && pwd)/$(basename "$_t_src")"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir f37f-grace-test)"
trap 'rm -rf "$TMP"' EXIT

# ── shared fixture: one real git repo, everything one level below faked ─────
ROOT="${TMP}/repo"
mkdir -p "${ROOT}/.claude/ref" "${ROOT}/docs" "${ROOT}/scripts"
( cd "${ROOT}" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed ) || { echo "fixture git init failed"; exit 1; }

# Recording journal bin (asserts land in JOURNAL_REC as "JOURNAL <args>")
JOURNAL_REC="${TMP}/journal-record.log"
cat > "${TMP}/journal-recorder.sh" <<'EOF'
#!/usr/bin/env bash
printf 'JOURNAL %s\n' "$*" >> "${LEADV2_JOURNAL_REC:-/dev/null}"
exit 0
EOF
chmod +x "${TMP}/journal-recorder.sh"
export LEADV2_JOURNAL_REC="${JOURNAL_REC}"

# Fake launchers: record the spawn, answer status. B1/B4/B5/B6's whole point is
# that on an unmet ladder NEITHER is ever reached.
SPAWN_MARK="${TMP}/spawn-mark.log"
cat > "${TMP}/fake-glm.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SPAWN glm\n' >> "${LEADV2_SPAWN_MARK:-/dev/null}"
case "${1:-}" in
  bg)     printf 'fake-glm-handle\n' ;;
  status) exit 0 ;;
  *)      exit 0 ;;
esac
EOF
chmod +x "${TMP}/fake-glm.sh"
cat > "${TMP}/fake-subsession.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SPAWN subsession\n' >> "${LEADV2_SPAWN_MARK:-/dev/null}"
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
EOF
chmod +x "${TMP}/fake-subsession.sh"

# Deterministic offline stubs (same shapes as test-phase-precondition.sh):
# judge, glm policy resolver, lane worktree, no-arbiter lib.
cat > "${TMP}/judge-stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"work_kind":"build","complexity":"simple","duration_class":"short"}\n'
EOF
chmod +x "${TMP}/judge-stub.sh"
cat > "${TMP}/glm-policy-stub.py" <<'EOF'
#!/usr/bin/env python3
print("arm=glm\nrule=none\nreason=e2e_stub\ntier=")
EOF
chmod +x "${TMP}/glm-policy-stub.py"
cat > "${TMP}/lane-wt-stub.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  ensure|path-of) printf '%s\n' "${LEADV2_PROJECT_ROOT}" ;;
esac
EOF
chmod +x "${TMP}/lane-wt-stub.sh"
: > "${TMP}/no-arbiter.lib"

# Lane-liveness stub: prints the verdict the case wants, verbatim — the guard
# must consume the BARE verdict token contract, nothing else.
cat > "${TMP}/liveness-stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${LEADV2_LIVENESS_VERDICT:-unknown:stub_default}"
EOF
chmod +x "${TMP}/liveness-stub.sh"

cat > "${ROOT}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
    codex_default_tier: standard
YAML

export LEADV2_LANE_WORK_ROOT="${ROOT}"
export LEADV2_ARM_EARLY_VERDICT_S=0
cd "${ROOT}"
unset PROJECT_ROOT LEADV2_PROJECT_ROOT 2>/dev/null || true

# _record <sig8> <phase> [args...] -> REC_OUT, REC_RC (direct writer drive;
# every Part A case and every seeding/remedy step goes through the REAL writer)
_record() {
  local _rc=0 _out
  _out="$(cd "${ROOT}" && env LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_JOURNAL_BIN="${TMP}/journal-recorder.sh" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP}/cache-a" \
    ${REC_EXTRA[@]+"${REC_EXTRA[@]}"} \
    bash "${PHASE_RECORD}" record "$@" 2>&1)" || _rc=$?
  REC_OUT="${_out}"; REC_RC="${_rc}"
}

# _brief <sig8>: a real lead-authored brief (>=120 non-ws chars, >=2 lines)
_brief() {
  local sig8="$1"
  mkdir -p "${ROOT}/docs/handoff/dispatch-${sig8}"
  cat > "${ROOT}/docs/handoff/dispatch-${sig8}/brief.md" <<BRIEF
# Plan for dispatch-${sig8}

Reproduce the refusal, move the prefix check to the one writer, prove the
lane resumes without any hand-moved phase file, and keep the full-scope
refusal pinned. This text exists so the substance floor passes.
BRIEF
}

_sig8_of() { # <mission> -> first 8 hex of the dispatch sig pipeline
  printf '%s' "$1" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' \
    | shasum -a 256 | awk '{print $1}' | cut -c1-8
}

# ── T0: syntax ─────────────────────────────────────────────────────────────
if bash -n "${DISPATCH_SH}" 2>/dev/null && bash -n "${PHASE_RECORD}" 2>/dev/null \
   && bash -n "${SUITE_SELF}" 2>/dev/null; then
  pass "T0 bash -n dispatch + phase-record + suite"
else
  fail "T0 bash -n dispatch + phase-record + suite"
fi

# ════════════════════════════════════════════════════════════════════════════
# Part A — the writer's contract (leadv2-phase-record.sh record)
# ════════════════════════════════════════════════════════════════════════════
REC_EXTRA=()

# A1: Standard classify-only -> build refused rc=6, nothing written
A1_SIG="f37faa01"
: > "${JOURNAL_REC}"
_record "${A1_SIG}" classify --status done --class Standard --task-id f37faa01 --owner suite:a1
_record "${A1_SIG}" build --status running --handle "dispatch-${A1_SIG}-build" --task-id f37faa01 --owner suite:a1
[[ "${REC_RC}" == "6" ]] && pass "A1 build on grace lane refused rc=6" || fail "A1 expected rc=6 got ${REC_RC}"
[[ ! -f "${ROOT}/docs/handoff/dispatch-${A1_SIG}/phases.d/build.yaml" ]] \
  && pass "A1 refused record wrote nothing" || fail "A1 build.yaml must not exist after refusal"
printf '%s' "${REC_OUT}" | grep -q 'plan' && printf '%s' "${REC_OUT}" | grep -q 'gate1' \
  && pass "A1 refusal names plan and gate1" || fail "A1 refusal must name plan+gate1: $(printf '%s' "${REC_OUT}" | head -1)"
printf '%s' "${REC_OUT}" | grep -q 'pre-build' \
  && pass "A1 refusal says pre-build prefix" || fail "A1 refusal must say pre-build: $(printf '%s' "${REC_OUT}" | head -1)"
grep -q 'phase_record_refused' "${JOURNAL_REC}" && grep -q 'reason=pre_build_prefix' "${JOURNAL_REC}" \
  && pass "A1 journal phase_record_refused reason=pre_build_prefix" \
  || fail "A1 journal line absent: $(grep phase_record "${JOURNAL_REC}" | head -2)"

# A2: + plan (real brief) -> still refused, missing gate1 only
_brief "${A1_SIG}"
_record "${A1_SIG}" plan --status done --artifact "docs/handoff/dispatch-${A1_SIG}/brief.md" --task-id f37faa01 --owner suite:a1
[[ "${REC_RC}" == "0" ]] && pass "A2 plan with real brief recorded" || fail "A2 plan record rc=${REC_RC}: $(printf '%s' "${REC_OUT}" | head -1)"
_record "${A1_SIG}" build --status running --handle "dispatch-${A1_SIG}-build" --task-id f37faa01 --owner suite:a1
[[ "${REC_RC}" == "6" ]] && pass "A2 build still refused with plan only" || fail "A2 expected rc=6 got ${REC_RC}"
printf '%s' "${REC_OUT}" | grep -q 'missing gate1' \
  && pass "A2 refusal names gate1 alone" || fail "A2 refusal must name gate1: $(printf '%s' "${REC_OUT}" | head -1)"

# A3: + gate1 (--reason) -> build records
_record "${A1_SIG}" gate1 --status done --reason "suite gate1 decision: proceed to build" --task-id f37faa01 --owner suite:a1
[[ "${REC_RC}" == "0" ]] && pass "A3 gate1 recorded from explicit decision" || fail "A3 gate1 rc=${REC_RC}"
_record "${A1_SIG}" build --status running --handle "dispatch-${A1_SIG}-build" --task-id f37faa01 --owner suite:a1
[[ "${REC_RC}" == "0" ]] && pass "A3 build records once prefix exists" || fail "A3 expected rc=0 got ${REC_RC}"
grep -q '^status: running' "${ROOT}/docs/handoff/dispatch-${A1_SIG}/phases.d/build.yaml" 2>/dev/null \
  && pass "A3 build.yaml written status=running" || fail "A3 build.yaml missing/wrong"

# A4: Light class -> build records (owes neither plan nor gate1)
A4_SIG="f37faa04"
_record "${A4_SIG}" classify --status done --class Light --task-id f37faa04 --owner suite:a4
_record "${A4_SIG}" build --status running --handle "dispatch-${A4_SIG}-build" --task-id f37faa04 --owner suite:a4
[[ "${REC_RC}" == "0" ]] && pass "A4 Light lane build records (class-aware table)" || fail "A4 expected rc=0 got ${REC_RC}: $(printf '%s' "${REC_OUT}" | head -1)"

# A5: classless legacy lane -> fail-open
A5_SIG="f37faa05"
_record "${A5_SIG}" classify --status done --task-id f37faa05 --owner suite:a5
_record "${A5_SIG}" build --status running --handle "dispatch-${A5_SIG}-build" --task-id f37faa05 --owner suite:a5
[[ "${REC_RC}" == "0" ]] && pass "A5 classless legacy lane fails open" || fail "A5 expected rc=0 got ${REC_RC}"

# A6: REQUIRE_PHASES=0 -> kill-switch parity at the writer
A6_SIG="f37faa06"
REC_EXTRA=(LEADV2_REQUIRE_PHASES=0)
_record "${A6_SIG}" classify --status done --class Standard --task-id f37faa06 --owner suite:a6
_record "${A6_SIG}" build --status running --handle "dispatch-${A6_SIG}-build" --task-id f37faa06 --owner suite:a6
REC_EXTRA=()
[[ "${REC_RC}" == "0" ]] && pass "A6 REQUIRE_PHASES=0 kills the writer check too" || fail "A6 expected rc=0 got ${REC_RC}"

# A7: governance records (n/a) are exempt
A7_SIG="f37faa07"
_record "${A7_SIG}" classify --status done --class Standard --task-id f37faa07 --owner suite:a7
_record "${A7_SIG}" plan --status n/a --reason "no plan needed for this fixture" --task-id f37faa07 --owner suite:a7
_record "${A7_SIG}" gate1 --status n/a --reason "gate folded into plan for this fixture" --task-id f37faa07 --owner suite:a7
_record "${A7_SIG}" build --status running --handle "dispatch-${A7_SIG}-build" --task-id f37faa07 --owner suite:a7
[[ "${REC_RC}" == "0" ]] && pass "A7 waived/n/a prefix records exempt" || fail "A7 expected rc=0 got ${REC_RC}"

# A8: EVERY phase >= build is gated, not just build — review on a grace lane
A8_SIG="f37faa08"
printf 'review artifact\n' > "${ROOT}/review-out.txt"
_record "${A8_SIG}" classify --status done --class Standard --task-id f37faa08 --owner suite:a8
_record "${A8_SIG}" review --status done --artifact "review-out.txt" --task-id f37faa08 --owner suite:a8
[[ "${REC_RC}" == "6" ]] && pass "A8 review also gated by the pre-build prefix" || fail "A8 expected rc=6 got ${REC_RC}"

# ════════════════════════════════════════════════════════════════════════════
# Part B — the dispatcher's contract (leadv2-dispatch-code.sh e2e)
# ════════════════════════════════════════════════════════════════════════════
DISPATCH_EXTRA=(--acceptance-cmd true --no-probe-yet)

# _dispatch <case> <mission> [env VAR=val ...] -> OUT, RC; fresh cache per
# case; REQUIRE_PHASES/PHASE_GUARD_SCOPE explicitly absent so the D3 default
# is what runs (B5 sets =1 explicitly).
_dispatch() {
  local _case="$1" _mission="$2"; shift 2
  rm -f "${SPAWN_MARK}"; : > "${JOURNAL_REC}"
  local _kv _rc=0 _out _cache="${TMP}/cache-${_case}"
  rm -rf "${_cache}"; mkdir -p "${_cache}"
  _out="$(env \
    -u LEADV2_REQUIRE_PHASES -u PHASE_GUARD_SCOPE \
    -u LEADV2_LANE_START_SHA -u LEADV2_WORKTREE_DIR -u LEADV2_TASK_ID \
    -u LEADV2_PARENT_SESSION_ID -u LEADV2_DISPATCH_LANE_NAME \
    CLAUDE_PROJECT_ROOT="${ROOT}" \
    LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_PREMISE_BACKLOG_ROOTS="${ROOT}" \
    LEADV2_DISPATCH_CACHE_DIR="${_cache}" \
    LEADV2_STATE_BASE="${TMP}/state-${_case}" \
    LEADV2_LANE_WORK_ROOT="${ROOT}" \
    LEADV2_DISPATCH_GLM_BIN="${TMP}/fake-glm.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${TMP}/fake-subsession.sh" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_JOURNAL_BIN="${TMP}/journal-recorder.sh" \
    LEADV2_JOURNAL_REC="${JOURNAL_REC}" \
    LEADV2_SPAWN_MARK="${SPAWN_MARK}" \
    LEADV2_ROUTER_V2=0 \
    LEADV2_EXCLUDED_ARMS="__none__" \
    LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 \
    LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="${TMP}/judge-stub.sh" \
    GLM_POLICY_RESOLVER="${TMP}/glm-policy-stub.py" \
    LEADV2_DISPATCH_LANE_WORKTREE_BIN="${TMP}/lane-wt-stub.sh" \
    LEADV2_ROUTE_ARBITER_LIB="${TMP}/no-arbiter.lib" \
    LEADV2_DISPATCH_COST_ESTIMATE=0 \
    LEADV2_DISPATCH_LANE_LIVENESS_BIN="${TMP}/liveness-stub.sh" \
    "$@" \
    bash "${DISPATCH_SH}" "${_mission}" \
    --spawn --kind docs --task-class "${_DCLASS:-standard}" --task-id "f37f-${_case}" \
    ${DISPATCH_EXTRA[@]+"${DISPATCH_EXTRA[@]}"} 2>&1)" || _rc=$?
  OUT="${_out}"; RC="${_rc}"
}

# B1: fresh Standard lane — grace admits, build stamp refuses, no worker
M_B1="f37f suite B1: the bootstrap grace must not let build start without plan and gate1"
S_B1="$(_sig8_of "${M_B1}")"
_dispatch b1 "${M_B1}"
[[ "${RC}" == "3" ]] && pass "B1 grace lane dispatch aborts exit 3" || fail "B1 expected rc=3 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q 'phase_precondition_bootstrap' "${JOURNAL_REC}" \
  && pass "B1 bootstrap admission is journaled" || fail "B1 bootstrap journal line absent"
grep -q 'reason=build_prefix_unmet' "${JOURNAL_REC}" \
  && pass "B1 dispatch_refused reason=build_prefix_unmet journaled" \
  || fail "B1 build_prefix_unmet journal line absent: $(grep dispatch_refused "${JOURNAL_REC}" | head -2)"
printf '%s' "${OUT}" | grep -q 'build cannot start' \
  && pass "B1 refusal names the unmet ladder" || fail "B1 refusal text missing: $(printf '%s' "${OUT}" | tail -2)"
[[ ! -s "${SPAWN_MARK}" ]] && pass "B1 worker NEVER spawned" || fail "B1 worker spawned on unmet ladder: $(head -1 "${SPAWN_MARK}")"

# B2: record the printed remedies, re-dispatch the SAME mission -> full resume
_brief "${S_B1}"
_record "${S_B1}" plan --status done --artifact "docs/handoff/dispatch-${S_B1}/brief.md" --task-id "f37f-b1" --owner suite:b2-remedy
_record "${S_B1}" gate1 --status done --reason "suite B2 remedy: gate decision taken after B1 refusal" --task-id "f37f-b1" --owner suite:b2-remedy
_cache_b1="${TMP}/cache-b1"
_dispatch b1 "${M_B1}"   # same mission => same sig8; keep the SAME cache dir
[[ "${RC}" == "0" ]] && pass "B2 re-dispatch after remedies succeeds" || fail "B2 expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q '^SPAWN ' "${SPAWN_MARK}" && pass "B2 worker spawned (deadlock gone)" || fail "B2 worker not spawned after remedies"
grep -q '^status: running' "${ROOT}/docs/handoff/dispatch-${S_B1}/phases.d/build.yaml" 2>/dev/null \
  && pass "B2 build recorded through the real writer" || fail "B2 build.yaml missing"

# B3: classify+build:running on a POSITIVELY dead lane -> readmitted, resumable
M_B3="f37f suite B3: a stale running build on a dead lane must be resumable"
S_B3="$(_sig8_of "${M_B3}")"
REC_EXTRA=(LEADV2_REQUIRE_PHASES=0)   # seed the exact measured 2026-09-12 shape
_record "${S_B3}" classify --status done --class Standard --task-id "f37f-b3" --owner suite:b3-seed
_record "${S_B3}" build --status running --handle "dispatch-${S_B3}-build" --task-id "f37f-b3" --owner suite:b3-seed
REC_EXTRA=()
cp "${ROOT}/docs/handoff/dispatch-${S_B3}/phases.d/build.yaml" "${TMP}/b3-build-orig.yaml"
_dispatch b3 "${M_B3}" LEADV2_LIVENESS_VERDICT=dead:no_process
grep -q 'phase_precondition_stale_running_readmit' "${JOURNAL_REC}" && grep -q 'stale=build' "${JOURNAL_REC}" \
  && pass "B3 stale-running lane readmitted (journaled)" || fail "B3 readmit line absent: $(grep stale "${JOURNAL_REC}" | head -2)"
grep -q 'phase_precondition_refused' "${JOURNAL_REC}" \
  && fail "B3 must NOT carry a refusal line on a dead lane" || pass "B3 no phase_precondition_refused line"
grep -q 'reason=build_prefix_unmet' "${JOURNAL_REC}" \
  && pass "B3 prefix still owed (record refusal, not guard refusal)" || fail "B3 build_prefix_unmet line absent"
cmp -s "${TMP}/b3-build-orig.yaml" "${ROOT}/docs/handoff/dispatch-${S_B3}/phases.d/build.yaml" \
  && pass "B3 no phase file moved by hand" || fail "B3 build.yaml was rewritten/moved"
# ...and after the remedies it resumes fully — same mission, no hand-editing
_brief "${S_B3}"
_record "${S_B3}" plan --status done --artifact "docs/handoff/dispatch-${S_B3}/brief.md" --task-id "f37f-b3" --owner suite:b3-remedy
_record "${S_B3}" gate1 --status done --reason "suite B3 remedy: gate decision after stale readmit" --task-id "f37f-b3" --owner suite:b3-remedy
_dispatch b3 "${M_B3}" LEADV2_LIVENESS_VERDICT=dead:no_process
[[ "${RC}" == "0" ]] && pass "B3 lane resumes rc=0 after remedies" || fail "B3 resume expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q '^SPAWN ' "${SPAWN_MARK}" && pass "B3 resumed worker spawned" || fail "B3 resumed worker not spawned"

# B4: same seed, liveness alive -> refused (never reclaim on a guess)
M_B4="f37f suite B4: a live lane holding running build must stay refused"
S_B4="$(_sig8_of "${M_B4}")"
REC_EXTRA=(LEADV2_REQUIRE_PHASES=0)
_record "${S_B4}" classify --status done --class Standard --task-id "f37f-b4" --owner suite:b4-seed
_record "${S_B4}" build --status running --handle "dispatch-${S_B4}-build" --task-id "f37f-b4" --owner suite:b4-seed
REC_EXTRA=()
_dispatch b4 "${M_B4}" LEADV2_LIVENESS_VERDICT=alive
[[ "${RC}" == "3" ]] && pass "B4 live lane refused exit 3" || fail "B4 expected rc=3 got ${RC}"
grep -q 'phase_precondition_refused' "${JOURNAL_REC}" \
  && pass "B4 refusal journaled for live lane" || fail "B4 refusal line absent"
grep -q 'phase_precondition_stale_running_readmit' "${JOURNAL_REC}" \
  && fail "B4 live lane must never be reclaimed" || pass "B4 no readmit on alive verdict"
[[ ! -s "${SPAWN_MARK}" ]] && pass "B4 worker not started" || fail "B4 worker started"

# B5: fresh lane under explicit scope=full -> still refused (guard not weakened).
# scope=full is reached exactly the way G2 in test-phase-precondition.sh reaches
# it: an explicit LEADV2_REQUIRE_PHASES=1 on a Light-ROUTED dispatch (a Standard
# route exports PHASE_GUARD_SCOPE=pre-build at :8960, so `=1` alone never gives
# full scope there — the full-completion contract is pinned from the Light door).
_DCLASS=light
M_B5="f37f suite B5: full scope fresh lane must still refuse"
_dispatch b5 "${M_B5}" LEADV2_REQUIRE_PHASES=1
unset _DCLASS
[[ "${RC}" == "3" ]] && pass "B5 scope=full fresh lane refused exit 3" || fail "B5 expected rc=3 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q 'phase_precondition_refused' "${JOURNAL_REC}" \
  && pass "B5 phase_precondition_refused journaled" || fail "B5 refusal line absent: $(grep phase_precondition "${JOURNAL_REC}" | head -3)"
[[ ! -s "${SPAWN_MARK}" ]] && pass "B5 worker not started" || fail "B5 worker started under scope=full"

# B6: the grace is time-bounded — backdated classify-only lane is an anomaly
M_B6="f37f suite B6: bootstrap grace expires on an old classify-only lane"
S_B6="$(_sig8_of "${M_B6}")"
_record "${S_B6}" classify --status done --class Standard --task-id "f37f-b6" --owner suite:b6-seed
sed 's/^started_at: .*/started_at: 2026-09-01T00:00:00Z/' \
  "${ROOT}/docs/handoff/dispatch-${S_B6}/phases.d/classify.yaml" > "${TMP}/b6-classify.yaml" \
  && mv "${TMP}/b6-classify.yaml" "${ROOT}/docs/handoff/dispatch-${S_B6}/phases.d/classify.yaml"
_dispatch b6 "${M_B6}" LEADV2_BOOTSTRAP_GRACE_MAX_S=86400
[[ "${RC}" == "3" ]] && pass "B6 expired-grace lane refused exit 3" || fail "B6 expected rc=3 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"
grep -q 'bootstrap_grace_expired' "${JOURNAL_REC}" \
  && pass "B6 bootstrap_grace_expired journaled" || fail "B6 expired line absent: $(grep -i bootstrap "${JOURNAL_REC}" | head -3)"
grep -q 'phase_precondition_refused' "${JOURNAL_REC}" \
  && pass "B6 refusal journaled after grace expiry" || fail "B6 refusal line absent"
grep -q 'phase_precondition_bootstrap_admit' "${JOURNAL_REC}" \
  && fail "B6 expired lane must not be admitted" || pass "B6 no admit after expiry"
# B6b: young classify-only lane still gets the one-shot grace
M_B6B="f37f suite B6b: young classify-only lane still gets the grace"
S_B6B="$(_sig8_of "${M_B6B}")"
_record "${S_B6B}" classify --status done --class Standard --task-id "f37f-b6b" --owner suite:b6b-seed
_dispatch b6b "${M_B6B}" LEADV2_BOOTSTRAP_GRACE_MAX_S=86400
grep -q 'phase_precondition_bootstrap_admit' "${JOURNAL_REC}" \
  && pass "B6b young classify-only lane admitted by grace" || fail "B6b admit line absent: $(grep -i bootstrap "${JOURNAL_REC}" | head -3)"
grep -q 'reason=build_prefix_unmet' "${JOURNAL_REC}" \
  && pass "B6b build still refuses at the writer (grace admits, never replaces)" \
  || fail "B6b build_prefix_unmet line absent"

printf -- '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
exit 0
# bash-guard: allow
