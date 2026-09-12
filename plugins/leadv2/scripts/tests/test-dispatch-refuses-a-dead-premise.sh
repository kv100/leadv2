#!/usr/bin/env bash
# tests/test-dispatch-refuses-a-dead-premise.sh — PREMISE-PROBE-BEFORE-A-
# LANE-IS-DISPATCHED-01
# run-all-triggers: leadv2-dispatch-code
#
# The defect (measured 2026-09-10/11, wave B0): a lane starts against an
# already-fixed defect because a backlog row's status is set by hand and
# nothing closes it -- five of six dispatched rows were already fixed on
# main; lane c65d77ed1b3c burned 25 minutes producing a 509-line report of
# a fix that already existed (zero product diff).
#
# The gate under test lives in leadv2-dispatch-code.sh's cmd_resolve, before
# the burn gate / placement pin / ensure block / architect prepass / any
# ledger row / spawn: it runs the row's acceptance probe and refuses to
# spend the lane unless the premise is provably alive.
#
# THIS SUITE drives the REAL dispatch script end to end. The only things
# faked are one level BELOW it (the repo-native seams): fake launcher bins
# (LEADV2_DISPATCH_GLM_BIN / _SUBSESSION_BIN), a recording journal bin
# (LEADV2_JOURNAL_BIN), and the repo-owner's scripts/task-close.sh replaced
# by an argument-recording interceptor -- the same hermetic-fixture
# discipline as test-dispatch-ledger-task-id.sh and
# test-phase8-closes-the-backlog-row.sh. The probe commands themselves are
# REAL greps/sleeps against REAL fixture files: the green probe is green
# because the defect marker is genuinely absent, the red probe is red
# because it is genuinely present. A suite that substitutes the function it
# asserts about proves nothing.
#
# Cases (founder task id -> expected):
#   T1 GREEN       row probe green       -> rc=7, row closed via the seam
#                (shortid + --reason naming the task), journal
#                premise_dead task=<sig8> row=<sid>, worker NEVER started
#   T2 RED        row probe red          -> rc=0, dispatch proceeds,
#                worker started, row NOT closed
#   T3 NOPROBE    row, no probe at all   -> rc=8 reason=no_premise_probe,
#                remedy names task-add/--acceptance-cmd/acceptance_cmd,
#                no worker, no close
#   T4 UNREADABLE probe id only (Supabase probe_registry) -> rc=8
#                reason=probe_cmd_unreadable, remedy names a runnable path
#   T5 BUDGET     probe exceeds LEADV2_PREMISE_PROBE_BUDGET_SEC -> rc=8
#                reason=probe_budget_exceeded (premise_unknown class)
#   T6 NOTRUNNABLE probe command missing -> rc=8 reason=probe_not_runnable
#   T7 NO-ROW     --task-id resolving to no row, no probe -> rc=0 today's
#                ad-hoc contract preserved, worker started
#   T8 NO-SEAM    green probe but no scripts/task-close.sh in the repo ->
#                rc=7 still, row left to its owning repo, no worker
#   T9 AMBIG      2 rows match the founder id -> rc=8 reason=row_ambiguous
#   T10 DECLCMD    --acceptance-cmd 'true' with NO row -> rc=0, worker
#                started (declarative callers -- lane-shape, papercuts --
#                keep today's contract; the premise is a property of the ROW)
#   T11 MULTILINE  row acceptance_cmd is a YAML block scalar -> rc=8,
#                reason=acceptance_cmd_multiline, no worker
#   T12 ONELINE    row acceptance_cmd remains a one-line red probe -> rc=0,
#                worker started (quoting/execution unchanged)
#   T0 bash -n on the dispatch script and on this suite
#
# Negative controls (mutation, run via leadv2-mutation-control.sh) that MUST
# redden this suite:
#   (а) the premise-dead exit is neutralised (exit "${PREMISE_DEAD_RC}" ->
#       return 0): the green premise falls through to a spent lane -> T1 reds
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-refuses-a-dead-premise.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
# zsh safety (same as test-phase8-closes-the-backlog-row.sh): BASH_SOURCE is
# absent under zsh; fall back to $0 when it names a real file.
_t_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t_src" && -f "${0:-}" ]]; then _t_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

