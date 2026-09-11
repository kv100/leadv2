#!/usr/bin/env bash
# run-all-triggers: leadv2-state-path.sh
# test-state-path-fails-closed.sh — STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01
#
# The resolver is a bash script, so the unset-BASH_SOURCE case is exercised by
# evaluating its file body from bash -c, not by starting zsh. In an eval body
# BASH_SOURCE[0] is genuinely unset. The probe is deliberately run from a
# scratch cwd containing the resolver's sibling so the old cwd-shaped lookup
# cannot be mistaken for a missing dependency.
#
# Contract:
#   * no file-backed bash context => non-zero, empty stdout, diagnostic naming
#     the unavailable BASH_SOURCE mechanism;
#   * executed bash and sourced-from-file bash behavior remain unchanged;
#   * removing the refusal guard makes the same probe fail open with a
#     repo-relative path, so the suite must turn red under that mutation.
#
# Run: bash plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

STATE_PATH_SH="${STATE_PATH_OVERRIDE:-${SCRIPT_DIR}/../leadv2-state-path.sh}"
PORTABLE_LOCK_SH="${SCRIPT_DIR}/../leadv2-portable-lock.sh"
TMP_ROOT="$(lv2_mktemp_dir state-path-fails-closed)"

PASS=0
FAIL=0
ERRORS=()

cleanup() {
  find "$TMP_ROOT" -type f -exec rm -f {} + 2>/dev/null || true
  find "$TMP_ROOT" -depth -type d -exec rmdir {} + 2>/dev/null || true
}
trap cleanup EXIT

log() { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# run_eval_probe <resolver> <cwd> <project-root> <stderr-file>
# The inner bash assertion proves the exact precondition before the resolver
# body is evaluated; no zsh-specific behavior is involved.
run_eval_probe() {
  local resolver="$1" cwd="$2" project_root="$3" stderr_file="$4"
  # Keep the old fail-open trap available in every probe cwd. The clean
  # resolver refuses before reading it; a guard mutation must get far enough
  # to source this sibling and print the wrong repo-relative path.
  [[ -f "$cwd/leadv2-portable-lock.sh" ]] || cp "$PORTABLE_LOCK_SH" "$cwd/leadv2-portable-lock.sh"
  PROBE_OUT="$(cd "$cwd" && PROJECT_ROOT="$project_root" bash -c \
    '[[ -z "${BASH_SOURCE[0]:-}" ]] || exit 91; resolver="$1"; shift; eval "$(cat "$resolver")"' \
    bash "$resolver" --no-link active.yaml 2>"$stderr_file")"
  PROBE_RC=$?
  PROBE_ERR="$(cat "$stderr_file" 2>/dev/null || true)"
}

test_eval_without_bash_source_refuses() {
  local d="${TMP_ROOT}/eval-refusal" err
  mkdir -p "$d/cwd" "$d/project"
  err="${d}/stderr.txt"
  run_eval_probe "$STATE_PATH_SH" "$d/cwd" "$d/project" "$err"
  if [[ "$PROBE_RC" -ne 0 && -z "$PROBE_OUT" \
        && "$PROBE_ERR" == *'reason=not_file_backed_bash'* \
        && "$PROBE_ERR" == *'BASH_SOURCE[0]'* ]]; then
    pass "bash -c eval with BASH_SOURCE unset refuses closed (rc=$PROBE_RC, stdout empty)"
  else
    fail "unset BASH_SOURCE did not refuse closed: rc=$PROBE_RC out='$PROBE_OUT' err='$PROBE_ERR'"
  fi
  if [[ "$PROBE_ERR" != *'portable-lock'* ]]; then
    pass "diagnostic names the unavailable location mechanism, not a sibling lookup"
  else
    fail "diagnostic names the wrong missing mechanism: $PROBE_ERR"
  fi
}

test_executed_bash_keeps_resolution() {
  local d="${TMP_ROOT}/exec" state out rc
  mkdir -p "$d/project"
  cp "$PORTABLE_LOCK_SH" "$d/leadv2-portable-lock.sh"
  state="${d}/state"
  set +e
  out="$(cd "$d" && LEADV2_STATE_ROOT="$state" PROJECT_ROOT="${d}/project" \
    bash "$STATE_PATH_SH" --no-link active.yaml 2>"${d}/stderr.txt")"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && "$out" == "${state}/active.yaml" \
        && ! -s "${d}/stderr.txt" ]]; then
    pass "executed bash still resolves the explicit state root"
  else
    fail "executed bash changed: rc=$rc out='$out' err='$(cat "${d}/stderr.txt")'"
  fi
}

