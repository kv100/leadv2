#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code.sh leadv2-active-registry.sh
# DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-01 guard.
#
# Claim 1 (writer, concurrency): N concurrent dispatch registrations through the
#   real bridge `_dispatch_register_writes_row`, each with a DISTINCT --writes CSV,
#   must all read back their OWN set from the scratch active.yaml. Negative
#   control: the same harness with the bridge mutated INSIDE the function body
#   (drops "${writes}") must lose rows -- proves the harness can fail.
# Claim 2 (reader, untouched): one row with NO write set + a live worker pid +
#   a fresh pending window must make admission refuse any other registration
#   with rc=5 reason=pending_resolution (leadv2-active-registry.sh :564).
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
REGISTRY="${SCRIPTS_DIR}/leadv2-active-registry.sh"
MUTATED="${TESTS_DIR}/.writes-conc-mutated.$$.sh"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/writes-conc.XXXXXX")"
trap 'rm -rf "${ROOT}" "${MUTATED}"' EXIT
mkdir -p "${ROOT}/state"
N=6

# One concurrent registration arm through the real bridge + proof.
# usage: run_arm <dispatch-script> <task-id> <writes-csv> <outfile>
run_arm() {
  local script="$1" task="$2" writes="$3" outfile="$4"
  (
    cd "${ROOT}" && \
    PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_STATE_ROOT="${ROOT}/state" LEADV2_DISPATCH_SOURCE_ONLY=1 \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
    bash -c 'source "$1"; source "$2"
      _dispatch_register_writes_row "$3" Standard "$4" main "$5" - ; rc=$?
      _dispatch_registry_writes_proof "$3" "$5" ; proof_rc=$?
      printf "arm_rc=%s proof_rc=%s %s\n" "$rc" "$proof_rc" "${DISPATCH_REGISTRY_WRITES_PROOF:-proof=absent}"
      exit $(( rc != 0 ? rc : proof_rc ))' \
      _ "${script}" "${REGISTRY}" "${task}" "${ROOT}" "${writes}" \
    >"${outfile}" 2>&1
  ) &
}

# Central read-back: task_id -> writes for every conc-writes-* row.
readback() {
  python3 - "${ROOT}/state/active.yaml" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PYYAML-MISSING"); raise SystemExit(3)
try:
    doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except FileNotFoundError:
    print("REGISTRY-MISSING"); raise SystemExit(3)
rows = {r.get("task_id"): r.get("writes")
        for r in (doc.get("sessions") or [])
        if str(r.get("task_id", "")).startswith("conc-writes-")}
for t in sorted(rows):
    print(f"{t}\t{rows.get(t)!r}")
PY
}

# ── Claim 1: concurrent distinct write sets all persist ─────────────────────
pids=()
for i in $(seq 1 "${N}"); do
  run_arm "${DISPATCH}" "conc-writes-${i}" "src${i}.py" "${ROOT}/arm-${i}.log"
  pids+=($!)
done
for p in "${pids[@]}"; do wait "${p}" || true; done

KEPT=0; OWN=0
while IFS="$(printf '\t')" read -r tid writes_repr; do
  [[ -n "${tid:-}" ]] || continue
  KEPT=$((KEPT + 1))
  i="${tid#conc-writes-}"
  case "${writes_repr}" in
    "'src${i}.py'") OWN=$((OWN + 1)) ;;
  esac
done < <(readback)

if [[ "${KEPT}" -eq "${N}" && "${OWN}" -eq "${N}" ]] \
  && grep -q "arm_rc=0 proof_rc=0 .*present=1" "${ROOT}"/arm-*.log; then
  printf '[ok] claim 1: %s concurrent bridge registrations all read back their OWN writes\n' "${N}"
else
  printf '[FAIL] claim 1: kept=%s/%s own_set=%s/%s\n' "${KEPT}" "${N}" "${OWN}" "${N}"
  readback; grep -H . "${ROOT}"/arm-*.log | head -30
  exit 1
fi

# ── Claim 1b (fix-specific): a caller-pinned LEADV2_PROJECT_ROOT wins over a
# divergent ambient PROJECT_ROOT at the bridge. Ambient PROJECT_ROOT points at a
# REAL repo decoy (has a remote, so the state-path sandbox guard would ABORT a
# registration threaded onto it) -- exactly the ambient-root churn a staggered
# fleet produces. The bridge must thread the pin, not the ambient value.
DECOY="${ROOT}/decoy-real-repo"
git -C "${ROOT}" init -q "${DECOY}" 2>/dev/null || git init -q "${DECOY}"
git -C "${DECOY}" remote add origin "${ROOT}/decoy-remote.git" 2>/dev/null || true
PIN_OUT="$(cd "${ROOT}" && \
  PROJECT_ROOT="${DECOY}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_STATE_ROOT="${ROOT}/state" LEADV2_DISPATCH_SOURCE_ONLY=1 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
  bash -c 'source "$1"; source "$2"
    _dispatch_register_writes_row "conc-writes-pin" Standard "'"${ROOT}"'" main "srcpin.py" - ; rc=$?
    _dispatch_registry_writes_proof "conc-writes-pin" "srcpin.py" ; proof_rc=$?
    printf "arm_rc=%s proof_rc=%s %s\n" "$rc" "$proof_rc" "${DISPATCH_REGISTRY_WRITES_PROOF:-proof=absent}"
    exit $(( rc != 0 ? rc : proof_rc ))' \
    _ "${DISPATCH}" "${REGISTRY}" 2>&1)"
