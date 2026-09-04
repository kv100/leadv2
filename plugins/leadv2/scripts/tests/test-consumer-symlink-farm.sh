#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-admission-class.sh leadv2-dispatch-code.sh leadv2-dispatch-ledger.sh leadv2-dispatch-product-close.sh test-consumer-symlink-farm.sh
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

# This sibling is part of the linked-script installation, not scripts/lib.  It
# gives the real terminal ledger a deterministic pinned lane for the close
# probe below.
TERMINAL_MAIN="${T}/terminal-main"
TERMINAL_LANE="${T}/terminal-lane"
TERMINAL_LEDGER="${T}/terminal-ledger.jsonl"
git init -q "${TERMINAL_MAIN}"
git -C "${TERMINAL_MAIN}" config user.email test@example.invalid
git -C "${TERMINAL_MAIN}" config user.name consumer-farm-test
printf 'seed\n' > "${TERMINAL_MAIN}/worker.txt"
git -C "${TERMINAL_MAIN}" add worker.txt
git -C "${TERMINAL_MAIN}" commit -qm seed
git -C "${TERMINAL_MAIN}" worktree add -q -b terminal-lane "${TERMINAL_LANE}" HEAD
cat > "${FARM}/leadv2-lane-worktree.sh" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == path-of ]] && printf '%s\\n' "${TERMINAL_LANE}"
EOF
chmod +x "${FARM}/leadv2-lane-worktree.sh"

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

last_terminal() { tail -n 1 "${TERMINAL_LEDGER}"; }
assert_terminal() { # <terminal> <cause prefix>
  local terminal="$1" cause="$2" row
  row="$(last_terminal)"
  if [[ "${row}" != *"\"terminal\":\"${terminal}\""* || "${row}" != *"\"cause\":\"${cause}"* ]]; then
    echo "FAIL: expected terminal=${terminal} cause=${cause}, got: ${row}" >&2
    exit 1
  fi
}

run_product_close_terminal() { # <canonical root> <output file>
  local canonical="$1" out="$2" rc
  set +e
  PROJECT_ROOT="${TERMINAL_MAIN}" LEADV2_PROJECT_ROOT="${TERMINAL_MAIN}" \
    LEADV2_CANONICAL_ROOT="${canonical}" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${TERMINAL_LEDGER}" \
    LEADV2_PRODUCT_CLOSE_SOURCE_ONLY=1 \
    LEADV2_DISPATCH_LANE_WRITES=worker.txt \
    bash -c 'set -uo pipefail; source "$1" "$2" terminal01 arm handle 0 0 founder; _dl_note landed completed' \
      _ "${FARM}/leadv2-dispatch-product-close.sh" "${TERMINAL_MAIN}" >"${out}" 2>&1
  rc=$?
  set -e
  if [[ ${rc} -ne 0 ]]; then
    echo "FAIL: product close terminal probe failed rc=${rc}" >&2
    sed -n '1,80p' "${out}" >&2
    exit 1
  fi
}

exercise_close_gate() { # <canonical root> <dirty|clean> <output>
  local canonical="$1" state="$2" out="$3"
  : > "${TERMINAL_LEDGER}"
  git -C "${TERMINAL_LANE}" checkout -- worker.txt
  if [[ "${state}" == dirty ]]; then
    printf 'dirty\n' >> "${TERMINAL_LANE}/worker.txt"
  fi
  run_product_close_terminal "${canonical}" "${out}"
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

# The direct close-gate proof is intentionally data-driven: it asserts the
# persisted terminal record, never the production script's source text.
exercise_close_gate "${T}/no-canonical-root" dirty "${T}/missing-guard.out"
assert_terminal pass_unlanded dirty_lane:completed
if grep -Fq '"terminal":"landed"' "${TERMINAL_LEDGER}"; then
  echo 'FAIL: missing guard let a dirty lane record landed' >&2
  exit 1
fi
if ! grep -Fq '[leadv2-dispatch-product-close] ERROR: lane guard unavailable' "${T}/missing-guard.out"; then
  echo 'FAIL: product close did not emit the named missing-guard error' >&2
  sed -n '1,80p' "${T}/missing-guard.out" >&2
  exit 1
fi
echo 'PASS: missing local and canonical guards fail CLOSED (terminal=pass_unlanded)'

exercise_close_gate "${REPO}" clean "${T}/canonical-guard.out"
assert_terminal landed completed
if grep -Fq 'lane guard unavailable' "${T}/canonical-guard.out"; then
  echo 'FAIL: canonical guard path emitted a missing-guard error' >&2
  exit 1
fi
echo 'PASS: canonical guard with a clean lane records terminal=landed'

# Mutation proof, unconditional -- every default invocation re-derives this,
# not an opt-in flag CI never sets. The two assertions above (:177-196)
# depend on leadv2-dispatch-ledger.sh's OWN canonical-fallback stub, never on
# leadv2-dispatch-product-close.sh's: _dl_note always shells out to
# leadv2-dispatch-ledger.sh write-terminal as a SEPARATE process (see
# leadv2-dispatch-product-close.sh:79 "Always a subprocess call (never
# sourced)"), so it is that process's own lv2_lane_dirty definition that
# decides the persisted terminal row -- product-close.sh's copy of the same
# fallback pattern (used only by its in-process silence/review-gate checks,
# never by the terminal write) is not on this path. Verified live with
# bash -x: even with product-close.sh's own guard missing, its else-branch
# runs and prints the missing-guard error asserted at :183-187, but the
# ledger subprocess resolves (or fails to resolve) the guard independently.
# Mutation is in the live production fallback body, never a scratch copy.
production="${ROOT}/scripts/leadv2-dispatch-ledger.sh"
backup="${T}/leadv2-dispatch-ledger.before-close-gate-mutation"
cp "${production}" "${backup}"
RESTORE_PATHS+=("${production}")
RESTORE_COPIES+=("${backup}")
python3 - "${production}" <<'PY'
import sys
path = sys.argv[1]
with open(path) as source:
    text = source.read()
needle = 'lv2_lane_dirty() { return 0; }'
if text.count(needle) != 1:
    raise SystemExit('expected exactly one fail-closed ledger fallback body')
with open(path, 'w') as destination:
    destination.write(text.replace(needle, 'lv2_lane_dirty() { return 1; }'))
PY
exercise_close_gate "${T}/no-canonical-root" dirty "${T}/mutated-close-gate.out"
mutated_row="$(last_terminal)"
cp "${backup}" "${production}"
if [[ "${mutated_row}" != *'"terminal":"landed"'* ]]; then
  echo "FAIL: close-gate mutation unexpectedly stayed fail-closed: ${mutated_row}" >&2
  exit 1
fi
echo 'PASS: mutation control -- flipping the ledger fail-closed stub to fail-open lets a dirty lane record landed (RED without the guarantee)'

exercise_close_gate "${T}/no-canonical-root" dirty "${T}/restored-close-gate.out"
assert_terminal pass_unlanded dirty_lane:completed
echo 'PASS: restored ledger fail-closed stub returns the dirty lane to pass_unlanded (GREEN with the guarantee back)'

echo 'PASS: all four consumer-farm loaders resolve via canonical fallback'
