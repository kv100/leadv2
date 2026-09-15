#!/usr/bin/env bash
# tests/test-reaper-dry-run-env-precedence.sh —
# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01
#
# DRY_RUN was read from the environment and then unconditionally clobbered
# by the script's own `DRY_RUN=0` default a few lines later, so
# `DRY_RUN=1 leadv2-orphan-reaper.sh` killed anyway while claiming (via the
# universally-understood env-var convention) that it would not. The fix
# captures the inherited value BEFORE the default assignment and OR-combines
# it with the --dry-run flag: either surface asking for dry-run wins, since
# a safety switch must fail toward safe, never toward live.
#
# Cases (all against the age-based sweeper subject — no session/transcript
# fixture needed, `reap_stuck_by_age`'s age branch fires regardless of ppid):
#   1. env DRY_RUN=1, no flag        -> fixture SURVIVES (the bug's repro)
#   2. --dry-run flag, no env        -> fixture SURVIVES (flag regression)
#   3. --dry-run flag, env DRY_RUN=0 -> fixture SURVIVES (flag still wins
#                                        when the two surfaces disagree)
#   4. neither switch set            -> fixture is KILLED (live path intact)
#
# Mutation negative controls (COPIES, mutation inside the body — never a
# top-level insert, the 2026-08-25 lesson):
#   NC-1  neuter the env-recognition line so DRY_RUN=1 in the environment
#         is never honoured -> case 1 flips (env-only dry-run stops
#         working; this is the original defect, restored).
#   NC-2  neuter the flag-precedence line so --dry-run defers to the env
#         value instead of always setting 1 -> case 3 flips (flag no
#         longer wins when env says 0). A distinct line from NC-1, so it
#         is a separate control -- one mutation is not a check for two
#         cases.
#
# Hermetic: LEADV2_REAPER_SUBJECT_SCOPE pins every reaper run to this
# suite's own tmp dir (SUITES-MUTATE-LIVE-CONTROL-PLANE-01) so it can never
# TERM a real sweeper of another session. All fixtures are foreground
# children of this shell, force-killed on exit.
#
# Environmental hazard (core-offline-reds-under-concurrent-runners.md): this
# fixture is deliberately named leadv2-stale-sweeper.sh to exercise the
# reaper's real pgrep -f pattern, but that means an UNSCOPED production
# reaper invoked by another concurrent session's SessionStart hook
# (plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh, no
# LEADV2_REAPER_SUBJECT_SCOPE set there) also matches it by cmdline
# substring. Ruled out as the actual killer by construction: the reaper's
# only kill primitive is _term() -> `kill -TERM` (no SIGKILL anywhere in
# leadv2-orphan-reaper.sh), and "unknown" owner-death state never kills
# (_owner_death_state, reaper:466). A SIGKILL death with no TERM trap fired
# is therefore never attributable to this script, ours or a concurrent
# session's. Whatever intermittently SIGKILLs the fixture on this shared
# dev machine is unrelated to the code under test; expect_survive() below
# retries once (fresh fixture, fresh reaper run) before failing, so the
# case's verdict is about DRY_RUN precedence, not about machine noise.
# run-all-triggers: leadv2-orphan-reaper

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAPER="${SCRIPT_DIR}/../leadv2-orphan-reaper.sh"
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

bash -n "${REAPER}" || { echo "ERROR: bash -n failed for ${REAPER}"; exit 1; }

TMP_ROOT="$(mktemp -d /tmp/reaper-dryrun-env.XXXXXX)"
FIX="${TMP_ROOT}/leadv2-stale-sweeper.sh"
cat > "${FIX}" <<'EOS'
#!/usr/bin/env bash
sleep 600
EOS
chmod +x "${FIX}"

