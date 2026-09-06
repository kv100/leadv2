#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dod-gate.sh run-all.sh
# (triggers are BASENAMES -- parse_suite_triggers rejects any token containing "/"
#  with a FATAL for the whole run, and maps token -> suite by name, so "lib/..." was
#  both invalid and unnecessary. I wrote the path form here and broke selection for
#  every session in this repo; run-all --scope changed in THIS repo catches it in one
#  run, which is the run I owed and did not make.)
# tests/test-dod-gate-suite-registration.sh — DOD-GATE-KILLS-A-REGISTERED-SUITE-01.
#
# The DoD gate's check (c) asks "is this new suite registered with run-all?" and a
# NO does not merely mark a lane red -- it ends it (`dispatch_terminal terminal=dead
# cause=review_dod_fail`, lane 3a86546f on 2026-09-06; the worker had already written
# everything and the work survived only because a human went looking).
#
# It answered by parsing tests/run-all.sh with a regexp written for the leadv2 repo's
# scalar `EXTRA_SUITE_MAP="`. persona-engine declares `declare -A EXTRA_SUITE_MAP=(`
# with suite BASENAMES as values, so the extraction returned zero rows, the comparison
# was unreachable, and every suite under tests/unit/ -- the only place that repo keeps
# its suites -- was "unregistered". Survival depended on which directory a suite lived
# in, not on whether it was registered.
#
# Two verdict paths reach this check, so this file exercises both and mutates both:
#   1. run-all's OWN selection (`[SELECT] <path>` under the select-only env var)
#   2. the EXTRA_SUITE_MAP parser, now form-agnostic, kept only as a fallback
# and a third outcome that did not exist before: when NEITHER can answer, the check
# reports UNDETERMINED and returns 2. A guard that cannot check must say so rather
# than kill a lane -- that is the whole lesson of the row.
#
# DECLARED NEGATIVE CONTROLS (both inside the gate's own function bodies):
#   M1  make _dod_run_all_selection return 1 always => case (a) goes RED (that fixture
#       has no map at all, so selection is its only path).
#   M2  delete the FORM 2 (declare -A) block in _dod_extra_suite_map_values => cases
#       (c) and (g) go RED -- exactly the production defect, reproduced.
# The two "unregistered" cases (b) and (d) must stay RED-correct (i.e. keep failing
# the fixture suite) under both mutations: fixing the gate must not turn it into a
# rubber stamp, which is the more expensive direction of the two.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="${LEADV2_DOD_GATE_LIB:-${PLUGIN_SCRIPTS}/lib/leadv2-dod-gate.sh}"
[[ -f "${GATE}" ]] || { echo "FATAL: gate lib not found: ${GATE}" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf -- '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf -- '[TEST] FAIL: %s\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dod-reg.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT

# shellcheck disable=SC1090
. "${GATE}" 2>/dev/null || { echo "FATAL: cannot source the gate lib" >&2; exit 2; }
for fn in _dod_check_c _dod_extra_suite_map_values _dod_run_all_selection; do
  if declare -F "${fn}" >/dev/null 2>&1; then ok "gate exposes ${fn}"; else bad "gate does not expose ${fn}"; fi
done
[[ ${FAIL} -eq 0 ]] || { printf -- '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1; }

mkrepo() { # <name> <mode: select|array|string|none> -> prints root
  local root="${WORK}/$1" mode="$2"
  mkdir -p "${root}/tests/unit"
  case "${mode}" in
    select)
      cat > "${root}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
# No EXTRA_SUITE_MAP at all: this fixture can only be answered by the selection.
if [[ "${PE_RUN_ALL_SELECT_ONLY:-0}" == "1" || "${LEADV2_RUN_ALL_SELECT_ONLY:-0}" == "1" ]]; then
  printf '[SELECT] %s\n' "tests/unit/test-registered.sh"
  printf 'run-all: 1 selected, scope=changed, select_only=1\n'
  exit 0
fi
exit 0
EOF
      ;;
    array)
      cat > "${root}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
# persona-engine's shape: associative array, values are suite BASENAMES.
declare -A EXTRA_SUITE_MAP=(
  ["agent/thing.sh"]="test-registered.sh test-other.sh"
  [".claude/hooks/x.sh"]="test-hooky.sh"
)
exit 0
EOF
      ;;
    string)
      cat > "${root}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
