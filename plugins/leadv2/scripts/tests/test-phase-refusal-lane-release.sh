#!/usr/bin/env bash
# PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01 — a dispatcher that registers its
# lane in active.yaml and THEN hits the phase gate must release the row on
# refusal. Live evidence (2026-09-03, CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01):
# two rows for one task_id made the release python fail closed with a silent
# exit 2 (`active_lane_release_skipped reason=not_owner_row_intact`), so the
# lane stayed registered forever and every later dispatch saw lane_is_live.
#
# This suite proves the fixed `_release_registered_lane` behaviour directly:
# the function is extracted from leadv2-dispatch-code.sh (real code, no copy)
# and run in a harness with a stubbed `emit` journal, against a fixture
# active.yaml + flock lockfile. Every changed requirement carries its own
# in-function mutation control (baseline_rc vs mutated_rc pairs below):
#   M1 (req 1) release-on-refusal per-row removal predicate
#   M2 (req 2) duplicate-rows journal line
#   M3 (req 3) process-kind guard (a mislabelled row whose PID is a live
#              worker process must never be released)
#   M4 (req 3) registry proc_kind stamp at register time
# Acceptance #3: a row with pid_role=worker and a live process survives the
# release path (T4).

set -uo pipefail
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DC="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
REGISTRY="${PLUGIN_SCRIPTS}/leadv2-active-registry.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

SBX="$(mktemp -d /tmp/leadv2-prlr-XXXXXX)"
trap 'rm -rf "${SBX}"' EXIT

DEAD_PID=""
for cand in 99998 99997 99996 99995; do
  if ! kill -0 "${cand}" 2>/dev/null; then DEAD_PID="${cand}"; break; fi
done
[[ -n "${DEAD_PID}" ]] || { echo "FATAL: no dead pid found"; exit 1; }

# Fake processes: a launcher NAMED claude whose argv carries `-p` (worker)
# or `--dangerously-skip-permissions` (interactive lead), so `ps -o args=`
# classifies them without spawning real claude. The child `sleep` is killed
# via its recorded pid at the end of the run.
cat > "${SBX}/claude" <<'EOF'
#!/bin/bash
sleep 30 &
echo $! > "${PRLR_CHILD:-/tmp/prlr-child.$$}"
wait $!
EOF
chmod +x "${SBX}/claude"
PRLR_CHILD="${SBX}/child.w" "${SBX}/claude" -p 30 & FAKE_WORKER_PID=$!
PRLR_CHILD="${SBX}/child.l" "${SBX}/claude" --dangerously-skip-permissions 30 & FAKE_LEAD_PID=$!
sleep 0.5
kill -0 "${FAKE_WORKER_PID}" 2>/dev/null || { echo "FATAL: fake worker died"; exit 1; }
# sanity: the kind classifier reads the expected argv kinds
ps -p "${FAKE_WORKER_PID}" -o args= | grep -q ' -p ' || { echo "FATAL: worker argv unexpected: $(ps -p "${FAKE_WORKER_PID}" -o args=)"; exit 1; }
ps -p "${FAKE_LEAD_PID}" -o args= | grep -q -- --dangerously-skip-permissions || { echo "FATAL: lead argv unexpected"; exit 1; }

extract_release_fn() { # <dispatch-code-copy> <outfile>
  awk '/^_release_registered_lane\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$1" > "$2"
}

# run_release <dispatch-copy> <yaml> <session> <pid> <decisions-file> -> rc
run_release() {
  local copy="$1" yml="$2" sess="$3" pid="$4" dec="$5"
  local fnf="${SBX}/fn.$.$.sh"
  extract_release_fn "${copy}" "${fnf}"
  local lock="${yml}.lock"; : > "${lock}"
  : > "${dec}"
  HARNESS_YAML="${yml}" HARNESS_LOCK="${lock}" HARNESS_DEC="${dec}" \
  HARNESS_SESSION="${sess}" HARNESS_PID="${pid}" \
  bash -c '
    emit() { printf "%s\n" "$*" >> "${HARNESS_DEC}"; }
    _leadv2_yaml_file()      { printf "%s\n" "${HARNESS_YAML}"; }
    _leadv2_yaml_lockfile()  { printf "%s\n" "${HARNESS_LOCK}"; }
    PROJECT_ROOT="'"${SBX}"'"
    DISPATCH_SLOT_REG_ID="reg-x"
    DISPATCH_SLOT_SESSION="${HARNESS_SESSION}"
    DISPATCH_SLOT_PID="${HARNESS_PID}"
    DISPATCH_SLOT_SIG8="prlr0001"
    source "'"${fnf}"'"
    _release_registered_lane "task-prlr0001" "prlr0001" "unit_test" >/dev/null 2>&1
  '
}