DISPATCH_SH="${SCRIPTS_ROOT}/leadv2-dispatch-cod""e.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

SUITE_SELF="$(cd "$(dirname "$_t_src")" && pwd)/$(basename "$_t_src")"
TMP="$(lv2_mktemp_dir premise-probe-test)"
trap 'rm -rf "$TMP"' EXIT
ROOT="${TMP}/repo"
CACHE_DIR="${TMP}/cache"
SPAWN_MARK="${TMP}/spawn-mark.log"
CLOSE_CAP="${TMP}/close-capture.log"
JOURNAL_REC="${TMP}/journal-record.log"

mkdir -p "${ROOT}/.claude/ref" "${ROOT}/docs/leadv2/.bus-offsets" "${ROOT}/platform" \
         "${ROOT}/docs" "${ROOT}/scripts"
( cd "${ROOT}" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed ) || { echo "fixture git init failed"; exit 1; }

# The probe corpus: two REAL files, one carrying the wave-B0 defect marker
# (red premise), one fixed (green premise). The probes below grep these
# files -- their verdicts are genuinely earned, never stubbed.
printf '#!/usr/bin/env bash\n# fixed lib: the wave-B0 defect marker is gone\n' > "${ROOT}/journal-lib-fixed.sh"
printf '#!/usr/bin/env bash\ntrap '"'"'exit 0'"'"' ERR\n# broken lib: WAVE0-DEFECT-MARKER present (live defect)\nWAVE0-DEFECT-MARKER here\n' > "${ROOT}/journal-lib-broken.sh"

cat > "${ROOT}/docs/tasks.yaml" <<YAML
total_open: 8
tasks:
- id: aaaagreen0001
  intent: 'TASK-PREMISE-GREEN-01: fixed defect, green probe'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: '! grep -q WAVE0-DEFECT-MARKER ${ROOT}/journal-lib-fixed.sh'
- id: bbbbred000002
  intent: 'TASK-PREMISE-RED-01: live defect, red probe'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: '! grep -q WAVE0-DEFECT-MARKER ${ROOT}/journal-lib-broken.sh'
- id: ccccnoprobe03
  intent: 'TASK-PREMISE-NOPROBE-01: row with no probe at all'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: true
- id: ddddunread004
  intent: 'TASK-PREMISE-UNREAD-01: probe id points into Supabase only'
  status: queued
  acceptance_probe_id: human-adhoc-deadbeef01
  needs_acceptance_probe: false
- id: eeeesleep0005
  intent: 'TASK-PREMISE-SLEEP-01: probe overruns the budget'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: 'sleep 30'
- id: ffffnoexec0006
  intent: 'TASK-PREMISE-NOEXEC-01: probe command does not exist'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: 'premise-nonexistent-cmd-xyz-42 --flag'
- id: 1111ambig0007
  intent: 'TASK-PREMISE-AMBIG-01: first of two rows sharing a founder id'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: 'true'
- id: 2222ambig0008
  intent: 'TASK-PREMISE-AMBIG-01: second of two rows sharing a founder id'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: 'true'
- id: 3333multiline11
  intent: 'TASK-PREMISE-MULTILINE-01: multiline acceptance command'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: |
    echo first line
    false
- id: 4444oneline0012
  intent: 'TASK-PREMISE-ONELINE-01: one-line acceptance command'
  status: queued
  acceptance_probe_id: null
  needs_acceptance_probe: false
  acceptance_cmd: '! grep -q WAVE0-DEFECT-MARKER ${ROOT}/journal-lib-broken.sh'
YAML
# bash-guard: allow

# ── the repo-native seams, faked one level BELOW the dispatch path ────────
# task-close.sh interceptor: records its arguments verbatim, exits 0 (the
# real seam's success contract). phase8's suite uses the same shape.
cat > "${ROOT}/scripts/task-close.sh" <<'EOF'
#!/usr/bin/env bash
printf 'CLOSE %s\n' "$*" >> "${LEADV2_CLOSE_CAP:-/dev/null}"
exit 0
EOF
chmod +x "${ROOT}/scripts/task-close.sh"

