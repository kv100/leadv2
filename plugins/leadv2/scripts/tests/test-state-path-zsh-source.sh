#!/usr/bin/env bash
# run-all-triggers: leadv2-state-path
# test-state-path-zsh-source.sh — STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01
#
# Exercise the reported shape directly: zsh sources the resolver from both
# the scripts directory and a neutral cwd. Both probes must refuse before any
# path is printed. A guard-less scratch copy is a negative control: it must
# restore the old cwd-shaped, repo-relative fallback.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

STATE_PATH_SH="${STATE_PATH_OVERRIDE:-${SCRIPT_DIR}/../leadv2-state-path.sh}"
PORTABLE_LOCK_SH="${SCRIPT_DIR}/../leadv2-portable-lock.sh"
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
TMP_ROOT="$(lv2_mktemp_dir state-path-zsh-source)"

PASS=0
FAIL=0
ERRORS=()

log() { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# run_zsh_source_probe <resolver> <cwd> <project-root>
run_zsh_source_probe() {
  local resolver="$1" cwd="$2" project_root="$3" err
  if [[ "${cwd}/leadv2-portable-lock.sh" != "$PORTABLE_LOCK_SH" ]]; then
    cp "$PORTABLE_LOCK_SH" "${cwd}/leadv2-portable-lock.sh"
  fi
  err="$(mktemp "${TMP_ROOT}/stderr.XXXXXX")"
  set +e
  PROBE_OUT="$(cd "$cwd" && PROJECT_ROOT="$project_root" \
    LEADV2_STATE_ROOT= LEADV2_STATE_BASE= \
    "$ZSH_BIN" -c 'source "$1" --no-link active.yaml' zsh "$resolver" 2>"$err")"
  PROBE_RC=$?
  set -e
  PROBE_ERR="$(cat "$err")"
}

test_zsh_source_from_scripts_dir_refuses() {
  if [[ -z "$ZSH_BIN" ]]; then
    log 'SKIP: zsh is not installed'
    return 0
  fi
  run_zsh_source_probe "$STATE_PATH_SH" "${SCRIPT_DIR}/.." "${TMP_ROOT}/project"
  if [[ "$PROBE_RC" -ne 0 && -z "$PROBE_OUT" \
        && "$PROBE_ERR" == *'reason=not_file_backed_bash'* \
        && "$PROBE_ERR" == *'BASH_SOURCE[0]'* ]]; then
    pass "zsh source from the scripts dir refuses closed (rc=$PROBE_RC, stdout empty)"
  else
    fail "scripts-dir zsh source was not fail-closed: rc=$PROBE_RC out='$PROBE_OUT' err='$PROBE_ERR'"
  fi
}

test_zsh_source_from_neutral_dir_refuses() {
  if [[ -z "$ZSH_BIN" ]]; then
    return 0
  fi
  local cwd="${TMP_ROOT}/neutral" project_root="${TMP_ROOT}/neutral-project"
  mkdir -p "$cwd" "$project_root"
  run_zsh_source_probe "$STATE_PATH_SH" "$cwd" "$project_root"
  if [[ "$PROBE_RC" -ne 0 && -z "$PROBE_OUT" \
        && "$PROBE_ERR" == *'reason=not_file_backed_bash'* ]]; then
    pass "zsh source from a neutral cwd refuses closed (rc=$PROBE_RC, stdout empty)"
  else
    fail "neutral-cwd zsh source was not fail-closed: rc=$PROBE_RC out='$PROBE_OUT' err='$PROBE_ERR'"
  fi
}

test_guard_removal_flips_red() {
  if [[ -z "$ZSH_BIN" ]]; then
    return 0
  fi
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
  local mutant_dir="${TMP_ROOT}/mutant" mutant project_root mutation_rc
  mkdir -p "$mutant_dir" "${mutant_dir}/project"
  mutant="${mutant_dir}/leadv2-state-path.sh"
  project_root="${mutant_dir}/project"
  cp "$STATE_PATH_SH" "$mutant"
  cp "$PORTABLE_LOCK_SH" "${mutant_dir}/leadv2-portable-lock.sh"
  set +e
  python3 - "$mutant" <<'PYEOF'
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()
marker = 'if [[ -z "${BASH_VERSION:-}" || -z "${BASH_SOURCE[0]:-}" ]]'
start = source.index(marker)
end = source.index("\nfi\n", start) + len("\nfi\n")
source = source[:start] + source[end:]
source = source.replace("set -euo pipefail", "set -eo pipefail", 1)
old_script_dir = next(line for line in source.splitlines() if line.startswith("SCRIPT_DIR="))
source = source.replace(old_script_dir, 'SCRIPT_DIR="$PWD"', 1)
open(path, "w", encoding="utf-8").write(source)
PYEOF
  mutation_rc=$?
  set -e
  if [[ "$mutation_rc" -ne 0 ]]; then
    fail "negative-control mutation could not be applied (rc=$mutation_rc)"
    return 0
  fi
  run_zsh_source_probe "$mutant" "$mutant_dir" "$project_root"
  if [[ "$PROBE_RC" -eq 0 \
        && "$PROBE_OUT" == "${project_root}/docs/leadv2/active.yaml" \
        && -z "$PROBE_ERR" ]]; then
    pass 'guard removal restores the silent repo-relative fallback (negative control flips)'
  else
    fail "guard removal did not fail open: rc=$PROBE_RC out='$PROBE_OUT' err='$PROBE_ERR'"
  fi
}

test_syntax() {
  if bash -n "$STATE_PATH_SH"; then
    pass 'bash -n clean'
  else
    fail 'bash -n failed on leadv2-state-path.sh'
  fi
}

test_zsh_source_from_scripts_dir_refuses
test_zsh_source_from_neutral_dir_refuses
test_guard_removal_flips_red
test_syntax

log '----------------------------------------'
log "RESULTS: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  for error in "${ERRORS[@]}"; do log "$error"; done
  exit 1
fi
exit 0