# journal_code <decisions-file> -> canonical release rc mirrored from the
# journal decision line (_release_registered_lane returns 0 by design; the
# release outcome is observable only through the journal line it emits).
journal_code() {
  if    grep -q "active_lane_released " "$1"; then echo 0
  elif  grep -q "reason=not_owner_row_intact" "$1"; then echo 2
  elif  grep -q "reason=duplicate_rows_unresolvable" "$1"; then echo 4
  elif  grep -q "active_lane_release_failed" "$1"; then echo 3
  else echo 1
  fi
}

rows_of_task() { # <yaml> <task> -> count
  python3 - "$1" "$2" <<'EOF'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
print(sum(1 for s in (data.get("sessions") or []) if s.get("task_id") == sys.argv[2]))
EOF
}

yaml_row_field() { # <yaml> <task> <session_id> <field>
  python3 - "$1" "$2" "$3" "$4" <<'EOF'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
for s in (data.get("sessions") or []):
    if s.get("task_id") == sys.argv[2] and s.get("session_id") == sys.argv[3]:
        print(s.get(sys.argv[4], ""))
        break
EOF
}

mk_yaml() { # <yaml> <session>:<pid>:<role> ...
  local out="$1"; shift
  {
    printf 'sessions:\n'
    for row in "$@"; do
      IFS=: read -r sid pid role pad <<< "${row}"
      printf '  - session_id: "%s"\n    task_id: "task-prlr0001"\n    pid: %s\n    pid_role: "%s"\n    phase: "spawning"\n' \
        "${sid}" "${pid}" "${role}"
    done
  } > "${out}"
}

HARNESS_PID=$$   # the harness bash process: alive, kind=other (not a worker)
S="s-20260903T000000Z-${DEAD_PID}-111"

# ── T1 (req 1): our row + a stale duplicate → BOTH released, rc 0 ───────────
Y="${SBX}/t1.yaml"; D="${SBX}/t1.dec"
mk_yaml "${Y}" "${S}:${HARNESS_PID}:lead_durable" "s-other-1:${DEAD_PID}:lead_durable"
run_release "${DC}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc=$?
[[ "${rc}" == "0" ]] && ok "T1 baseline_rc=0 (release succeeds despite duplicate row)" \
                     || bad "T1 baseline_rc=${rc} expected 0"
[[ "$(rows_of_task "${Y}" "task-prlr0001")" == "0" ]] && ok "T1 both rows released" \
                     || bad "T1 rows left: $(rows_of_task "${Y}" "task-prlr0001")"
grep -q "active_lane_duplicate_rows .*found=2" "${D}" && ok "T1 duplicate row count journaled (req 2)" \
                     || bad "T1 no active_lane_duplicate_rows line in journal"

# ── T2: single FOREIGN live row → fail closed, survives (R5 preserved) ──────
Y="${SBX}/t2.yaml"; D="${SBX}/t2.dec"
mk_yaml "${Y}" "s-foreign:${FAKE_LEAD_PID}:lead_durable"
run_release "${DC}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc=$(journal_code "${D}")
[[ "${rc}" == "2" ]] && ok "T2 foreign live row skipped rc=2" || bad "T2 rc=${rc} expected 2"
[[ "$(rows_of_task "${Y}" "task-prlr0001")" == "1" ]] && ok "T2 foreign row survives" \
                     || bad "T2 foreign row was deleted"