# leadv2's shape: scalar string rows, values are repo-relative paths.
EXTRA_SUITE_MAP="agent/thing.sh:tests/unit/test-registered.sh
.claude/hooks/x.sh:tests/unit/test-hooky.sh"
exit 0
EOF
      ;;
    none)
      cat > "${root}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
      ;;
  esac
  chmod +x "${root}/tests/run-all.sh"
  printf '%s' "${root}"
}

mkdiff() { # <file> <path...>
  local out="$1"; shift
  : > "${out}"
  local p
  for p in "$@"; do
    printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$p" "$p" "$p" >> "${out}"
  done
}

run_check() { # <root> <diff> -> RC, OUT
  OUT="$(_dod_check_c "$1" "${WORK}/taskdir" "$2" 2>&1)"; RC=$?
  return 0
}
mkdir -p "${WORK}/taskdir"

# ── (a) run-all's own selection answers, with no map anywhere ───────────────
R_SEL="$(mkrepo sel select)"
mkdiff "${WORK}/d-sel.diff" "tests/unit/test-registered.sh"
run_check "${R_SEL}" "${WORK}/d-sel.diff"
if [[ "${RC}" == "0" ]] && grep -q 'dod_pass' <<< "${OUT}"; then
  ok "(a) a suite run-all SELECTS passes, with no EXTRA_SUITE_MAP in the repo at all"
else
  bad "(a) rc=${RC} out=${OUT}"
fi

# ── (b) NEG-CTL: not selected, not mapped -> still an honest failure ────────
mkdiff "${WORK}/d-sel-bad.diff" "tests/unit/test-invented.sh"
run_check "${R_SEL}" "${WORK}/d-sel-bad.diff"
if [[ "${RC}" == "1" ]] && grep -q 'dod_fail check=suite_unregistered' <<< "${OUT}"; then
  ok "(b) NEG-CTL: an unselected, unmapped suite still fails the gate"
else
  bad "(b) NEG-CTL: rc=${RC} out=${OUT} — the fix turned the gate into a rubber stamp"
fi

# ── (c) parser fallback, persona-engine's array form with basename values ──
R_ARR="$(mkrepo arr array)"
mkdiff "${WORK}/d-arr.diff" "tests/unit/test-registered.sh"
run_check "${R_ARR}" "${WORK}/d-arr.diff"
if [[ "${RC}" == "0" ]] && grep -q 'dod_pass' <<< "${OUT}"; then
  ok "(c) declare -A map with a BASENAME value registers a tests/unit/ suite"
else
  bad "(c) rc=${RC} out=${OUT} — the production defect, unfixed"
fi

# ── (d) NEG-CTL for the parser path ────────────────────────────────────────
mkdiff "${WORK}/d-arr-bad.diff" "tests/unit/test-nowhere.sh"
run_check "${R_ARR}" "${WORK}/d-arr-bad.diff"
if [[ "${RC}" == "1" ]] && grep -q 'suite_unregistered' <<< "${OUT}"; then
  ok "(d) NEG-CTL: a suite absent from the array map still fails"
else
  bad "(d) NEG-CTL: rc=${RC} out=${OUT}"
fi

# ── (e) leadv2's string form, with path values, still works ────────────────
R_STR="$(mkrepo str string)"
mkdiff "${WORK}/d-str.diff" "tests/unit/test-registered.sh"
run_check "${R_STR}" "${WORK}/d-str.diff"
if [[ "${RC}" == "0" ]]; then
  ok "(e) the scalar string form is not regressed by the new one"
else
  bad "(e) rc=${RC} out=${OUT} — the old form stopped working"
