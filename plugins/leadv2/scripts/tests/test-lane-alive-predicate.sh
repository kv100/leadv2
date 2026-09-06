#!/usr/bin/env bash
# tests/test-lane-alive-predicate.sh — LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01
# regression suite for the three-valued liveness predicate in
# lib/leadv2-lane-state.sh (proc_verdict/verdict/alive + the lead_alive op).
#
# Paired control, BOTH directions (a one-sided fix is a silencer that stops
# the reaper collecting real orphans):
#   GREEN side — a заведомо live process is NEVER declared dead, including
#     EPERM (process exists under another owner) and an empty/unobservable
#     birth on either side (register-time or check-time ps failure);
#   RED side — a genuinely dead process (ESRCH) and a pid-reuse mismatch
#     STAY dead, so worktrees keep getting reaped and unknown never becomes
#     a blanket "alive".
#
# The predicate has FOUR independent verdict sources, so the negative
# controls are four single-line mutants, each inserted INSIDE proc_verdict's
# body (never at top level), each expected to redden exactly its own case:
#   MUTANT-A  kill-classification reverted (EPERM/other-OSError -> dead)  -> c4 red
#   MUTANT-B  incomparability reverted (missing birth -> dead)            -> c2,c3,c7 red
#   MUTANT-C  ESRCH silenced (dead pid -> unknown)                        -> c5 red
#   MUTANT-D  mismatch silenced (pid reuse -> unknown)                    -> c6 red
# A fifth mutation anywhere else in the file cannot pass this matrix: every
# branch of proc_verdict is load-bearing for exactly one case.
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh
# run-all-triggers: leadv2-lane-state.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${SCRIPTS_DIR}/lib/leadv2-lane-state.sh"

