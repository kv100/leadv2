#!/usr/bin/env bash
# run-all-triggers: run-all run-core-offline
#
# test-run-all-forwards-scope.sh — E2E-GATE-RUNS-ALL-94-SUITES-BECAUSE-
# run-all-SWALLOWS-SCOPE-01.
#
# tests/run-all.sh always ran the plugin's core-offline suite
# (plugins/leadv2/scripts/tests/run-core-offline.sh) as a bare `bash
# <suite>`, even though run-core-offline.sh has had its own `--scope
# changed|all` contract since it added scope-aware selection. Nothing
# upstream of it ever forwarded a scope, so a `--scope changed` phase-8 gate
# run always ran the full 95-suite set (900s timeout) instead of the 3-4
# suites the diff actually touched (0.2s). This suite proves the forward
# happens, in both directions, without depending on the real (slow)
# core-offline suite tree: it builds a throwaway git fixture containing a
# copy of the FILE UNDER TEST (run-all.sh, picked up from this suite's own
# directory so a mutated copy is exercised too) plus a FAKE core-offline
# stub that only records its own argv.
#
# Every assertion below reads the fake stub's own recorded argv line, never
# a log string from run-all.sh itself, so a mutant cannot pass by rewording
# the "delegating scope=" line while still forwarding the wrong value.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01) — see the matching comment
# block above core_offline_scope_arg() in tests/run-all.sh for what each
# mutant does and why it reddens the relevant case here, not both.
#
# Hermetic: the fixture is a throwaway git repo under mktemp -d; nothing
# under docs/leadv2 or the real plugins/leadv2/scripts/tests tree is
# touched or executed. Run: bash tests/test-run-all-forwards-scope.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ALL_UNDER_TEST="${SCRIPT_DIR}/run-all.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

FIXTURES=()
cleanup() { local d; for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done; }
trap cleanup EXIT

if [[ ! -f "${RUN_ALL_UNDER_TEST}" ]]; then
  fail "run-all.sh not found at ${RUN_ALL_UNDER_TEST}"
  printf 'FAIL: %d, PASS: %d\n' "${FAIL}" "${PASS}"
  exit 1
fi

# ── fixture: a throwaway git repo with a copy of run-all.sh under test and a
#    fake core-offline stub that just records the argv it was invoked with ──
build_fixture() { # -> sets FIX
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/run-all-scope-fix.XXXXXX")"
  FIX="$(cd -P "${FIX}" && pwd)"  # macOS: TMPDIR is a symlink; match git's physical realpath
  FIXTURES+=("${FIX}")
  mkdir -p "${FIX}/tests" "${FIX}/plugins/leadv2/scripts/tests" \
           "${FIX}/.claude/scripts/tests" "${FIX}/plugins/leadv2/tests"
  cp "${RUN_ALL_UNDER_TEST}" "${FIX}/tests/run-all.sh"
  chmod +x "${FIX}/tests/run-all.sh"
  cat > "${FIX}/plugins/leadv2/scripts/tests/run-core-offline.sh" <<'STUB'
#!/usr/bin/env bash
printf 'FAKE-CORE-OFFLINE argv=%s\n' "$*"
exit 0
STUB
  chmod +x "${FIX}/plugins/leadv2/scripts/tests/run-core-offline.sh"
  ( cd "${FIX}" \
      && git init -q \
      && git branch -m main \
      && git add -A \
      && git -c user.email=t@local -c user.name=t commit -qm base -q ) >/dev/null 2>&1
}

# ── executed test: run tests/run-all.sh --scope <given>, assert the fake
#    stub recorded argv containing `--scope <expected>` ───────────────────
check_forward() { # <given-scope> <expected-forwarded-scope> <case-label>
  local given="$1" expected="$2" label="$3" out stub_line
  build_fixture
  out="$(cd "${FIX}" && bash tests/run-all.sh --scope "${given}" 2>&1)"
  stub_line="$(printf '%s\n' "${out}" | grep '^FAKE-CORE-OFFLINE argv=' | head -1)"
  if [[ -z "${stub_line}" ]]; then
    fail "${label}: fake core-offline stub was never invoked"
    printf '%s\n' "${out}" | tail -10
    return
  fi
  case "${stub_line}" in
    *"--scope ${expected}"*)
      pass "${label}: forwarded --scope ${expected}" ;;
    *)
      fail "${label}: expected '--scope ${expected}' in stub argv, got: ${stub_line}" ;;
  esac
}

check_forward "changed" "changed" "scope=changed forwards changed"
check_forward "all"     "all"     "scope=all forwards all"

if [[ ${FAIL} -gt 0 ]]; then
  printf '  Failures:\n'
  for e in "${ERRORS[@]}"; do printf '    - %s\n' "${e}"; done
fi
printf 'test-run-all-forwards-scope: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