# ── T4 (req 3 / acceptance 3): worker-labelled live row survives ────────────
Y="${SBX}/t4.yaml"; D="${SBX}/t4.dec"
mk_yaml "${Y}" "s-worker:${FAKE_WORKER_PID}:worker" "s-stale:${DEAD_PID}:lead_durable"
run_release "${DC}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc=$?
[[ "$(rows_of_task "${Y}" "task-prlr0001")" == "1" ]] && ok "T4 live worker row survives release" \
                     || bad "T4 live worker row was released"
[[ "$(yaml_row_field "${Y}" "task-prlr0001" "s-worker" "session_id")" == "s-worker" ]] \
                     && ok "T4 surviving row is the worker row" || bad "T4 wrong row survived"
grep -q "live_worker_kept=1" "${D}" && ok "T4 journal names kept live worker" \
                     || bad "T4 no live_worker_kept in journal: $(cat "${D}")"

# ── T5 (req 3): MISLABELLED row whose pid is a live worker survives ─────────
Y="${SBX}/t5.yaml"; D="${SBX}/t5.dec"
mk_yaml "${Y}" "${S}:${FAKE_WORKER_PID}:lead_durable"
run_release "${DC}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc=$?
[[ "$(rows_of_task "${Y}" "task-prlr0001")" == "1" ]] && ok "T5 mislabelled live-worker row survives kind guard" \
                     || bad "T5 mislabelled live-worker row was released"

# ── Mutation controls ────────────────────────────────────────────────────────
mutate() { # <src> <dst> <old> <new>
  python3 - "$1" "$2" "$3" "$4" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src).read()
assert old in t, "mutation anchor not found: " + old[:60]
open(dst, "w").write(t.replace(old, new, 1))
EOF
}

# M1 (req 1): kill the per-row removal predicate (inside function body)
M1="${SBX}/dc.m1.sh"
mutate "${DC}" "${M1}" "        if ours or stale:" "        if False:  # MUTATED-M1"
Y="${SBX}/m1.yaml"; D="${SBX}/m1.dec"
mk_yaml "${Y}" "${S}:${HARNESS_PID}:lead_durable" "s-other-1:${DEAD_PID}:lead_durable"
run_release "${M1}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc=$(journal_code "${D}")
if [[ "${rc}" != "0" ]]; then
  ok "M1 mutated_rc=${rc} differs from baseline_rc=0 (release control bites)"
else
  bad "M1 mutation did NOT change rc (control useless)"
fi
grep -q "active_lane_release_skipped" "${D}" && ok "M1 red line present: $(grep active_lane_release "${D}" | head -1)" \
                     || bad "M1 no skip line"

# M2 (req 2): kill the duplicate-rows journal line (inside function body)
M2="${SBX}/dc.m2.sh"
mutate "${DC}" "${M2}" 'emit decision "active_lane_duplicate_rows' ': ; # MUTATED-M2 emit decision "active_lane_duplicate_rows'
Y="${SBX}/m2.yaml"; D="${SBX}/m2.dec"
mk_yaml "${Y}" "${S}:${HARNESS_PID}:lead_durable" "s-other-1:${DEAD_PID}:lead_durable"
run_release "${DC}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc_base=$?
run_release "${M2}" "${Y}" "${S}" "${HARNESS_PID}" "${D}"; rc_mut=$?
if [[ "${rc_base}" == "0" && "${rc_mut}" == "0" ]]; then
  # same rc, so the observable is the journal line itself
  if ! grep -q "active_lane_duplicate_rows" "${D}"; then
    ok "M2 mutated: duplicate journal line gone (baseline had it) — control bites"
  else
    bad "M2 mutation did not remove the journal line (control useless)"
  fi
else
  bad "M2 unexpected rc pair base=${rc_base} mut=${rc_mut}"
fi

# M3 (req 3): kill the process-kind guard (inside function body)
M3="${SBX}/dc.m3.sh"
mutate "${DC}" "${M3}" \
  'if _prlr_alive(rpid) and _prlr_kind(rpid) == "worker":' \
  'if False:  # MUTATED-M3'
