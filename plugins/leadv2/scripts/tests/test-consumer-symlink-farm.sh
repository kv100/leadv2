#!/usr/bin/env bash
# Consumer installs link individual scripts but not scripts/lib.  Exercise all
# four lane-guard loaders through that topology, not through source-text grep.
set -euo pipefail

ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPO="$(cd "${ROOT}/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-consumer-farm.XXXXXX")"
cleanup() { rm -rf "${T}"; }
trap cleanup EXIT
FARM="${T}/consumer/.claude/scripts"
mkdir -p "${FARM}"

# The normal consumer farm has linked sibling scripts but no lib/ directory.
ln -s "${ROOT}/scripts/leadv2-portable-lock.sh" "${FARM}/leadv2-portable-lock.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-code.sh" "${FARM}/leadv2-dispatch-code.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-ledger.sh" "${FARM}/leadv2-dispatch-ledger.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-product-close.sh" "${FARM}/leadv2-dispatch-product-close.sh"
ln -s "${ROOT}/scripts/lib/leadv2-admission-class.sh" "${FARM}/leadv2-admission-class.sh"
[[ ! -e "${FARM}/lib" ]] || { echo 'FAIL: consumer fixture unexpectedly has lib/' >&2; exit 1; }

check_loader() { # <named production file> <shell source expression> <farm link>
  local name="$1" expr="$2" path="$3" safe out rc
  safe="${name//\//_}"
  out="${T}/${safe}.out"
  set +e
  CLAUDE_PROJECT_ROOT="${REPO}" CLAUDE_PROJECT_DIR="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_CONSUMER_ROOT="${REPO}" LEADV2_CANONICAL_ROOT="${REPO}" bash -c "cd \"${REPO}\"; set -uo pipefail; ${expr}; test \"\$(type -t lv2_lane_dirty)\" = function" \
    _ "${path}" >"${out}" 2>&1
  rc=$?
  set -e
  if [[ ${rc} -ne 0 || -s "${out}" ]]; then
    echo "FAIL: ${name} did not resolve lane guard (rc=${rc})" >&2
    sed -n '1,40p' "${out}" >&2
    exit 1
  fi
  echo "PASS: ${name} resolves lane guard in a no-lib consumer farm"
}

check_loader leadv2-dispatch-code.sh 'LEADV2_DISPATCH_SOURCE_ONLY=1 source "$1"' "${FARM}/leadv2-dispatch-code.sh"
check_loader leadv2-dispatch-ledger.sh 'source "$1"' "${FARM}/leadv2-dispatch-ledger.sh"
check_loader leadv2-dispatch-product-close.sh 'LEADV2_PRODUCT_CLOSE_SOURCE_ONLY=1 source "$1" "$LEADV2_CONSUMER_ROOT" task arm handle 0 0 founder' "${FARM}/leadv2-dispatch-product-close.sh"
check_loader lib/leadv2-admission-class.sh 'source "$1"' "${FARM}/leadv2-admission-class.sh"

# RED control: remove reachability of the canonical root for each loader in
# turn.  A regression must name the specific production loader; this is
# position-independent and does not stop after the first one.
for spec in \
  'leadv2-dispatch-code.sh:LEADV2_DISPATCH_SOURCE_ONLY=1 source "$1"' \
  'leadv2-dispatch-ledger.sh:source "$1"' \
  'leadv2-dispatch-product-close.sh:LEADV2_PRODUCT_CLOSE_SOURCE_ONLY=1 source "$1" "$LEADV2_CONSUMER_ROOT" task arm handle 0 0 founder' \
  'lib/leadv2-admission-class.sh:source "$1"'; do
  name="${spec%%:*}"; expr="${spec#*:}"; out="${T}/missing-${name//\//_}.out"
  set +e
  CLAUDE_PROJECT_ROOT="${REPO}" CLAUDE_PROJECT_DIR="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_CONSUMER_ROOT="${REPO}" LEADV2_CANONICAL_ROOT="${T}/missing-canonical" bash -c "cd \"${REPO}\"; set -uo pipefail; ${expr}; test \"\$(type -t lv2_lane_dirty)\" = function" \
    _ "${FARM}/${name##*/}" >"${out}" 2>&1
  rc=$?
  set -e
  if [[ ${rc} -eq 0 && ! -s "${out}" ]]; then
    echo "FAIL: mutation control unexpectedly green for ${name}" >&2
    exit 1
  fi
  echo "RED control: ${name} (canonical fallback unreachable, rc=${rc})"
done

echo 'PASS: all four consumer-farm loaders resolve via canonical fallback'