test_sourced_file_backed_bash_keeps_resolution() {
  local d="${TMP_ROOT}/source" state runner out rc
  mkdir -p "$d/project"
  cp "$PORTABLE_LOCK_SH" "$d/leadv2-portable-lock.sh"
  state="${d}/state"
  runner="${d}/runner.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    "source \"${STATE_PATH_SH}\" --no-link active.yaml" > "$runner"
  set +e
  out="$(cd "$d" && LEADV2_STATE_ROOT="$state" PROJECT_ROOT="${d}/project" \
    bash "$runner" 2>"${d}/stderr.txt")"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && "$out" == "${state}/active.yaml" \
        && ! -s "${d}/stderr.txt" ]]; then
    pass "sourced from a real bash file context still resolves normally"
  else
    fail "bash file-context source changed: rc=$rc out='$out' err='$(cat "${d}/stderr.txt")'"
  fi
}

test_mutation_guard_removed_goes_red() {
  local d="${TMP_ROOT}/mutation" mutated err
  local guard_probe_rc
  if grep -Fq 'if [[ -z "${BASH_VERSION:-}" || -z "${BASH_SOURCE[0]:-}" ]]' "$STATE_PATH_SH"; then
    guard_probe_rc=0
  else
    guard_probe_rc=$?
  fi
  if [[ "$guard_probe_rc" -ne 0 ]]; then
    fail "resolver refusal guard is absent or its assertion tool failed (grep rc=$guard_probe_rc)"
    return 0
  fi
  mkdir -p "$d/cwd" "$d/project"
  mutated="${d}/cwd/leadv2-state-path.sh"
  cp "$STATE_PATH_SH" "$mutated"
  cp "$PORTABLE_LOCK_SH" "${d}/cwd/leadv2-portable-lock.sh"
  set +e
  python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); marker="if [[ -z \"${BASH_VERSION:-}\" || -z \"${BASH_SOURCE[0]:-}\" ]]"; start=s.index(marker); end=s.index("\nfi\n", start)+len("\nfi\n"); s=s[:start]+s[end:]; s=s.replace("set -euo pipefail","set -eo pipefail",1); old=[line for line in s.splitlines() if line.startswith("SCRIPT_DIR=")][0]; s=s.replace(old,"SCRIPT_DIR=\"$PWD\"",1); open(p,"w").write(s)' "$mutated"
  mutation_rc=$?
  set -e
  if [[ "$mutation_rc" -ne 0 ]]; then
    fail "negative-control mutation could not be applied (rc=$mutation_rc)"
    return 0
  fi
  err="${d}/stderr.txt"
  run_eval_probe "$mutated" "$d/cwd" "$d/project" "$err"
  # This is the declared negative control: the guard-less copy restores the
  # old cwd/repo-relative fallback and must return success. The clean suite
  # passes only after proving that this mutation flips the resolver open.
  if [[ "$PROBE_RC" -eq 0 && "$PROBE_OUT" == "$d/project/docs/leadv2/active.yaml" \
        && -z "$PROBE_ERR" ]]; then
    pass "declared silent-fallback mutation fails open (negative control flips)"
  else
    fail "declared mutation did not fail open: rc=$PROBE_RC out='$PROBE_OUT' err='$PROBE_ERR'"
  fi
}

test_syntax() {
  if bash -n "$STATE_PATH_SH"; then
    pass "bash -n clean"
  else
    fail "bash -n failed on leadv2-state-path.sh"
  fi
}

test_eval_without_bash_source_refuses
test_executed_bash_keeps_resolution
test_sourced_file_backed_bash_keeps_resolution
test_mutation_guard_removed_goes_red
test_syntax

log '----------------------------------------'
log "RESULTS: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  for error in "${ERRORS[@]}"; do log "$error"; done
  exit 1
fi
exit 0