PIN_RC=$?
if [[ "${PIN_RC}" -eq 0 ]] && printf '%s' "${PIN_OUT}" | grep -q "arm_rc=0 proof_rc=0 .*present=1"; then
  printf '[ok] claim 1b: caller-pinned LEADV2_PROJECT_ROOT honored over divergent ambient PROJECT_ROOT\n'
else
  printf '[FAIL] claim 1b: pinned root not honored at the bridge rc=%s\n%s\n' "${PIN_RC}" "${PIN_OUT}"
  exit 1
fi

# ── Claim 1 negative control: mutate the bridge INSIDE the function body ────
# The mutation target must be present before the control runs -- a control
# that cannot fail proves nothing.
python3 - "${DISPATCH}" "${MUTATED}" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
s = src.read_text()
old = '    "${task_id}" "${cls}" "${worktree}" "${branch}" "" "" "" "${writes}" "${reason}"'
assert old in s, "mutation target (bridge register call) not found in dispatch writer"
mutated = s.replace(old, old.replace('"${writes}"', '""'), 1)
assert mutated != s
dst.write_text(mutated)
dst.chmod(0o755)
PY
rm -f "${ROOT}/state/active.yaml" "${ROOT}/state/active.yaml.lock"

pids=()
for i in $(seq 1 "${N}"); do
  run_arm "${MUTATED}" "conc-writes-${i}" "src${i}.py" "${ROOT}/mut-arm-${i}.log"
  pids+=($!)
done
for p in "${pids[@]}"; do wait "${p}" || true; done

MUT_LOST=0; MUT_TOTAL=0
while IFS="$(printf '\t')" read -r tid writes_repr; do
  [[ -n "${tid:-}" ]] || continue
  MUT_TOTAL=$((MUT_TOTAL + 1))
  case "${writes_repr}" in
    "None" | "''") MUT_LOST=$((MUT_LOST + 1)) ;;
  esac
done < <(readback)

if [[ "${MUT_TOTAL}" -ge 1 && "${MUT_LOST}" -ge 1 ]]; then
  printf '[ok] claim 1 red-control: mutated bridge lost %s/%s write sets (harness can fail)\n' "${MUT_LOST}" "${MUT_TOTAL}"
else
  printf '[FAIL] claim 1 red-control: mutation was NOT caught total=%s lost=%s\n' "${MUT_TOTAL}" "${MUT_LOST}"
  readback
  exit 1
fi

# ── Claim 2: reader refusal intact -- unrecorded write set + live worker ────
rm -f "${ROOT}/state/active.yaml" "${ROOT}/state/active.yaml.lock"
REFUSE_OUT="$(
  cd "${ROOT}" && \
  PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_STATE_ROOT="${ROOT}/state" \
  LEADV2_WRITESET_PENDING_WINDOW_SEC="900" LEADV2_WRITESET_ENFORCE="block" \
  bash -c 'source "$1"
    sleep 60 & WORKER_PID=$!
    leadv2_active_register "pending-loser-1" Standard "'"$ROOT"'" main false "" "" "-" "-" >/dev/null 2>&1 || { echo "loser-register-failed"; exit 9; }
    leadv2_active_set_worker_pid "pending-loser-1" "${WORKER_PID}" "$(_lv2_pid_birth "${WORKER_PID}")" worker >/dev/null 2>&1 || { echo "setpid-failed"; exit 9; }
    leadv2_active_register "pending-claimer-1" Standard "'"$ROOT"'" main false "" "" "src_claim.py" "-" >/dev/null
    rc=$?
    kill "${WORKER_PID}" 2>/dev/null
    printf "claimer_rc=%s\n" "${rc}"
    exit "${rc}"' _ "${REGISTRY}" 2>&1
)"
REFUSE_RC=$?
if [[ "${REFUSE_RC}" -eq 5 ]] \
  && printf '%s' "${REFUSE_OUT}" | grep -q "claimer_rc=5" \
  && printf '%s' "${REFUSE_OUT}" | grep -q "reason=pending_resolution"; then
  printf '[ok] claim 2: unrecorded write set + live worker still refused rc=5 reason=pending_resolution\n'
else
  printf '[FAIL] claim 2: admission did not refuse pending_resolution rc=%s\n%s\n' "${REFUSE_RC}" "${REFUSE_OUT}"
  exit 1
fi

printf '=== all checks passed ===\n'
