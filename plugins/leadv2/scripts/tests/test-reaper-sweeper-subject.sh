#!/usr/bin/env bash
# tests/test-reaper-sweeper-subject.sh —
# REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01
#
# The orphan reaper's sweeper/cleanup subjects were AGE-gated only (3600s /
# 1800s stuck thresholds). The orphan population is reparented to ppid=1
# within a minute and lives 1-20 minutes — it NEVER survives to the age
# gate, so the reaper printed an honest "reaped: 0" over 18 live orphans
# (2026-09-06T13:05Z). The fix added a second, positive-death branch: a
# ppid=1 subject whose OWNING session is provably dead (env CLAUDE_PID gone
# by the three-answer kill -0: rc=0/EPERM live, ESRCH dead) is reaped NOW,
# leaves-first (grandchildren before children before the subject —
# CONTROL-PLANE-SATURATES-01/reaper-constraint-20260906T1550Z.md).
#
# This suite is the PAIRED control the mission demands — one half without
# the other is not accepted:
#   A. a LIVE owner's detached sweep SURVIVES the reaper (and a second
#      pass after a re-spawn) — without this the reaper is a jammer;
#   B. a DEAD owner's orphaned sweep, younger than every age gate, IS
#      reaped by the death sign alone, chain terminated leaves-first,
#      zero residue.
# Verdicts are by strict argv COUNTS and pid liveness, never by kill's
# exit code (rc=0 said nothing the day the wrapper died and the watcher
# survived).
#
# Hermeticity: every reaper run here sets LEADV2_REAPER_SUBJECT_SCOPE to
# this run's tmp dir, so the suite can never TERM a real sweeper, pulse or
# beat-loop of another session (SUITES-MUTATE-LIVE-CONTROL-PLANE-01).
#
# Negative control (§4) inverts the death-sign comparison INSIDE
# reap_stuck_by_age's body — never a line-number/top-level insert (a
# 2026-08-25 measurement was invalidated by exactly that mistake: an insert
# that lands at top level reddens every suite for the wrong reason and
# reads as a pass).
# run-all-triggers: leadv2-orphan-reaper

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAPER="${SCRIPT_DIR}/../leadv2-orphan-reaper.sh"
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

bash -n "${REAPER}" || { echo "ERROR: bash -n failed for ${REAPER}"; exit 1; }

TMP_ROOT="$(mktemp -d /tmp/pe-reaper-sweeper.XXXXXX)"
mkdir -p "${TMP_ROOT}/pids"
SW="${TMP_ROOT}/leadv2-stale-sweeper.sh"
CL="${TMP_ROOT}/leadv2-worktree-cleanup.sh"

cat > "${SW}" <<'EOS'
#!/usr/bin/env bash
# fixture sweeper: spawns a cleanup-shaped child (which spawns a grandchild
# sleep), then holds — models the real sweeper->cleanup->grandchild chain.
d="$(dirname "$0")"
echo $$ > "${d}/pids/sweeper.pid"
"${d}/leadv2-worktree-cleanup.sh" --sweep-dead &
sleep 600
EOS
cat > "${CL}" <<'EOS'
#!/usr/bin/env bash
# fixture cleanup: holds with a grandchild sleep — the leaf the reaper must
# terminate FIRST.
d="$(dirname "$0")"
echo $$ > "${d}/pids/cleanup.pid"
sleep 600 &
echo $! > "${d}/pids/grandchild.pid"
sleep 600
EOS
chmod +x "${SW}" "${CL}"

kill_tree_9() {  # PID — SIGKILL descendants then the pid (test cleanup only)
  local p="$1" c
  [[ "${p}" =~ ^[0-9]+$ ]] || return 0
  for c in $(pgrep -P "${p}" 2>/dev/null); do
    kill_tree_9 "${c}"
  done
  kill -9 "${p}" 2>/dev/null || true
}