# Recording journal bin: the emit() callsite invokes
# `bash ${LEADV2_JOURNAL_BIN} append <task> <type> <line>`; recording every
# argument lets the suite assert the premise_dead journal line WITHOUT
# writing to any real journal tree.
cat > "${TMP}/journal-recorder.sh" <<'EOF'
#!/usr/bin/env bash
printf 'JOURNAL %s\n' "$*" >> "${LEADV2_JOURNAL_REC:-/dev/null}"
exit 0
EOF
chmod +x "${TMP}/journal-recorder.sh"

# Fake launchers (same shape as test-dispatch-ledger-task-id.sh): each
# records that it was invoked -- T1's whole point is that on a dead premise
# NEITHER is ever reached.
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

cat > "${ROOT}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
    codex_default_tier: standard
YAML

# The dispatcher derives its authoritative project root from its working
# directory and rejects a foreign environment root (FOREIGN-PROJECT-ROOT-
# GUARD-01): every dispatch below runs rooted in the fixture repo, with the
# reservation ledger, launchers and journal pointed at this TMP.
export LEADV2_LANE_WORK_ROOT="${ROOT}"
export LEADV2_ARM_EARLY_VERDICT_S=0
cd "${ROOT}"

# _dispatch <case-name> <founder-task-id> [extra env: VAR=val ...] ->
# sets OUT, RC, and resets the per-case capture files.
DISPATCH_EXTRA=()
_dispatch() {
  local _case="$1" _tid="$2"; shift 2
  rm -f "${SPAWN_MARK}" "${CLOSE_CAP}"
  : > "${JOURNAL_REC}"
  local -a _env=()
  local _kv
  for _kv in "$@"; do _env+=("$_kv"); done
  local _rc=0 _out
  _out="$(env \
    CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
    LEADV2_DISPATCH_GLM_BIN="${TMP}/fake-glm.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${TMP}/fake-subsession.sh" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_JOURNAL_BIN="${TMP}/journal-recorder.sh" \
    LEADV2_JOURNAL_REC="${JOURNAL_REC}" \
    LEADV2_SPAWN_MARK="${SPAWN_MARK}" \
    LEADV2_CLOSE_CAP="${CLOSE_CAP}" \
    LEADV2_ROUTER_V2=0 \
    LEADV2_EXCLUDED_ARMS="__none__" \
    LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 \
    ${_env[@]+"${_env[@]}"} \
    bash "${DISPATCH_SH}" "premise-probe suite ${_case} $$ $(date +%s 2>/dev/null || echo 0)" \
      --spawn --task-id "${_tid}" ${DISPATCH_EXTRA[@]+"${DISPATCH_EXTRA[@]}"} 2>&1)" || _rc=$?
  RC="${_rc}"; OUT="${_out}"
}
# bash-guard: allow

# ── T0: syntax ────────────────────────────────────────────────────────────
if bash -n "${DISPATCH_SH}" 2>/dev/null && bash -n "${SUITE_SELF}" 2>/dev/null; then
  pass "T0 bash -n dispatch script + suite"
else
  fail "T0 bash -n dispatch script + suite"
fi

# ── T1: green probe -> row closed, lane refused, worker never started ─────
_dispatch green TASK-PREMISE-GREEN-01
if [[ "${RC}" == "7" ]]; then pass "T1 green: exit 7"; else fail "T1 green: expected rc=7 got ${RC}"; fi
grep -q "premise dead" <<<"${OUT}" && pass "T1 last-line premise dead" || fail "T1 premise-dead stderr line missing: $(printf '%s' "${OUT}" | tail -1)"
if [[ "$(grep -c '^CLOSE ' "${CLOSE_CAP:-/dev/null}" 2>/dev/null || echo 0)" == "1" ]]; then
  pass "T1 task-close.sh called exactly once"
else
  fail "T1 task-close.sh call count != 1: $(cat "${CLOSE_CAP:-/dev/null}" 2>/dev/null | head -2)"
