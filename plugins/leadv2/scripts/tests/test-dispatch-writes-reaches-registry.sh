#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code.sh leadv2-active-registry.sh
# DISPATCH-HONESTY-01 §2: use the real registration function against a scratch
# state root and exercise the dispatcher's real writes bridge/read-back proof.
set -u

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-honesty-registry.XXXXXX")"
trap 'rm -rf "${ROOT}"' EXIT
DISPATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-dispatch-code.sh"
REGISTRY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-active-registry.sh"
MUTATED="${ROOT}/dispatch-mutated.sh"
mkdir -p "${ROOT}/state"

run_register_case() {
  local script="$1" task="$2" writes="$3"
  set +e
  RUN_OUT="$(cd "${ROOT}" && \
    PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_STATE_ROOT="${ROOT}/state" LEADV2_DISPATCH_SOURCE_ONLY=1 \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
    bash -c 'source "$1"; source "$2"; _dispatch_register_writes_row "$3" Standard "$4" main "$5" - >/dev/null; _dispatch_registry_writes_proof "$3" "$5"; rc=$?; printf "proof=%s\\n" "$DISPATCH_REGISTRY_WRITES_PROOF"; exit "$rc"' _ "${script}" "${REGISTRY}" "${task}" "${ROOT}" "${writes}" 2>&1)"
  RUN_RC=$?
  set -u
}

EXPECTED='plugins/leadv2/scripts/leadv2-merge-safety-gate.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh'
run_register_case "${DISPATCH}" DISPATCH-WRITES-POSITIVE "${EXPECTED}"
ACTIVE="${ROOT}/state/active.yaml"
if [[ ${RUN_RC} -eq 0 ]] \
  && grep -q 'task_id: DISPATCH-WRITES-POSITIVE' "${ACTIVE}" \
  && grep -q 'writes: plugins/leadv2/scripts/leadv2-merge-safety-gate.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh' "${ACTIVE}"; then
  printf '[ok] declared --writes reaches the real scratch active.yaml registry row\n'
else
  printf '[FAIL] real registration did not retain writes rc=%s\n%s\n' "${RUN_RC}" "${RUN_OUT}"
  [[ -f "${ACTIVE}" ]] && sed -n '1,140p' "${ACTIVE}"
  exit 1
fi

# Negative control: mutate the writes argument INSIDE the bridge function. The
# real registry still registers the row, but the proof must catch the lost CSV;
# a text-only top-level mutation would not exercise this path.
python3 -c 'import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text()
old="    \"${task_id}\" \"${cls}\" \"${worktree}\" \"${branch}\" \"\" \"\" \"\" \"${writes}\" \"${reason}\""
assert old in s
p2=pathlib.Path(sys.argv[2]); p2.write_text(s.replace(old, old.replace("\"${writes}\"", "\"\""), 1)); p2.chmod(0o755)' "${DISPATCH}" "${MUTATED}"
rm -f "${ACTIVE}" "${ROOT}/state/active.yaml.lock"
run_register_case "${MUTATED}" DISPATCH-WRITES-NEGATIVE "${EXPECTED}"
if [[ ${RUN_RC} -ne 0 ]] \
  && printf '%s' "${RUN_OUT}" | grep -q 'proof=present=1.*writes=<missing>'; then
  printf '[red-control §2 raw]\n%s\n' "${RUN_OUT}"
  printf '[ok] negative control: losing --writes in the bridge is caught by registry read-back\n'
else
  printf '[FAIL] negative control did not go red rc=%s\n%s\n' "${RUN_RC}" "${RUN_OUT}"
  exit 1
fi

printf '=== all checks passed ===\n'
