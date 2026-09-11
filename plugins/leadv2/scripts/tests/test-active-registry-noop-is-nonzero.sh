#!/usr/bin/env bash
# REGISTRY-SILENT-RC0-01 — six real-function no-op controls.
# run-all-triggers: leadv2-active-registry.sh
#
# Each case sources the production registry and uses a throwaway state root.
# It checks rc, task/reason diagnostics, and that failed operations do not
# rewrite or materialise active.yaml.
#
# Declared live negative controls (run with leadv2-mutation-control.sh):
# M1 unregister no-match sys.exit(4) -> sys.exit(0)
# M2 set_worktree path-absent return 2 -> return 0
# M3 update_phase file guard -> true
# M4 update_pulse no-match sys.exit(4) -> sys.exit(0)
# M5 set_worker_pid no-match sys.exit(4) -> sys.exit(0)
# M6 unregister file guard -> true
# Each mutant must make this suite exit non-zero; the live artifacts are the
# authoritative proof of those six red runs.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/../leadv2-temp.sh"
REGISTRY_SH="$SCRIPT_DIR/../leadv2-active-registry.sh"
STATE_PATH_BIN="$SCRIPT_DIR/../leadv2-state-path.sh"
PASS=0
FAIL=0
log() { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

new_sb() {
  local d
  d="$(lv2_mktemp_dir registry-noop)"
  mkdir -p "$d/proj" "$d/state"
  printf '%s\n' "$d"
}

run_sb() { # <sandbox> <stderr> <snippet>
  local sb="$1" err="$2" snippet="$3"
  REGISTRY_SH="$REGISTRY_SH" LEADV2_PROJECT_ROOT="$sb/proj" \
  LEADV2_STATE_ROOT="$sb/state" LEADV2_STATE_PATH_BIN="$STATE_PATH_BIN" \
    bash -c '
      set -uo pipefail
      source "$REGISTRY_SH"
      '"$snippet"'
    ' 2>"$err"
}

value() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

case_1() {
  local sb err out rc
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_register REG-SILENT-1 Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"; cp "$yaml" "$yaml.before"
    leadv2_active_unregister REG-SILENT-NOPE >/dev/null
    echo "RC=$?"
    cmp -s "$yaml" "$yaml.before" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')"; rc=$?
  if [[ $rc -eq 0 && "$(value "$out" RC)" == 4 && "$(value "$out" UNCHANGED)" == yes ]] &&
     grep -q 'task=REG-SILENT-NOPE.*reason=not-found' "$err"; then
    pass 'case 1 unregister not-found is rc=4 and byte-preserving'
  else
    fail "case 1 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

case_2() {
  local sb err out rc
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_register REG-SILENT-2 Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"; cp "$yaml" "$yaml.before"
    leadv2_active_set_worktree REG-SILENT-NOPE "$LEADV2_PROJECT_ROOT" >/dev/null
    echo "UNKNOWN_RC=$?"
    leadv2_active_set_worktree REG-SILENT-2 "$LEADV2_PROJECT_ROOT/no-such-worktree" >/dev/null
    echo "ABSENT_RC=$?"
    cmp -s "$yaml" "$yaml.before" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')"; rc=$?
  if [[ $rc -eq 0 && "$(value "$out" UNKNOWN_RC)" == 4 &&
        "$(value "$out" ABSENT_RC)" == 2 && "$(value "$out" UNCHANGED)" == yes ]] &&
     grep -q 'task=REG-SILENT-NOPE.*reason=not-found' "$err" &&
     grep -q 'task=REG-SILENT-2.*reason=path-absent' "$err"; then
    pass 'case 2 set_worktree reports not-found/path-absent and preserves bytes'
  else
    fail "case 2 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

case_3() {
  local sb err out rc
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_update_phase REG-SILENT-3 build >/dev/null
    echo "MISSING_RC=$?"
    yaml="$(_leadv2_yaml_file)"
    [[ ! -e "$yaml" ]] && echo "NOFILE=yes" || echo "NOFILE=no"
    leadv2_active_register REG-SILENT-3-ROW Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"; cp "$yaml" "$yaml.before"
    leadv2_active_update_phase REG-SILENT-3-NOPE build >/dev/null
    echo "UNKNOWN_RC=$?"
    cmp -s "$yaml" "$yaml.before" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')"; rc=$?
  if [[ $rc -eq 0 && "$(value "$out" MISSING_RC)" == 4 &&
        "$(value "$out" UNKNOWN_RC)" == 4 && "$(value "$out" NOFILE)" == yes &&
        "$(value "$out" UNCHANGED)" == yes ]] &&
     grep -q 'task=REG-SILENT-3.*reason=file-missing' "$err" &&
     grep -q 'task=REG-SILENT-3-NOPE.*reason=not-found' "$err"; then
    pass 'case 3 update_phase rejects file-missing and unknown task'
  else
    fail "case 3 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

case_4() {
  local sb err out rc
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_update_pulse REG-SILENT-4 >/dev/null
    echo "MISSING_RC=$?"
    yaml="$(_leadv2_yaml_file)"
    [[ ! -e "$yaml" ]] && echo "NOFILE=yes" || echo "NOFILE=no"
    leadv2_active_register REG-SILENT-4-ROW Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"; cp "$yaml" "$yaml.before"
    leadv2_active_update_pulse REG-SILENT-4-NOPE >/dev/null
    echo "UNKNOWN_RC=$?"
    cmp -s "$yaml" "$yaml.before" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')"; rc=$?
  if [[ $rc -eq 0 && "$(value "$out" MISSING_RC)" == 4 &&
        "$(value "$out" UNKNOWN_RC)" == 4 && "$(value "$out" NOFILE)" == yes &&
        "$(value "$out" UNCHANGED)" == yes ]] &&
     grep -q 'task=REG-SILENT-4.*reason=file-missing' "$err" &&
     grep -q 'task=REG-SILENT-4-NOPE.*reason=not-found' "$err"; then
    pass 'case 4 update_pulse rejects file-missing and unknown task'
  else
    fail "case 4 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

case_5() {
  local sb err out rc
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_register REG-SILENT-5 Standard "$LEADV2_PROJECT_ROOT" branch false >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"; cp "$yaml" "$yaml.before"
    leadv2_active_set_worker_pid REG-SILENT-5-NOPE 12345 birth worker >/dev/null
    echo "RC=$?"
    cmp -s "$yaml" "$yaml.before" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')"; rc=$?
  if [[ $rc -eq 0 && "$(value "$out" RC)" == 4 &&
        "$(value "$out" UNCHANGED)" == yes ]] &&
     grep -q 'task=REG-SILENT-5-NOPE.*reason=not-found' "$err"; then
    pass 'case 5 set_worker_pid rejects unknown task without a row change'
  else
    fail "case 5 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

case_6() {
  local sb err out rc yaml
  sb="$(new_sb)"; err="$sb/err"
  out="$(run_sb "$sb" "$err" '
    leadv2_active_unregister REG-SILENT-6 >/dev/null
    echo "RC=$?"
    yaml="$(_leadv2_yaml_file)"
    [[ ! -e "$yaml" ]] && echo "NOFILE=yes" || echo "NOFILE=no"
  ')"; rc=$?; yaml="$sb/state/active.yaml"
  if [[ $rc -eq 0 && "$(value "$out" RC)" == 4 &&
        "$(value "$out" NOFILE)" == yes && ! -e "$yaml" ]] &&
     grep -q 'task=REG-SILENT-6.*reason=file-missing' "$err"; then
    pass 'case 6 unregister rejects file-missing without materialising state'
  else
    fail "case 6 rc=$rc out=$out err=$(tr '\n' ' ' <"$err")"
  fi
  rm -rf "$sb"
}

main() {
  log '=== REGISTRY-SILENT-RC0-01 real-function suite ==='
  log "registry=$REGISTRY_SH"
  case_1; case_2; case_3; case_4; case_5; case_6
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  [[ $FAIL -eq 0 ]]
}
main "$@"
