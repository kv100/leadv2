#!/usr/bin/env bash
# tests/test-reaper-per-subject-candidate-report.sh —
# REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01
#
# leadv2-orphan-reaper.sh used to print exactly one collapsed line,
# `reaped: N subject(s) termed`. N=0 read identically whether every subject
# was clean or a whole subject's population never crossed its kill
# threshold -- the exact confusion behind the 2026-09-06T13:05Z incident: 18
# ppid=1 stale-sweeper orphans, none older than the 3600s stuck threshold,
# reported as "reaped: 0" and read as "clean" when it meant "seen, spared".
#
# This suite spawns a REAL fixture process with stale-sweeper-shaped argv,
# young enough to survive the age gate, and asserts the new per-subject line
# names it as a candidate even though it is not killed -- so a reader can no
# longer mistake "0 killed" for "0 seen".
# run-all-triggers: leadv2-orphan-reaper

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAPER="${SCRIPT_DIR}/../leadv2-orphan-reaper.sh"
FAIL=0

bash -n "${REAPER}" || { echo "ERROR: bash -n failed for ${REAPER}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
FIXTURE="${TMP_ROOT}/leadv2-stale-sweeper.sh"
cat > "${FIXTURE}" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "${FIXTURE}"

# Argv-shaped fixture: a real, young, orphaned (ppid=1 via setsid/disown)
# process whose command line matches the pattern reap_stuck_by_age greps for,
# but is nowhere near SWEEPER_STUCK_SEC old -- exactly the shape that must
# show up as a seen-but-spared candidate, never as an invisible zero.
( setsid "${FIXTURE}" leadv2-stale-sweeper.sh </dev/null >/dev/null 2>&1 & )
sleep 0.5
FIXTURE_PID="$(pgrep -f "leadv2-stale-sweeper.sh" | grep -v "$$" | tail -1)"
cleanup() { [[ -n "${FIXTURE_PID:-}" ]] && kill -9 "${FIXTURE_PID}" 2>/dev/null; rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

if [[ -z "${FIXTURE_PID}" ]]; then
  fail "fixture setup" "could not find the spawned fixture process by argv"
else
  out="$(LEADV2_REAPER_SWEEPER_STUCK_SEC=3600 bash "${REAPER}" --dry-run 2>&1)"
  sweeper_line="$(printf '%s\n' "${out}" | grep '^\[orphan-reaper\] sweeper:')"

  # --- test 1: the fixture is counted as a candidate ---
  if [[ "${sweeper_line}" =~ candidates=([0-9]+) ]] && (( ${BASH_REMATCH[1]} >= 1 )); then
    pass "young orphaned stale-sweeper fixture is counted as a candidate (candidates>=1)"
  else
    fail "candidate count" "sweeper line='${sweeper_line}' want candidates>=1"
  fi

  # --- test 2: it is spared (too young), and the line says so explicitly ---
  if [[ "${sweeper_line}" == *"would-kill=0"* ]]; then
    pass "young fixture is spared by the age gate (would-kill=0) -- and the line still shows it was SEEN"
  else
    fail "spared-but-visible" "sweeper line='${sweeper_line}' want would-kill=0 alongside candidates>=1"
  fi

  # --- test 3: the number carries its own boundary -- ppid=1 breakdown present ---
  if [[ "${sweeper_line}" == *"ppid=1: "* && "${sweeper_line}" == *"older_than="*"s: "* ]]; then
    pass "candidate count carries its own boundary (ppid=1 and older_than breakdown both present)"
  else
    fail "boundary breakdown" "sweeper line='${sweeper_line}' missing ppid=1/older_than breakdown"
  fi
fi

# --- test 4: MUTATION CONTROL -- neuter the counter increment INSIDE the
# function body (never a top-level/line-number insert): the seen-candidate
# increment for the sweeper kind is removed, so a real candidate reports
# candidates=0 again -- reintroducing the exact ambiguity this suite exists
# to catch. Confirms the suite actually exercises the counter, not just
# "reaper runs".
MUT_SH="${TMP_ROOT}/mutated-reaper.sh"
sed -E 's/sweeper\) *$/sweeper) : #NEGATIVE_CONTROL_NEUTERED/; s/_seen_sweeper=\$\(\(_seen_sweeper\+1\)\)/: #NEGATIVE_CONTROL_NEUTERED/' \
  "${REAPER}" > "${MUT_SH}"
if diff -q "${REAPER}" "${MUT_SH}" >/dev/null 2>&1; then
  fail "mutation control" "sed produced a byte-identical file -- the mutation never applied, this control proves nothing"
else
  ( setsid "${FIXTURE}" leadv2-stale-sweeper.sh </dev/null >/dev/null 2>&1 & )
  sleep 0.5
  MUT_PID="$(pgrep -f "leadv2-stale-sweeper.sh" | grep -v "$$" | tail -1)"
  mut_out="$(LEADV2_REAPER_SWEEPER_STUCK_SEC=3600 bash "${MUT_SH}" --dry-run 2>&1)"
  [[ -n "${MUT_PID:-}" ]] && kill -9 "${MUT_PID}" 2>/dev/null
  mut_sweeper_line="$(printf '%s\n' "${mut_out}" | grep '^\[orphan-reaper\] sweeper:')"
  if [[ "${mut_sweeper_line}" =~ candidates=([0-9]+) ]] && (( ${BASH_REMATCH[1]} == 0 )); then
    pass "MUTATION CONTROL: neutering the seen-candidate increment inside the function body drops candidates back to 0 (suite would go red)"
  else
    fail "mutation control" "mutated line='${mut_sweeper_line}' -- mutation did not neutralize the counter as intended"
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-reaper-per-subject-candidate-report.sh"
  exit 0
else
  echo "SOME FAILED: test-reaper-per-subject-candidate-report.sh"
  exit 1
fi