cleanup() {
  local f p
  for f in "${TMP_ROOT}"/pids/*.pid; do
    [[ -f "${f}" ]] || continue
    kill_tree_9 "$(cat "${f}" 2>/dev/null || true)"
  done
  for p in $(fixture_pids leadv2-stale-sweeper.sh) $(fixture_pids leadv2-worktree-cleanup.sh); do
    kill_tree_9 "${p}"
  done
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

# owners: a LIVE one (a held sleep, alive for the whole suite — stand-in for
# the owning claude) and a PROVABLY dead one (spawned, killed, waited).
sleep 600 & LIVE_OWNER=$!
sleep 0.2 & DEAD_OWNER=$!
kill -9 "${DEAD_OWNER}" 2>/dev/null; wait "${DEAD_OWNER}" 2>/dev/null
kill -0 "${LIVE_OWNER}" 2>/dev/null || fail "owners" "live owner died during setup"
if kill -0 "${DEAD_OWNER}" 2>/dev/null; then
  fail "owners" "dead owner still answers kill -0 — setup is wrong, every later verdict would be meaningless"
fi

# spawn_fixture OWNER_PID — double-fork detach (no setsid on macOS): the
# inner subshell exits, the fixture reparents to launchd (ppid=1), exactly
# the orphan shape. Owner identity rides in the ENV, which is where the
# reaper reads it (ps eww, same-user).
spawn_fixture() {
  ( ( env CLAUDE_PID="$1" CLAUDE_CODE_SESSION_ID="00000000-0000-4000-8000-000000000000" \
        "${SW}" >/dev/null 2>&1 & ) )
}

# strict argv census of THIS run's fixtures only. The needle travels in the
# ENVIRONMENT, never in argv: an argv-carried needle self-matches the very
# awk doing the counting (the mission's "count by argv, not pgrep -f"
# lesson, one storey down).
fixture_pids() {  # NAME -> pids whose argv word is TMP_ROOT/NAME...
  # export, never a pipeline prefix: bash 3.2 does not propagate `VAR=x a |
  # b` into b's environment (measured: awk saw an empty needle and the census
  # went blind while the fixture sat visible in ps).
  REAPER_T_NEEDLE="${TMP_ROOT}/$1"
  export REAPER_T_NEEDLE
  ps ax -o pid=,command= | awk '
    ENVIRON["REAPER_T_NEEDLE"] == "" { exit }
    {
      for (i = 2; i <= NF; i++)
        if (index($i, ENVIRON["REAPER_T_NEEDLE"]) == 1) { print $1; break }
    }'
}

run_scoped_reaper() {  # sets REAP_OUT
  REAP_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" \
              LEADV2_REAPER_PROJECTS_DIR="${TMP_ROOT}/projects-absent" \
              LEADV2_REAPER_SUBJECT_SCOPE="${TMP_ROOT}" \
              bash "${REAPER}" 2>&1)"
}

wait_orphaned() {  # PID — rc=0 once ppid==1
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [[ "$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')" == "1" ]] && return 0
    sleep 0.3
  done
  return 1
}

# ══ A: a live owner's detached sweep survives the reaper — twice ════════════
spawn_fixture "${LIVE_OWNER}"
sleep 0.8
A1="$(fixture_pids leadv2-stale-sweeper.sh | head -1)"
A2PID=""
if [[ -z "${A1}" ]]; then
  fail "A setup" "live-owner fixture did not spawn"
else
  wait_orphaned "${A1}" \
    || fail "A setup" "fixture never reparented to ppid=1 — shape not the orphan shape, control invalid"
  run_scoped_reaper
  if kill -0 "${A1}" 2>/dev/null; then
    pass "A1: live owner's detached sweep (ppid=1, younger than every gate) survives the reaper"
  else
    fail "A1 live-survives" "reaper TERM'd a LIVE owner's sweep — the jammer failure mode. $(printf '%s' "${REAP_OUT}" | grep -E 'TERM pid=|sweeper:' | head -3 | tr '\n' ' ')"
  fi
  A_LINE="$(printf '%s\n' "${REAP_OUT}" | grep '^\[orphan-reaper\] sweeper:')"
  if [[ "${A_LINE}" == *"ppid=1: 1"* && "${A_LINE}" == *"owner_live: 1"* && "${A_LINE}" == *"owner_dead: 0"* && ( "${A_LINE}" == *"termed=0"* || "${A_LINE}" == *"would-kill=0"* ) ]]; then
    pass "A2: the spared sweep is VISIBLE (sweeper line: ppid=1: 1, owner_live: 1, owner_dead: 0, would-kill=0) — not a bare 0"
  else
    fail "A2 report boundary" "sweeper line='${A_LINE}'"
  fi
  # re-spawn + second pass: survival is not a one-shot accident
  spawn_fixture "${LIVE_OWNER}"
  sleep 0.8
  A2PID="$(fixture_pids leadv2-stale-sweeper.sh | grep -v "^${A1}\$" | head -1)"
  run_scoped_reaper
  _a_ok=1
  kill -0 "${A1}" 2>/dev/null || _a_ok=0
  { [[ -n "${A2PID}" ]] && kill -0 "${A2PID}" 2>/dev/null; } || _a_ok=0
  if (( _a_ok )); then
    pass "A3: both live-owner sweeps survive the second reaper pass (re-spawn included)"
  else
    fail "A3 second pass" "a live-owner sweep died on the second pass"
  fi
  kill_tree_9 "${A1}"
  [[ -n "${A2PID}" ]] && kill_tree_9 "${A2PID}"
fi

# ══ B: a dead owner's orphan is reaped BY THE DEATH SIGN, leaves-first ══════
rm -f "${TMP_ROOT}"/pids/*.pid
control_B_once() {  # rc=0 full proof; prints the reason on partial/incomplete
  local attempt="$1" sw cl gc out idx_sw idx_cl idx_gc line
  spawn_fixture "${DEAD_OWNER}"
  sleep 0.8
  sw="$(fixture_pids leadv2-stale-sweeper.sh | head -1)"
  cl="$(cat "${TMP_ROOT}/pids/cleanup.pid" 2>/dev/null || true)"
  gc="$(cat "${TMP_ROOT}/pids/grandchild.pid" 2>/dev/null || true)"
  if [[ -z "${sw}" || -z "${cl}" || -z "${gc}" ]]; then
    printf 'B setup incomplete (sw=%s cl=%s gc=%s)\n' "${sw:-none}" "${cl:-none}" "${gc:-none}"
    return 1
  fi
  wait_orphaned "${sw}" || { printf 'B fixture never reparented\n'; return 1; }
  run_scoped_reaper
  out="${REAP_OUT}"
  # kill proof: subject gone, chain gone, zero residue — by COUNT, not rc
  if kill -0 "${sw}" 2>/dev/null; then
    printf 'B subject SURVIVED a provably dead owner (age gates: %s/%ss, fixture age <2s)\n' "${LEADV2_REAPER_SWEEPER_STUCK_SEC:-3600}" "${LEADV2_REAPER_CLEANUP_STUCK_SEC:-1800}"
    kill_tree_9 "${sw}"
    return 1
  fi
  kill -0 "${cl}" 2>/dev/null && { printf 'B cleanup child survived the subject\n'; kill_tree_9 "${cl}"; return 1; }
  kill -0 "${gc}" 2>/dev/null && { printf 'B grandchild survived the chain\n'; kill_tree_9 "${gc}"; return 1; }
  local residue
  residue="$(fixture_pids leadv2-stale-sweeper.sh; fixture_pids leadv2-worktree-cleanup.sh)"
  if [[ -n "${residue}" ]]; then
    printf 'B residue under the suite scope: %s\n' "$(printf '%s' "${residue}" | tr '\n' ' ')"
    return 1
  fi
  pass "B1: dead owner's orphan (ppid=1, <2s old, under every age gate) is reaped; chain and residue: zero"
  # branch proof: OUR reaper did it, via the death-sign branch
  line="$(printf '%s\n' "${out}" | grep "TERM pid=${sw} " | head -1)"
  if [[ -z "${line}" ]]; then
    printf 'B NOTE: subject is gone but our pass logged no TERM (a concurrent SessionStart reaper won the race) — order unproven on attempt %s\n' "${attempt}"
    return 1
  fi
  if [[ "${line}" != *"under the "*" age gate"* ]]; then
    printf 'B TERM line lacks the death-sign marker: %s\n' "${line}"
    return 1
  fi
  pass "B2: the kill came from the DEATH-SIGN branch ('${line#\[orphan-reaper\] }')"
  # order proof: grandchild TERMmed before child before subject
  idx_gc="$(printf '%s\n' "${out}" | grep -n "TERM pid=${gc} " | head -1 | cut -d: -f1)"
  idx_cl="$(printf '%s\n' "${out}" | grep -n "TERM pid=${cl} " | head -1 | cut -d: -f1)"
  idx_sw="$(printf '%s\n' "${out}" | grep -n "TERM pid=${sw} " | head -1 | cut -d: -f1)"
  if [[ -n "${idx_gc}" && -n "${idx_cl}" && -n "${idx_sw}" ]] \
     && (( idx_gc < idx_cl && idx_cl < idx_sw )); then
    pass "B3: leaves-first order proven (grandchild TERM #${idx_gc} < cleanup #${idx_cl} < sweeper #${idx_sw})"
    return 0
  fi
  printf 'B order not provable from our output (gc=%s cl=%s sw=%s)\n' "${idx_gc:-none}" "${idx_cl:-none}" "${idx_sw:-none}"
  return 1
}

B_OK=0
for _attempt in 1 2; do
  if control_B_once "${_attempt}"; then B_OK=1; break; fi
  if (( _attempt == 1 )); then
    echo "B: retrying once (concurrent reaper race is the expected cause)"
  fi
done
if (( B_OK == 0 )); then
  fail "B dead-owner reap" "could not prove death-sign reap + leaf-first order in 2 attempts (see notes above)"
fi

# ══ §4: negative control — invert the death sign INSIDE the function ═══════
# The sed target '="$owner" == dead*' exists exactly once, inside
# reap_stuck_by_age's kill-decision body — the mutation cannot land at top
# level. Under the mutant, control A's subject (owner LIVE) gets TERMmed —
# the suite's A1 assertion goes red — proving this suite actually exercises
# the death-sign discrimination rather than just "reaper runs".
MUT="${TMP_ROOT}/mutated-reaper.sh"
sed 's/"\$owner" == dead\*/"\$owner" != dead*/' "${REAPER}" > "${MUT}"
if diff -q "${REAPER}" "${MUT}" >/dev/null 2>&1; then
  fail "S4 mutation" "sed produced a byte-identical file — mutation never applied, control proves nothing"
else
  spawn_fixture "${LIVE_OWNER}"
  sleep 0.8
  M_PID="$(fixture_pids leadv2-stale-sweeper.sh | head -1)"
  M_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" \
           LEADV2_REAPER_PROJECTS_DIR="${TMP_ROOT}/projects-absent" \
           LEADV2_REAPER_SUBJECT_SCOPE="${TMP_ROOT}" \
           bash "${MUT}" 2>&1)"
  if [[ -n "${M_PID}" ]] && printf '%s\n' "${M_OUT}" | grep -q "TERM pid=${M_PID} "; then
    pass "S4: inverted death sign TERMs the LIVE owner's sweep — A1 goes red under mutation (control is live, kill-list branch exercised)"
    sleep 0.4
    kill -0 "${M_PID}" 2>/dev/null && kill_tree_9 "${M_PID}"
  else
    fail "S4 mutation" "mutant did not kill the live fixture — discrimination not exercised"
    [[ -n "${M_PID}" ]] && kill_tree_9 "${M_PID}"
  fi
fi

kill -9 "${LIVE_OWNER}" 2>/dev/null || true

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-reaper-sweeper-subject.sh"
  exit 0
else
  echo "SOME FAILED: test-reaper-sweeper-subject.sh"
  exit 1
fi