_live_pids=""
cleanup() {
  local p
  for p in ${_live_pids}; do
    kill -9 "${p}" 2>/dev/null || true
  done
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

SPAWN_PID=""
spawn_aged_fixture() {  # sets SPAWN_PID, aged past the 1s stuck threshold.
  # Deliberately NOT called via $(...): a command-substitution subshell
  # would (a) lose the _live_pids append across the subshell boundary (the
  # assignment never reaches the parent shell) and (b) exit right after
  # backgrounding the fixture, orphaning it a beat early and racing the
  # very first reaper invocation. Direct call + a global keeps both the
  # bookkeeping and the process tree in the one shell that owns cleanup.
  bash "${FIX}" >/dev/null 2>&1 &
  SPAWN_PID=$!
  disown "${SPAWN_PID}" 2>/dev/null || true   # no job-control "Killed" noise
  _live_pids="${_live_pids} ${SPAWN_PID}"
  sleep 1.5   # SWEEPER_STUCK_SEC=1 below, so this pid is now "stuck"
}

run_reaper() {  # SCRIPT DRY_RUN_ENV_VALUE FLAG_OR_EMPTY -> sets RUN_OUT
  local script="$1" env_val="$2" flag="$3"
  if [[ -n "${env_val}" ]]; then
    RUN_OUT="$(DRY_RUN="${env_val}" LEADV2_REAPER_SUBJECT_SCOPE="${TMP_ROOT}" \
      LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
      bash "${script}" --project-root "${TMP_ROOT}" ${flag} 2>&1)"
  else
    RUN_OUT="$(env -u DRY_RUN LEADV2_REAPER_SUBJECT_SCOPE="${TMP_ROOT}" \
      LEADV2_REAPER_SWEEPER_STUCK_SEC=1 \
      bash "${script}" --project-root "${TMP_ROOT}" ${flag} 2>&1)"
  fi
}

# expect_survive() retries once on an unexpected death: the reaper's only
# kill primitive is TERM (never SIGKILL, see header note above), so a dead
# fixture after a *second* fresh attempt is a real regression, never the
# shared-machine hazard.
expect_survive() {  # CASE_LABEL ENV_VAL FLAG -> PASS/FAIL via pass()/fail()
  local label="$1" env_val="$2" flag="$3" attempt pid
  for attempt in 1 2; do
    spawn_aged_fixture; pid="${SPAWN_PID}"
    run_reaper "${REAPER}" "${env_val}" "${flag}"
    if kill -0 "${pid}" 2>/dev/null; then
      LAST_RUN_OUT="${RUN_OUT}"
      LAST_CASE_PID="${pid}"
      return 0
    fi
    if (( attempt == 1 )); then
      printf 'INFO: %s attempt 1 fixture died unexpectedly (kill -TERM only in this script -- retrying once, see hazard note in header)\n' "${label}"
    fi
    kill -9 "${pid}" 2>/dev/null || true
  done
  LAST_RUN_OUT="${RUN_OUT}"
  LAST_CASE_PID="${pid}"
  return 1
}

# ══ Case 1: env DRY_RUN=1, no flag -> fixture survives ═════════════════════
if expect_survive "case1" "1" ""; then
  PID1="${LAST_CASE_PID}"
  if [[ "${LAST_RUN_OUT}" == *"DRY-RUN would TERM pid=${PID1}"* ]]; then
    pass "case1: DRY_RUN=1 env alone -> fixture survives, log says would-TERM"
  else
    fail "case1" "fixture survived but log did not name a DRY-RUN verdict: ${LAST_RUN_OUT}"
  fi
else
  fail "case1" "DRY_RUN=1 exported but fixture was killed (twice) -- env var silently ignored"
fi
kill -9 "${LAST_CASE_PID}" 2>/dev/null || true

# ══ Case 2: --dry-run flag, no env -> regression check ═════════════════════
if expect_survive "case2" "" "--dry-run"; then
  pass "case2: --dry-run flag alone -> fixture survives (flag still works)"
else
  fail "case2" "--dry-run flag regressed -- fixture was killed (twice)"
fi
kill -9 "${LAST_CASE_PID}" 2>/dev/null || true