PASS=0; FAIL=0; SKIP=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '[TEST] SKIP: %s\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-alive-pred.XXXXXX")"
SLEEP_PIDS=()
cleanup() { (( ${#SLEEP_PIDS[@]} )) && kill ${SLEEP_PIDS[@]} 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
REPO="$TMP/repo"; STATE_ROOT="$TMP/state"
mkdir -p "$REPO/.claude/worktrees" "$STATE_ROOT"
: > "$TMP/wt.txt"; : > "$TMP/ps.txt"; : > "$TMP/cwd.txt"; : > "$TMP/birth.txt"

new_sleeper() { sleep 300 </dev/null >/dev/null 2>&1 & echo $!; }
birth_of() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

write_row() { # <task> <pid> <pid_start_time> [lead_pid] [lead_pid_birth]
  python3 - "$STATE_ROOT/active.yaml" "$@" <<'PY'
import os, sys, yaml
path = sys.argv[1]; task, pid, birth = sys.argv[2:5]
lead_pid = sys.argv[5] if len(sys.argv) > 5 else ''
lead_birth = sys.argv[6] if len(sys.argv) > 6 else ''
os.makedirs(os.path.dirname(path), exist_ok=True)
data = yaml.safe_load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
rows = (data or {}).get('sessions') or []
rows[:] = [r for r in rows if r.get('task_id') != task]
row = {'task_id': task, 'session_id': 'lead', 'lead_session_id': 'lead',
       'worktree': '/tmp/nowhere-lane-alive-pred', 'phase': 'build',
       'pid': int(pid), 'pid_start_time': birth,
       'started_at': '2026-09-06T00:00:00Z', 'updated_at': '2026-09-06T00:00:00Z',
       'dead_at': None, 'recovered': False, 'lane_events': []}
if lead_pid: row.update(lead_pid=int(lead_pid), lead_pid_birth=lead_birth)
rows.append(row)
yaml.safe_dump({'meta': {}, 'sessions': rows}, open(path, 'w', encoding='utf-8'),
               default_flow_style=False, sort_keys=False)
PY
}

reset_registry() { : > "$STATE_ROOT/active.yaml"; }

op_rc() { # <lib> <op-call> -> rc of `bash -c "source lib; <op-call>"`
  local lib="$1" call="$2"
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$lib'; $call" >/dev/null 2>&1
  echo $?
}

alive_rc() { # <lib> <task>
  op_rc "$1" "lane_alive '$2'"
}

dead_at_is() { # <task> <expected: set|unset>
  python3 - "$STATE_ROOT/active.yaml" "$1" "$2" <<'PY'
import sys, yaml
rows = (yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}).get('sessions') or []
row = next((r for r in rows if r.get('task_id') == sys.argv[2]), None)
want_set = sys.argv[3] == 'set'
sys.exit(0 if row is not None and bool(row.get('dead_at')) == want_set else 1)
PY
}

reconcile() { # <lib>
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$1'; lane_reconcile" >/dev/null 2>&1
}

# --- GREEN side: live is never dead -----------------------------------------

c1_live_correct_birth() { local lib="${1:-$LIB}" P B
  reset_registry; P="$(new_sleeper)"; SLEEP_PIDS+=("$P"); B="$(birth_of "$P")"
  write_row c1 "$P" "$B"
  [[ "$(alive_rc "$lib" c1)" == 0 ]] || return 1
  reconcile "$lib"; dead_at_is c1 unset
}

c2_live_empty_recorded_birth() { local lib="${1:-$LIB}" P B
  reset_registry; P="$(new_sleeper)"; SLEEP_PIDS+=("$P"); B="$(birth_of "$P")"
  write_row c2 "$P" ""   # birth() failed ONCE at register time -> stamped '' forever
  [[ "$(alive_rc "$lib" c2)" == 0 ]] || return 1
  reconcile "$lib"; dead_at_is c2 unset
}

c3_live_empty_observed_birth() { local lib="${1:-$LIB}" P B
  reset_registry; P="$(new_sleeper)"; SLEEP_PIDS+=("$P"); B="$(birth_of "$P")"
  printf '%s\t\n' "$P" >> "$TMP/birth.txt"   # birth() observes '' at CHECK time
  write_row c3 "$P" "$B"
  [[ "$(alive_rc "$lib" c3)" == 0 ]] || return 1
  reconcile "$lib"; dead_at_is c3 unset
}

c4_live_eperm() { local lib="${1:-$LIB}" R RB
  R="$(ps -axo pid=,user= | awk '$2=="root" && $1>1 {print $1; exit}')"
  [[ -n "$R" ]] || return 2   # no root-owned pid -> SKIP
  kill -0 "$R" 2>/dev/null && return 2   # we MAY signal it (running as root) -> EPERM not exercisable
  RB="$(birth_of "$R")"
  reset_registry; write_row c4 "$R" "$RB"
  [[ "$(alive_rc "$lib" c4)" == 0 ]] || return 1
  reconcile "$lib"; dead_at_is c4 unset
}

c5_dead_stays_dead() { local lib="${1:-$LIB}" DP DB
  reset_registry; DP="$(new_sleeper)"; DB="$(birth_of "$DP")"
  kill "$DP" 2>/dev/null; wait "$DP" 2>/dev/null
  write_row c5 "$DP" "$DB"
  [[ "$(alive_rc "$lib" c5)" == 1 ]] || return 1
  reconcile "$lib"; dead_at_is c5 set
}

c6_mismatch_stays_dead() { local lib="${1:-$LIB}" P
  reset_registry; P="$(new_sleeper)"; SLEEP_PIDS+=("$P")
  write_row c6 "$P" "Mon Jan  1 00:00:00 1999"   # live pid, WRONG birth = pid reuse
  [[ "$(alive_rc "$lib" c6)" == 1 ]] || return 1
  reconcile "$lib"; dead_at_is c6 set
}

c7_lead_alive_unknown_degrades_live() { local lib="${1:-$LIB}" P B
  reset_registry; P="$(new_sleeper)"; SLEEP_PIDS+=("$P"); B="$(birth_of "$P")"
  write_row c7 "$P" "$B" "$P" ""   # live lead pid, EMPTY lead_pid_birth
  LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE_ROOT" \
  LEADV2_LANE_STATE_TEST_WORKTREES_FILE="$TMP/wt.txt" \
  LEADV2_LANE_STATE_TEST_PS_FILE="$TMP/ps.txt" \
  LEADV2_LANE_STATE_TEST_BIRTH_FILE="$TMP/birth.txt" \
  LEADV2_LANE_STATE_TEST_CWD_FILE="$TMP/cwd.txt" \
    bash -c "source '$lib'; lane_lead_alive 'lead'" >/dev/null 2>&1
  [[ $? == 0 ]]
}

run_case() { # <case-fn> <label>
  local rc=0; "$1" || rc=$?
  if [[ $rc == 0 ]]; then pass "$2"
  elif [[ $rc == 2 ]]; then skip "$2 (no root-owned pid on this machine — EPERM case not exercisable here)"
  else fail "$2"; fi
}

run_case c1_live_correct_birth "c1: live pid + correct birth -> alive, reconcile leaves it live"
run_case c2_live_empty_recorded_birth "c2: live pid + EMPTY recorded birth -> alive (unknown never kills), no dead_at"
run_case c3_live_empty_observed_birth "c3: live pid + EMPTY observed birth -> alive (unknown never kills), no dead_at"
run_case c4_live_eperm "c4: live pid under EPERM (root-owned) -> alive, no dead_at"
run_case c5_dead_stays_dead "c5: genuinely dead pid (ESRCH) -> dead, reconcile stamps dead_at"
run_case c6_mismatch_stays_dead "c6: live pid + mismatched birth (pid reuse) -> dead, reconcile stamps dead_at"
run_case c7_lead_alive_unknown_degrades_live "c7: lead_alive with empty lead_pid_birth on a live pid -> rc0 (unknown degrades to live)"

# --- RED side: four single-line mutants inside proc_verdict's body ----------

build_mutant() { # <name> <old-line> <new-line> -> echoes mutant lib path
  local name="$1" old="$2" new="$3" dir="$TMP/mut-$name"
  mkdir -p "$dir/lib"
  cp "${SCRIPTS_DIR}/leadv2-state-path.sh" "$dir/" 2>/dev/null || true
  cp "$LIB" "$dir/lib/leadv2-lane-state.sh"
  python3 - "$dir/lib/leadv2-lane-state.sh" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding='utf-8').read()
assert s.count(old) == 1, f"mutant anchor not unique ({s.count(old)} hits): {old!r}"
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
PY
  [[ $? == 0 ]] || { echo ""; return; }
  echo "$dir/lib/leadv2-lane-state.sh"
}

expect_mutant_red() { # <mutant-name> <case-fn> <case-label> — case must FAIL under mutant, PASS under shipped lib
  local name="$1" case_fn="$2" label="$3" mut rc=0
  mut="$(build_mutant "$name" "$4" "$5")"
  if [[ -z "$mut" ]]; then fail "mutant $name: anchor not found — mutant never applied (control invalid)"; return; fi
  "$case_fn" "$mut" || rc=$?   # same case, MUTANT lib: rc!=0 (and !=2) is the REQUIRED red
  if [[ $rc == 2 ]]; then skip "mutant $name: $label not exercisable on this machine (case SKIPs) — control neither claimed nor silently passed"
  elif [[ $rc != 0 ]]; then pass "mutant $name RED: $label goes red under it (control live)"
  else fail "mutant $name still green: $label — negative control proves nothing"; fi
}

KILL_OLD="    except ProcessLookupError: return 'dead'   # ESRCH -- the only proof of death
    except PermissionError: pass               # EPERM -- process exists, other owner
    except OSError: return 'unknown'           # unclassifiable -- do not kill on it"
KILL_NEW="    except OSError: return 'dead'   # MUTANT-A: kill-classification reverted (EPERM -> dead)"
BIRTH_OLD="    if not recorded or not observed: return 'unknown'  # incomparable, never a kill"
BIRTH_NEW="    if not recorded or not observed: return 'dead'  # MUTANT-B: incomparability reverted to death"
ESRCH_OLD="    except ProcessLookupError: return 'dead'   # ESRCH -- the only proof of death"
ESRCH_NEW="    except ProcessLookupError: return 'unknown'   # MUTANT-C: ESRCH silenced"
MISM_OLD="    return 'live' if recorded == observed else 'dead'  # mismatch = pid reuse"
MISM_NEW="    return 'live' if recorded == observed else 'unknown'  # MUTANT-D: mismatch silenced"

expect_mutant_red A c4_live_eperm "EPERM-live case" "$KILL_OLD" "$KILL_NEW"
expect_mutant_red B c2_live_empty_recorded_birth "empty-recorded-birth case" "$BIRTH_OLD" "$BIRTH_NEW"
expect_mutant_red B c3_live_empty_observed_birth "empty-observed-birth case" "$BIRTH_OLD" "$BIRTH_NEW"
expect_mutant_red B c7_lead_alive_unknown_degrades_live "lead_alive unknown case" "$BIRTH_OLD" "$BIRTH_NEW"
expect_mutant_red C c5_dead_stays_dead "ESRCH-dead case" "$ESRCH_OLD" "$ESRCH_NEW"
expect_mutant_red D c6_mismatch_stays_dead "mismatch-dead case" "$MISM_OLD" "$MISM_NEW"

# --- summary -----------------------------------------------------------------
printf '\n[LANE-ALIVE-PREDICATE] pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
if (( FAIL > 0 )); then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