Y="${SBX}/m3.yaml"; D="${SBX}/m3.dec"
mk_yaml "${Y}" "${S}:${FAKE_WORKER_PID}:lead_durable"
# the row is "ours" (matching session AND pid) -- only the process-KIND guard
# can tell the recorded pid is actually a live worker process.
run_release "${DC}" "${Y}" "${S}" "${FAKE_WORKER_PID}" "${D}"; rc_base=$(journal_code "${D}")
run_release "${M3}" "${Y}" "${S}" "${FAKE_WORKER_PID}" "${D}"; rc_mut=$(journal_code "${D}")
if [[ "${rc_base}" != "0" && "${rc_mut}" == "0" ]]; then
  ok "M3 baseline_rc=${rc_base} (kept) vs mutated_rc=0 (released live worker) — control bites"
else
  bad "M3 unexpected rc pair base=${rc_base} mut=${rc_mut}"
fi

# ── T6/M4 (req 3): registry stamps proc_kind at register time ───────────────
RT="${SBX}/regtarget"; mkdir -p "${RT}"
( cd "${RT}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
  && printf 'x\n' > f && git add f && git commit -qm s )
export LEADV2_STATE_ROOT="${SBX}/state"
export LEADV2_STATE_BASE="${SBX}/state"
register_once() { # <registry-copy> <task-id> <state-suffix> -> yaml path on stdout
  local copy="$1" tid="$2" suffix="$3"
  LEADV2_STATE_ROOT="${SBX}/state${suffix}" LEADV2_STATE_BASE="${SBX}/state${suffix}" \
  LEADV2_PROJECT_ROOT="${RT}" bash -c "
    source '$copy' >/dev/null 2>&1
    leadv2_active_register '$tid' 'standard' '${RT}' '' '' '' '' '-' >/dev/null 2>&1
    _leadv2_yaml_file
  "
}
ACT="$(register_once "${REGISTRY}" "task-prlr-reg" "")"
if [[ -n "${ACT}" && -f "${ACT}" ]]; then
  if python3 -c "
import sys, yaml
data = yaml.safe_load(open('${ACT}')) or {}
rows = [s for s in (data.get('sessions') or []) if s.get('task_id') == 'task-prlr-reg']
assert rows, 'no row registered'
assert rows[0].get('proc_kind') in ('interactive','worker','other','claude_other','unknown'), rows[0].get('proc_kind')
" 2>/dev/null; then
    ok "T6 registry stamps proc_kind on the registered row"
  else
    bad "T6 registered row missing/bad proc_kind"
  fi
else
  bad "T6 could not locate sandbox active.yaml (${ACT})"
fi

# M4: remove the proc_kind stamp (inside register dict body)
M4="${SBX}/reg.m4.sh"
mutate "${REGISTRY}" "${M4}" '                "proc_kind": _proc_kind(pid_int),
' ''
M4Y="$(register_once "${M4}" "task-prlr-m4" ".m4")"
M4_BASE="${ACT}"
if [[ -n "${M4Y}" && -f "${M4Y}" && -n "${M4_BASE}" ]]; then
  base_has="$(python3 -c "
import yaml
d = yaml.safe_load(open('${M4_BASE}')) or {}
print(any(s.get('task_id')=='task-prlr-reg' and s.get('proc_kind') for s in (d.get('sessions') or [])))
" 2>/dev/null)"
  mut_has="$(python3 -c "
import yaml
d = yaml.safe_load(open('${M4Y}')) or {}
print(any(s.get('task_id')=='task-prlr-m4' and s.get('proc_kind') for s in (d.get('sessions') or [])))
" 2>/dev/null)"
  if [[ "${base_has}" == "True" && "${mut_has}" == "False" ]]; then
    ok "M4 baseline stamps proc_kind=True vs mutated=False — control bites"
  else
    bad "M4 pair unexpected base=${base_has} mut=${mut_has}"
  fi
else
  bad "M4 could not build sandbox state (base=${M4_BASE} mut=${M4Y})"
fi

kill "${FAKE_WORKER_PID}" "${FAKE_LEAD_PID}" 2>/dev/null || true
kill "$(cat "${SBX}/child.w" 2>/dev/null)" "$(cat "${SBX}/child.l" 2>/dev/null)" 2>/dev/null || true

echo
echo "[TEST] PASS=${PASS} FAIL=${FAIL}"
[[ "${FAIL}" == "0" ]]
