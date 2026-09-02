#!/usr/bin/env bash
# tests/known-red-guard.sh — CI-RUNS-THE-SUITES-01.
#
# tests/known-red-suites.txt (the CI allow-list of pre-existing red suites)
# may only shrink over time. This compares the entry count in the working
# tree against the entry count at a base ref and fails if it grew — so a
# future PR cannot silently hide a NEW regression by adding it to the
# allow-list instead of fixing it.
#
# usage: tests/known-red-guard.sh [base-ref]
#   base-ref defaults to origin/main, falling back to main, falling back to
#   "no history to compare" (first-ever commit of the list passes trivially).
# exit 0: entry count did not grow (or list is new)
# exit 1: entry count grew relative to base-ref
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
LIST_REL="tests/known-red-suites.txt"
LIST_ABS="${ROOT}/${LIST_REL}"

BASE_REF="${1:-}"
if [[ -z "${BASE_REF}" ]]; then
  for cand in origin/main main; do
    if git -C "${ROOT}" rev-parse --verify "${cand}" >/dev/null 2>&1; then
      BASE_REF="${cand}"
      break
    fi
  done
fi

count_entries() {
  # Non-comment, non-blank lines only.
  grep -vcE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true
}

if [[ ! -f "${LIST_ABS}" ]]; then
  echo "known-red-guard: FATAL ${LIST_REL} does not exist" >&2
  exit 2
fi

CURRENT_COUNT="$(count_entries "${LIST_ABS}")"
CURRENT_COUNT="${CURRENT_COUNT:-0}"

BASE_COUNT=""
if [[ -n "${BASE_REF}" ]] && git -C "${ROOT}" cat-file -e "${BASE_REF}:${LIST_REL}" 2>/dev/null; then
  BASE_COUNT="$(git -C "${ROOT}" show "${BASE_REF}:${LIST_REL}" | grep -vcE '^[[:space:]]*(#|$)' || true)"
  BASE_COUNT="${BASE_COUNT:-0}"
fi

if [[ -z "${BASE_COUNT}" ]]; then
  echo "known-red-guard: no ${LIST_REL} found at base-ref=${BASE_REF:-<none>} — treating as first introduction, nothing to compare (current_count=${CURRENT_COUNT})"
  exit 0
fi

echo "known-red-guard: base=${BASE_REF} base_count=${BASE_COUNT} current_count=${CURRENT_COUNT}"

if [[ "${CURRENT_COUNT}" -gt "${BASE_COUNT}" ]]; then
  echo "known-red-guard: FAIL — ${LIST_REL} grew from ${BASE_COUNT} to ${CURRENT_COUNT} entries." >&2
  echo "known-red-guard: the allow-list may only shrink. Fix a suite and remove its line instead of adding a new one; a genuinely new exception needs sign-off outside CI-RUNS-THE-SUITES-01's scope." >&2
  exit 1
fi

echo "known-red-guard: OK (count did not grow)"