fi

# ── (f) neither instrument can answer -> UNDETERMINED, never a kill ────────
R_NONE="$(mkrepo none none)"
mkdiff "${WORK}/d-none.diff" "tests/unit/test-whatever.sh"
run_check "${R_NONE}" "${WORK}/d-none.diff"
if [[ "${RC}" == "2" ]] && grep -q 'undetermined' <<< "${OUT}"; then
  ok "(f) no selection and no map: reports UNDETERMINED (rc=2), does not fail the lane"
else
  bad "(f) rc=${RC} out=${OUT} — an instrument fault still reads as a verdict"
fi

# ── (g) the live tree: the map that started this ───────────────────────────
PE_ROOT="${LEADV2_DOD_LIVE_REPO:-${HOME}/Projects/persona-engine}"
if [[ -f "${PE_ROOT}/tests/run-all.sh" ]]; then
  live_vals="$(_dod_extra_suite_map_values "${PE_ROOT}")"
  if [[ -n "${live_vals}" ]] && grep -qxF 'test-sessionstart-hook-schema.sh' <<< "${live_vals}"; then
    ok "(g) live persona-engine map yields $(printf '%s\n' "${live_vals}" | wc -l | tr -d ' ') values incl. a real registered basename"
  else
    bad "(g) live persona-engine map still parses to nothing — the reported defect is unfixed"
  fi
else
  bad "(g) live repo not found at ${PE_ROOT} (set LEADV2_DOD_LIVE_REPO) — this case must not silently skip"
fi

# ── (h)(i)(j) sustained blindness announces itself ──────────────────────────
# A dod_skip line in a log nobody reads is indistinguishable from no problem, so
# every UNDETERMINED verdict is also recorded, and the day's count announces
# itself once it crosses the threshold. Without this the gate could answer
# UNDETERMINED forever and we would learn it from the next lost lane.
export LEADV2_STATE_ROOT="${WORK}/state"
export LEADV2_DOD_BLIND_ALERT_N=3
BLIND_LOG="${LEADV2_STATE_ROOT}/dod-undetermined.log"
rm -f "${BLIND_LOG}"

run_check "${R_NONE}" "${WORK}/d-none.diff"
if [[ -s "${BLIND_LOG}" ]] && [[ "$(grep -c . "${BLIND_LOG}")" == "1" ]]; then
  ok "(h) an UNDETERMINED verdict records one line"
else
  bad "(h) nothing recorded: $(cat "${BLIND_LOG}" 2>/dev/null | tr '\n' '|')"
fi
if grep -q 'dod_blind_streak' <<< "${OUT}"; then
  bad "(h2) one blind verdict already cries streak — the threshold does nothing"
else
  ok "(h2) one blind verdict is not yet a streak (threshold respected)"
fi

run_check "${R_NONE}" "${WORK}/d-none.diff"
run_check "${R_NONE}" "${WORK}/d-none.diff"
if grep -q 'dod_blind_streak check=suite_registration count=3' <<< "${OUT}"; then
  ok "(i) the third blind verdict of the day announces itself with a count"
else
  bad "(i) no dod_blind_streak at the threshold — out=${OUT}"
fi

# (j) NEG-CTL: a check that CAN answer must not touch the counter. Without this
# the counter would fill from healthy runs and the alert would mean nothing.
before="$(grep -c . "${BLIND_LOG}" 2>/dev/null || printf '0')"
run_check "${R_ARR}" "${WORK}/d-arr.diff"
after="$(grep -c . "${BLIND_LOG}" 2>/dev/null || printf '0')"
if [[ "${RC}" == "0" && "${before}" == "${after}" ]]; then
  ok "(j) NEG-CTL: a check that answers records nothing (counter stays ${after})"
else
  bad "(j) NEG-CTL: rc=${RC} counter ${before} -> ${after}"
fi
unset LEADV2_STATE_ROOT LEADV2_DOD_BLIND_ALERT_N

printf -- '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