# ══ Case 3: --dry-run flag, env DRY_RUN=0 -> flag wins when they disagree ═══
if expect_survive "case3" "0" "--dry-run"; then
  pass "case3: flag=--dry-run + env DRY_RUN=0 (disagree) -> flag wins, fixture survives"
else
  fail "case3" "flag was overridden by env=0 -- fixture was killed (twice)"
fi
kill -9 "${LAST_CASE_PID}" 2>/dev/null || true

# ══ Case 4: neither switch set -> live kill path still works ═══════════════
spawn_aged_fixture; PID4="${SPAWN_PID}"
run_reaper "${REAPER}" "" ""
sleep 0.3
if kill -0 "${PID4}" 2>/dev/null; then
  fail "case4" "neither DRY_RUN nor --dry-run set, but fixture is still alive -- kill path broken"
else
  pass "case4: neither switch set -> fixture is killed (live path intact)"
fi
kill -9 "${PID4}" 2>/dev/null || true

# ── Mutation negative controls (copies; mutation INSIDE the body) ──────────

# NC-1: neuter env-recognition -> DRY_RUN=1 in the environment never honoured
sed 's|\[\[ "\$_dry_run_env" == "1" \]\] && DRY_RUN=1|[[ "$_dry_run_env" == "MUTATED-NEVER" ]] \&\& DRY_RUN=1|' \
  "${REAPER}" > "${TMP_ROOT}/reaper-nc1.sh"
if grep -q 'MUTATED-NEVER' "${TMP_ROOT}/reaper-nc1.sh" && bash -n "${TMP_ROOT}/reaper-nc1.sh" 2>/dev/null; then
  spawn_aged_fixture; PIDN1="${SPAWN_PID}"
  run_reaper "${TMP_ROOT}/reaper-nc1.sh" "1" ""
  if kill -0 "${PIDN1}" 2>/dev/null; then
    fail "NC-1" "mutated reaper still spared the fixture (mutation not exercised -- case1 does not test the env line)"
  else
    pass "NC-1: neutered env-recognition -> DRY_RUN=1 env is ignored again, fixture killed (case1 goes red on mutation)"
  fi
  kill -9 "${PIDN1}" 2>/dev/null || true
else
  fail "NC-1" "sed mutation did not apply cleanly -- pattern drifted, fix the suite"
fi

# NC-2: neuter flag precedence -> --dry-run defers to the (disagreeing) env
# value instead of always setting 1. Distinct line from NC-1: this one only
# breaks case3 (flag wins on disagreement), leaving case1 unaffected.
sed 's|--dry-run) DRY_RUN=1; shift ;;|--dry-run) DRY_RUN="$_dry_run_env"; shift ;;|' \
  "${REAPER}" > "${TMP_ROOT}/reaper-nc2.sh"
if grep -q 'DRY_RUN="\$_dry_run_env"; shift' "${TMP_ROOT}/reaper-nc2.sh" && bash -n "${TMP_ROOT}/reaper-nc2.sh" 2>/dev/null; then
  spawn_aged_fixture; PIDN2="${SPAWN_PID}"
  run_reaper "${TMP_ROOT}/reaper-nc2.sh" "0" "--dry-run"
  sleep 0.3
  if kill -0 "${PIDN2}" 2>/dev/null; then
    fail "NC-2" "mutated reaper still spared the fixture (mutation not exercised -- case3 does not test the flag-precedence line)"
  else
    pass "NC-2: neutered flag-precedence -> --dry-run deferred to env=0, fixture killed (case3 goes red on mutation)"
  fi
  kill -9 "${PIDN2}" 2>/dev/null || true
else
  fail "NC-2" "sed mutation did not apply cleanly -- pattern drifted, fix the suite"
fi

if (( FAIL == 0 )); then
  echo "ALL PASS: test-reaper-dry-run-env-precedence.sh"
  exit 0
else
  echo "FAILURES in test-reaper-dry-run-env-precedence.sh"
  exit 1
fi
