#!/usr/bin/env bash
# tests/ci-gate.sh — CI-RUNS-THE-SUITES-01.
#
# Runs tests/run-all.sh and reconciles its failures against
# tests/known-red-suites.txt: a failure already on the allow-list is
# reported but does not fail the job; any OTHER failure fails the job. This
# lets CI be green from birth on a repo that already has known-red suites,
# without hiding a newly-broken suite behind the pre-existing reds.
#
# usage: tests/ci-gate.sh [changed|all]
# exit 0: every failing suite (if any) is on the allow-list
# exit 1: at least one failing suite is NOT on the allow-list
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
SCOPE="${1:-changed}"
ALLOWLIST="${ROOT}/tests/known-red-suites.txt"
CORE_OFFLINE_REL="plugins/leadv2/scripts/tests/run-core-offline.sh"

LOG="$(mktemp "${TMPDIR:-/tmp}/ci-gate-run-all.XXXXXX")"
trap 'rm -f "${LOG}"' EXIT

bash "${ROOT}/tests/run-all.sh" --scope "${SCOPE}" >"${LOG}" 2>&1
RUN_RC=$?

# Echo the full run-all.sh transcript to the job log — the raw [RUN]/[PASS]/
# [FAIL] trace stays available even though the pass/fail verdict below is
# allow-list-aware, not the raw exit code.
cat "${LOG}"

if [[ ${RUN_RC} -eq 2 ]]; then
  echo "ci-gate: FATAL tests/run-all.sh rejected its own arguments (exit 2) — this is a bug in the workflow, not a suite failure" >&2
  exit 1
fi

is_allowlisted() {
  local id="$1"
  [[ -f "${ALLOWLIST}" ]] || return 1
  grep -qxF "${id}" <(grep -vE '^[[:space:]]*(#|$)' "${ALLOWLIST}" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
}

declare -a UNEXPECTED=()
declare -a KNOWN=()

# Suites failing inside the curated run-core-offline.sh set are named by
# their [CORE-OFFLINE] FAILED: label, not a path — key the allow-list the
# same way.
while IFS= read -r name; do
  [[ -n "${name}" ]] || continue
  id="core:${name}"
  if is_allowlisted "${id}"; then
    KNOWN+=("${id}")
  else
    UNEXPECTED+=("${id}")
  fi
done < <(grep -E '^\[CORE-OFFLINE\] FAILED: ' "${LOG}" | sed -E 's/^\[CORE-OFFLINE\] FAILED: //')

# Top-level tests/run-all.sh suite failures (its own [FAIL] lines), except
# the run-core-offline.sh wrapper itself — that failure is only the sum of
# the [CORE-OFFLINE] FAILED: lines already handled above, and would
# otherwise show up as an extra, unresolvable "path:" failure on every run
# that has ANY allow-listed known-red suite.
while IFS= read -r p; do
  [[ -n "${p}" ]] || continue
  rel="${p#"${ROOT}/"}"
  [[ "${rel}" == "${CORE_OFFLINE_REL}" ]] && continue
  id="path:${rel}"
  if is_allowlisted "${id}"; then
    KNOWN+=("${id}")
  else
    UNEXPECTED+=("${id}")
  fi
done < <(grep -E '^\[FAIL\] ' "${LOG}" | sed -E 's/^\[FAIL\] //')

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
write_summary() {
  if [[ -n "${SUMMARY_FILE}" ]]; then
    printf '%s\n' "$1" >>"${SUMMARY_FILE}"
  fi
}

write_summary "## tests/run-all.sh --scope ${SCOPE}"
write_summary ""
if [[ ${#UNEXPECTED[@]} -eq 0 && ${#KNOWN[@]} -eq 0 ]]; then
  write_summary "All selected suites passed."
fi
if [[ ${#UNEXPECTED[@]} -gt 0 ]]; then
  write_summary "### Failing suites (BLOCKING — not on the known-red allow-list)"
  for id in "${UNEXPECTED[@]}"; do
    write_summary "- \`${id}\`"
  done
  write_summary ""
fi
if [[ ${#KNOWN[@]} -gt 0 ]]; then
  write_summary "### Failing suites (known-red, allow-listed — see tests/known-red-suites.txt / FIFTEEN-RED-SUITES-01)"
  for id in "${KNOWN[@]}"; do
    write_summary "- \`${id}\`"
  done
  write_summary ""
fi

echo ""
echo "ci-gate: scope=${SCOPE} run_all_rc=${RUN_RC} known_red=${#KNOWN[@]} unexpected=${#UNEXPECTED[@]}"
if [[ ${#UNEXPECTED[@]} -gt 0 ]]; then
  echo "ci-gate: FAIL — the following suites failed and are NOT on the known-red allow-list:" >&2
  for id in "${UNEXPECTED[@]}"; do
    echo "  - ${id}" >&2
  done
  exit 1
fi

if [[ ${#KNOWN[@]} -gt 0 ]]; then
  echo "ci-gate: PASS — only known-red (allow-listed) suites failed:"
  for id in "${KNOWN[@]}"; do
    echo "  - ${id}"
  done
fi

exit 0