fi
grep -q '^CLOSE aaaagreen0001 --reason premise probe green at dispatch' "${CLOSE_CAP}" 2>/dev/null \
  && pass "T1 close targets the row shortid with the premise reason" \
  || fail "T1 close args wrong: $(head -1 "${CLOSE_CAP:-/dev/null}" 2>/dev/null)"
grep -q "premise_dead task=" "${JOURNAL_REC}" && grep -q "row=aaaagreen0001" "${JOURNAL_REC}" \
  && pass "T1 journal premise_dead task=<sig8> row=<sid>" \
  || fail "T1 journal premise_dead line absent: $(grep premise "${JOURNAL_REC}" | head -2)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T1 worker NEVER started" \
  || fail "T1 worker started on a dead premise: $(head -2 "${SPAWN_MARK}")"

# ── T2: red probe -> dispatch proceeds, worker started, row NOT closed ────
_dispatch red TASK-PREMISE-RED-01
if [[ "${RC}" == "0" ]]; then pass "T2 red: dispatch proceeds rc=0"; else fail "T2 red: expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"; fi
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "T2 worker started" || fail "T2 worker not started on a live premise"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T2 row NOT closed" || fail "T2 row closed on a live premise: $(head -1 "${CLOSE_CAP}")"

# ── T3: row with no probe -> refusal with remedy, nothing spent ───────────
_dispatch noprobe TASK-PREMISE-NOPROBE-01
if [[ "${RC}" == "8" ]]; then pass "T3 noprobe: exit 8"; else fail "T3 noprobe: expected rc=8 got ${RC}"; fi
grep -q "reason=no_premise_probe" <<<"${OUT}" && pass "T3 reason=no_premise_probe" || fail "T3 reason line missing: $(printf '%s' "${OUT}" | tail -1)"
grep -q -- "--acceptance-cmd" <<<"${OUT}" && grep -q "task-add.sh" <<<"${OUT}" && grep -q "acceptance_cmd" <<<"${OUT}" \
  && pass "T3 remedy names how to attach a probe" || fail "T3 remedy incomplete: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T3 worker not started" || fail "T3 worker started"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T3 row not closed" || fail "T3 row closed"

# ── T4: probe id readable only by Supabase -> refused, remedy names path ──
_dispatch unread TASK-PREMISE-UNREAD-01
if [[ "${RC}" == "8" ]]; then pass "T4 unreadable: exit 8"; else fail "T4 unreadable: expected rc=8 got ${RC}"; fi
grep -q "reason=probe_cmd_unreadable" <<<"${OUT}" && pass "T4 reason=probe_cmd_unreadable" || fail "T4 reason missing: $(printf '%s' "${OUT}" | tail -1)"
grep -q -- "--acceptance-cmd" <<<"${OUT}" && pass "T4 remedy names a runnable probe path" || fail "T4 remedy missing"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T4 worker not started" || fail "T4 worker started"

# ── T5: probe overruns the budget -> premise_unknown refusal ──────────────
_dispatch budget TASK-PREMISE-SLEEP-01 "LEADV2_PREMISE_PROBE_BUDGET_SEC=1"
if [[ "${RC}" == "8" ]]; then pass "T5 budget: exit 8"; else fail "T5 budget: expected rc=8 got ${RC}"; fi
grep -q "reason=probe_budget_exceeded" <<<"${OUT}" && pass "T5 reason=probe_budget_exceeded (premise_unknown)" || fail "T5 reason missing: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T5 worker not started" || fail "T5 worker started"

# ── T6: probe command itself missing -> premise_unknown refusal ───────────
_dispatch noexec TASK-PREMISE-NOEXEC-01
if [[ "${RC}" == "8" ]]; then pass "T6 not-runnable: exit 8"; else fail "T6 not-runnable: expected rc=8 got ${RC}"; fi
grep -q "reason=probe_not_runnable" <<<"${OUT}" && pass "T6 reason=probe_not_runnable" || fail "T6 reason missing: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T6 worker not started" || fail "T6 worker started"

