#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-phase-record
# test-phase-record-class.sh — PHASE-RECORD-REJECTS-TWO-DOCUMENTED-TASK-CLASSES-01.
#
# Both public class entry points must consume the exact same vocabulary.  The
# production source's one vocabulary lives inside _phase_record_valid_classes;
# this declared negative control removes Strategic from that function body:
#   bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live \
#     plugins/leadv2/scripts/tests/test-phase-record-class.sh \
#     plugins/leadv2/scripts/leadv2-phase-record.sh \
#     's|local -r classes="Trivial Light Standard Heavy Strategic Bulk"|local -r classes="Trivial Light Standard Heavy Bulk"|' \
#     plugins/leadv2/scripts/tests
# It must make the Strategic cases below fail while preserving the same suite
# and every other input.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"
TMP_ROOT="$(mktemp -d /tmp/leadv2-phase-record-class.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

unset PROJECT_ROOT
export LEADV2_PROJECT_ROOT="${TMP_ROOT}"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

run_expect() { # <label> <expected-rc> <subcommand> [args...]
  local label="$1" expected="$2" output rc
  shift 2
  output="$(bash "${PHASE_RECORD}" "$@" 2>&1)"
  rc=$?
  if [[ "${rc}" -eq "${expected}" ]]; then
    pass "${label} rc=${rc}"
    printf '%s\n' "${output}"
  else
    fail "${label} expected_rc=${expected} actual_rc=${rc} output=${output}"
  fi
}

printf 'test: all canonical classes reach both public validators\n'
for cls in Trivial Light Standard Heavy Strategic Bulk; do
  run_expect "assert class=${cls}" 0 assert classcheck --class "${cls}" --pre-build
  run_expect "plan-for class=${cls}" 0 plan-for --class "${cls}"
done

printf 'test: Strategic and Bulk use exact producer casing\n'
for cls in strategic bulk; do
  run_expect "assert lowercase class=${cls}" 4 assert classcase --class "${cls}" --pre-build
  run_expect "plan-for lowercase class=${cls}" 4 plan-for --class "${cls}"
done

printf 'test: paired unknown value preserves each entry point error\n'
for command in assert plan-for; do
  if [[ "${command}" == "assert" ]]; then
    output="$(bash "${PHASE_RECORD}" assert classunknown --class Nonsense --pre-build 2>&1)"
  else
    output="$(bash "${PHASE_RECORD}" plan-for --class Nonsense 2>&1)"
  fi
  rc=$?
  expected="[leadv2-phase-record.sh] ERROR: ${command}: invalid class 'Nonsense'"
  if [[ ${rc} -eq 4 && "${output}" == "${expected}" ]]; then
    pass "${command} Nonsense keeps rc=4 and prior error"
  else
    fail "${command} Nonsense expected_rc=4 expected=${expected} actual_rc=${rc} output=${output}"
  fi
done

printf 'test: YAML override parser reads the same class vocabulary\n'
mkdir -p "${TMP_ROOT}/.claude/leadv2-overrides"
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YAML'
version: 1
class_overrides:
  Strategic:
    mandatory:
      - e2e
  Bulk:
    mandatory:
      - e2e
YAML
for cls in Strategic Bulk; do
  output="$(bash "${PHASE_RECORD}" plan-for --class "${cls}" 2>&1)"
  rc=$?
  if [[ ${rc} -eq 0 && "${output}" == *"MANDATORY e2e"* ]]; then
    pass "YAML override class=${cls} accepted"
  else
    fail "YAML override class=${cls} expected mandatory e2e actual_rc=${rc} output=${output}"
  fi
done

printf 'RESULT: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
