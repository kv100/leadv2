#!/usr/bin/env bash
# Consumer installs link individual scripts but not scripts/lib.  Exercise all
# four lane-guard loaders through that topology, not through source-text grep.
set -euo pipefail

ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPO="$(cd "${ROOT}/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-consumer-farm.XXXXXX")"
MUTATE_LOADER="${LEADV2_CONSUMER_FARM_MUTATE_LOADER:-}"
declare -a RESTORE_PATHS=()
declare -a RESTORE_COPIES=()
cleanup() {
  local i
  for ((i = 0; i < ${#RESTORE_PATHS[@]}; i++)); do
    cp "${RESTORE_COPIES[$i]}" "${RESTORE_PATHS[$i]}" 2>/dev/null || true
  done
  rm -rf "${T}"
}
trap cleanup EXIT HUP INT TERM
FARM="${T}/consumer/.claude/scripts"
mkdir -p "${FARM}"

# The normal consumer farm has linked sibling scripts but no lib/ directory.
ln -s "${ROOT}/scripts/leadv2-portable-lock.sh" "${FARM}/leadv2-portable-lock.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-code.sh" "${FARM}/leadv2-dispatch-code.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-ledger.sh" "${FARM}/leadv2-dispatch-ledger.sh"
ln -s "${ROOT}/scripts/leadv2-dispatch-product-close.sh" "${FARM}/leadv2-dispatch-product-close.sh"
ln -s "${ROOT}/scripts/lib/leadv2-admission-class.sh" "${FARM}/leadv2-admission-class.sh"
[[ ! -e "${FARM}/lib" ]] || { echo 'FAIL: consumer fixture unexpectedly has lib/' >&2; exit 1; }

run_loader() { # <shell source expression> <farm link> <stdout/stderr file>
  local expr="$1" path="$2" out="$3"
  CLAUDE_PROJECT_ROOT="${REPO}" CLAUDE_PROJECT_DIR="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_CONSUMER_ROOT="${REPO}" LEADV2_CANONICAL_ROOT="${REPO}" bash -c "cd \"${REPO}\"; set -uo pipefail; ${expr}; test \"\$(type -t lv2_lane_root_is_own_worktree)\" = function" \
    _ "${path}" >"${out}" 2>&1
}

check_loader() { # <named production file> <shell source expression> <farm link>
  local name="$1" expr="$2" path="$3" safe out rc
  safe="${name//\//_}"
  out="${T}/${safe}.out"
  set +e
  run_loader "${expr}" "${path}" "${out}"
  rc=$?
  set -e
  if [[ ${rc} -ne 0 || -s "${out}" ]]; then
    echo "FAIL: ${name} did not resolve lane guard (rc=${rc})" >&2
    sed -n '1,40p' "${out}" >&2
    exit 1
  fi
  echo "PASS: ${name} resolves lane guard in a no-lib consumer farm"
}

mutate_canonical_fallback() { # <production loader>; mutate its live body, never a scratch copy
  local production="$1" backup="${T}/$(basename "${production}").before-mutation"
  cp "${production}" "${backup}"
  RESTORE_PATHS+=("${production}")
  RESTORE_COPIES+=("${backup}")
  python3 - "${production}" <<'PY'
import sys
path = sys.argv[1]
needle = '[[ -f "${_LANE_GUARD_SH}" ]] || _LANE_GUARD_SH='
with open(path, 'r') as source:
    text = source.read()
if text.count(needle) != 1:
    raise SystemExit('expected exactly one canonical lane-guard fallback')
with open(path, 'w') as source:
    source.write(text.replace(needle, '# mutation control stripped canonical lane-guard fallback:'))
PY
}

run_red_control() { # <named loader> <source expression> <farm link> <production loader>
  local name="$1" expr="$2" path="$3" production="$4" safe out rc
  mutate_canonical_fallback "${production}"
  safe="${name//\//_}"
  out="${T}/mutated-${safe}.out"
  set +e
  run_loader "${expr}" "${path}" "${out}"
  rc=$?
  set -e
  if [[ ${rc} -eq 0 ]]; then
    echo "FAIL: mutation control unexpectedly green for ${name}" >&2
    exit 1
  fi
  echo "RED control: ${name} (canonical fallback stripped from production body, rc=${rc})" >&2
  sed -n '1,40p' "${out}" >&2
  # The expected RED is deliberately the suite's result: a caller cannot
  # mistake printed output for a diagnostic control that actually passed.
  exit 1
}

case "${MUTATE_LOADER}" in
  '')
    check_loader leadv2-dispatch-code.sh 'LEADV2_DISPATCH_GUARD_SOURCE_ONLY=1 source "$1"' "${FARM}/leadv2-dispatch-code.sh"
    check_loader leadv2-dispatch-ledger.sh 'source "$1"' "${FARM}/leadv2-dispatch-ledger.sh"
    check_loader leadv2-dispatch-product-close.sh 'LEADV2_PRODUCT_CLOSE_SOURCE_ONLY=1 source "$1" "$LEADV2_CONSUMER_ROOT" task arm handle 0 0 founder' "${FARM}/leadv2-dispatch-product-close.sh"
    check_loader lib/leadv2-admission-class.sh 'source "$1"' "${FARM}/leadv2-admission-class.sh"
    ;;
  leadv2-dispatch-code.sh)
    run_red_control "$MUTATE_LOADER" 'LEADV2_DISPATCH_GUARD_SOURCE_ONLY=1 source "$1"' "${FARM}/leadv2-dispatch-code.sh" "${ROOT}/scripts/leadv2-dispatch-code.sh"
    ;;
  leadv2-dispatch-ledger.sh)
    run_red_control "$MUTATE_LOADER" 'source "$1"' "${FARM}/leadv2-dispatch-ledger.sh" "${ROOT}/scripts/leadv2-dispatch-ledger.sh"
    ;;
  leadv2-dispatch-product-close.sh)
    run_red_control "$MUTATE_LOADER" 'LEADV2_PRODUCT_CLOSE_SOURCE_ONLY=1 source "$1" "$LEADV2_CONSUMER_ROOT" task arm handle 0 0 founder' "${FARM}/leadv2-dispatch-product-close.sh" "${ROOT}/scripts/leadv2-dispatch-product-close.sh"
    ;;
  lib/leadv2-admission-class.sh)
    run_red_control "$MUTATE_LOADER" 'source "$1"' "${FARM}/leadv2-admission-class.sh" "${ROOT}/scripts/lib/leadv2-admission-class.sh"
    ;;
  *)
    echo "FAIL: unknown LEADV2_CONSUMER_FARM_MUTATE_LOADER=${MUTATE_LOADER}" >&2
    exit 2
    ;;
esac

echo 'PASS: all four consumer-farm loaders resolve via canonical fallback'