# ── T7: --task-id resolving to no row keeps today's ad-hoc contract ───────
_dispatch norow TASK-UNRESOLVED-99
if [[ "${RC}" == "0" ]]; then pass "T7 no-row: dispatch proceeds rc=0"; else fail "T7 no-row: expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"; fi
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "T7 worker started (ad-hoc path intact)" || fail "T7 worker not started"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T7 nothing closed" || fail "T7 row closed with no row"

# ── T8: green probe, no task-close.sh seam -> still exit 7, row skipped ───
rm -f "${ROOT}/scripts/task-close.sh"
_dispatch noseam TASK-PREMISE-GREEN-01
if [[ "${RC}" == "7" ]]; then pass "T8 no-seam: exit 7 still"; else fail "T8 no-seam: expected rc=7 got ${RC}"; fi
grep -q "left to its owning repo" <<<"${OUT}" && pass "T8 seam absence logged, row left to owner" || fail "T8 seam-absence line missing: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T8 worker not started" || fail "T8 worker started"

# ── T9: two rows share the founder id -> refuse, close nothing ────────────
_dispatch ambig TASK-PREMISE-AMBIG-01
if [[ "${RC}" == "8" ]]; then pass "T9 ambiguous: exit 8"; else fail "T9 ambiguous: expected rc=8 got ${RC}"; fi
grep -q "reason=row_ambiguous" <<<"${OUT}" && pass "T9 reason=row_ambiguous" || fail "T9 reason missing: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T9 nothing closed" || fail "T9 row closed despite ambiguity"

# ── T10: bare --acceptance-cmd, no row -> declaration, not a premise ─────
rm -f "${SPAWN_MARK}" "${CLOSE_CAP}"; : > "${JOURNAL_REC}"
DISPATCH_EXTRA=(--acceptance-cmd 'true')
_dispatch declcmd TASK-UNRESOLVED-88
DISPATCH_EXTRA=()
if [[ "${RC}" == "0" ]]; then pass "T10 declarative --acceptance-cmd: dispatch proceeds rc=0"; else fail "T10 declarative cmd: expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"; fi
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "T10 worker started (declarative callers intact)" || fail "T10 worker not started"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T10 nothing closed" || fail "T10 row closed with no row"

# ── T11: multiline acceptance_cmd is refused before eval can split it ────
_dispatch multiline TASK-PREMISE-MULTILINE-01
if [[ "${LEADV2_PREMISE_TEST_VERBOSE:-0}" == "1" ]]; then
  printf '[TEST] T11 raw dispatch output BEGIN\n%s\n[TEST] T11 raw dispatch output END\n' "${OUT}"
fi
if [[ "${RC}" == "8" ]]; then pass "T11 multiline: exit 8"; else fail "T11 multiline: expected rc=8 got ${RC}"; fi
grep -q "reason=acceptance_cmd_multiline" <<<"${OUT}" \
  && pass "T11 reason=acceptance_cmd_multiline" \
  || fail "T11 reason line missing: $(printf '%s' "${OUT}" | tail -1)"
[[ ! -s "${SPAWN_MARK:-/dev/nonexistent}" ]] && pass "T11 worker not started" || fail "T11 worker started"

# ── T12: one-line acceptance_cmd retains the existing red path ────────────
_dispatch oneline TASK-PREMISE-ONELINE-01
if [[ "${LEADV2_PREMISE_TEST_VERBOSE:-0}" == "1" ]]; then
  printf '[TEST] T12 raw dispatch output BEGIN\n%s\n[TEST] T12 raw dispatch output END\n' "${OUT}"
fi
if [[ "${RC}" == "0" ]]; then pass "T12 one-line: dispatch proceeds rc=0"; else fail "T12 one-line: expected rc=0 got ${RC}: $(printf '%s' "${OUT}" | tail -1)"; fi
grep -q '^SPAWN ' "${SPAWN_MARK:-/dev/nonexistent}" && pass "T12 worker started" || fail "T12 worker not started"
[[ ! -s "${CLOSE_CAP:-/dev/nonexistent}" ]] && pass "T12 row NOT closed" || fail "T12 row closed on a live premise: $(head -1 "${CLOSE_CAP}")"

printf -- '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
exit 0
# bash-guard: allow
