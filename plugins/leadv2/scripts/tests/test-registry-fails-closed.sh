#!/usr/bin/env bash
# tests/test-registry-fails-closed.sh — WAVE0-REGISTRY-FAILS-OPEN-01: the six
# mutating registry ops must fail CLOSED when the task_id is unknown or
# active.yaml is missing: non-zero rc + a machine-readable `registry: …`
# stderr line + no silent write (bytes untouched, or the file never created).
#
# Rows under test (plugins/leadv2/scripts/leadv2-active-registry.sh):
#   test_1  python `unregister`: 0 rows matched        -> rc 4, no rewrite
#   test_2  set_worktree: unknown tid -> rc 4; not-a-directory -> rc 2
#   test_3  update_phase: active.yaml absent            -> rc 4, no create
#   test_4  update_pulse: unknown tid                   -> rc 4, no write
#   test_5  set_worker_pid: unknown tid                 -> rc 4, no row
#   test_6  unregister (shell): active.yaml absent      -> rc 4, no create
#
# Negative control (red run pasted in the developer report): copy the registry
# NEXT TO ITSELF (it resolves lib/ and bundled scripts via BASH_SOURCE, so a
# /tmp copy breaks sourcing), inject `return 0` as the first body line of
# leadv2_active_update_pulse, then run
#   REGISTRY_SH=plugins/leadv2/scripts/.reg-mut-nc.sh \
#     bash plugins/leadv2/scripts/tests/test-registry-fails-closed.sh
# Acceptance: EXACTLY test_4 red, five green.
#
# Portable: no GNU-only tools; sandboxed via LEADV2_PROJECT_ROOT /
# LEADV2_STATE_ROOT env overrides, no git repo needed.
# Run: bash scripts/tests/test-registry-fails-closed.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-active-registry leadv2-fanout

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

# REGISTRY_SH lets the negative control point the whole suite at a mutated
# copy without touching the production file.
REGISTRY_SH="${REGISTRY_SH:-${SCRIPT_DIR}/../leadv2-active-registry.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

_new_sandbox() {
  local d
  d="$(lv2_mktemp_dir "regfc-test")"
  mkdir -p "${d}/proj" "${d}/state"
  printf -- '%s' "$d"
}

_row_count() { # <yaml_file> -> session row count, or __NO_FILE__
  python3 -c '
import sys, yaml
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = yaml.safe_load(f) or {}
    print(len(d.get("sessions") or []))
except FileNotFoundError:
    print("__NO_FILE__")
' "$1"
}

# _run <sandbox> <errfile> <snippet>: source the registry under the sandbox
# env and execute the snippet (no -e inside: a fail-closed rc must stay
# observable). stdout returns to the caller; stderr collects into <errfile>.
_run() {
  local sb="$1" errf="$2" snippet="$3"
  LEADV2_PROJECT_ROOT="${sb}/proj" LEADV2_STATE_ROOT="${sb}/state" \
    bash -c '
      set -uo pipefail
      source "'"$REGISTRY_SH"'"
      '"$snippet"'
    ' 2>"$errf"
}

_get() { # <out> <KEY> -> value of the last `KEY=…` line
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1
}

test_1_unregister_unknown_tid() {
  log "test_1: unregister of an unknown task_id -> rc 4, bytes untouched, stderr reports 0 rows"
  local sb errf out rc unch
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_register "REGFC-T1" "Standard" "$LEADV2_PROJECT_ROOT" "regfc-branch" "false" >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"
    cp "$yaml" "$yaml.snap"
    leadv2_active_unregister "REGFC-NOPE" >/dev/null
    echo "RC=$?"
    cmp -s "$yaml" "$yaml.snap" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')" || true
  rc="$(_get "$out" RC)"; unch="$(_get "$out" UNCHANGED)"
  if [[ "$rc" == "4" && "$unch" == "yes" ]] && grep -q 'unregistered 0 row(s)' "$errf"; then
    pass "test_1: rc=4, bytes unchanged, stderr 'unregistered 0 row(s)'"
  else
    fail "test_1: rc='${rc}' unchanged='${unch}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

test_2_set_worktree_bad_target() {
  log "test_2: set_worktree unknown tid -> rc 4; not-a-directory -> rc 2; bytes untouched"
  local sb errf out rca rcb unch
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_register "REGFC-T1" "Standard" "$LEADV2_PROJECT_ROOT" "regfc-branch" "false" >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"
    cp "$yaml" "$yaml.snap"
    leadv2_active_set_worktree "REGFC-NOPE" "$LEADV2_PROJECT_ROOT" >/dev/null
    echo "RCA=$?"
    leadv2_active_set_worktree "REGFC-T1" "$LEADV2_PROJECT_ROOT/no-such-dir" >/dev/null
    echo "RCB=$?"
    cmp -s "$yaml" "$yaml.snap" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')" || true
  rca="$(_get "$out" RCA)"; rcb="$(_get "$out" RCB)"; unch="$(_get "$out" UNCHANGED)"
  if [[ "$rca" == "4" && "$rcb" == "2" && "$unch" == "yes" ]] \
     && grep -q 'set_worktree: task not registered' "$errf" \
     && grep -q 'set_worktree: not a directory' "$errf"; then
    pass "test_2: unknown tid rc=4, not-a-dir rc=2, bytes unchanged, both stderr lines"
  else
    fail "test_2: rca='${rca}' rcb='${rcb}' unchanged='${unch}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

test_3_update_phase_missing_file() {
  log "test_3: update_phase with NO active.yaml -> rc 4, file never created; legacy 1-arg without LEADV2_TASK_ID -> non-zero"
  local sb errf out rc nofile legacy_rc=0
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_update_phase "REGFC-T1" "implement" >/dev/null
    echo "RC=$?"
    yaml="$(_leadv2_yaml_file)"
    [[ ! -e "$yaml" ]] && echo "NOFILE=yes" || echo "NOFILE=no"
  ')" || true
  rc="$(_get "$out" RC)"; nofile="$(_get "$out" NOFILE)"
  LEADV2_PROJECT_ROOT="${sb}/proj" LEADV2_STATE_ROOT="${sb}/state" \
    env -u LEADV2_TASK_ID bash -c '
      source "'"$REGISTRY_SH"'"
      leadv2_active_update_phase "implement"
    ' >/dev/null 2>&1 || legacy_rc=$?
  if [[ "$rc" == "4" && "$nofile" == "yes" && "$legacy_rc" -ne 0 ]] \
     && grep -q 'registry: active.yaml missing at' "$errf"; then
    pass "test_3: rc=4, no file materialised, legacy form rc=${legacy_rc}, stderr 'active.yaml missing'"
  else
    fail "test_3: rc='${rc}' nofile='${nofile}' legacy_rc='${legacy_rc}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

test_4_update_pulse_unknown_tid() {
  log "test_4: update_pulse of an unknown task_id -> rc 4, bytes untouched"
  local sb errf out rc unch
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_register "REGFC-T1" "Standard" "$LEADV2_PROJECT_ROOT" "regfc-branch" "false" >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"
    cp "$yaml" "$yaml.snap"
    leadv2_active_update_pulse "REGFC-NOPE" >/dev/null
    echo "RC=$?"
    cmp -s "$yaml" "$yaml.snap" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')" || true
  rc="$(_get "$out" RC)"; unch="$(_get "$out" UNCHANGED)"
  if [[ "$rc" == "4" && "$unch" == "yes" ]] && grep -q 'update_pulse: task not registered' "$errf"; then
    pass "test_4: rc=4, bytes unchanged, stderr 'update_pulse: task not registered'"
  else
    fail "test_4: rc='${rc}' unchanged='${unch}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

test_5_set_worker_pid_unknown_tid() {
  log "test_5: set_worker_pid of an unknown task_id -> rc 4, no row created"
  local sb errf out rc unch rows
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_register "REGFC-T1" "Standard" "$LEADV2_PROJECT_ROOT" "regfc-branch" "false" >/dev/null 2>&1
    yaml="$(_leadv2_yaml_file)"
    echo "YAML=$yaml"
    cp "$yaml" "$yaml.snap"
    leadv2_active_set_worker_pid "REGFC-NOPE" "12345" "2026-09-09T00:00:00Z" "worker" >/dev/null
    echo "RC=$?"
    cmp -s "$yaml" "$yaml.snap" && echo "UNCHANGED=yes" || echo "UNCHANGED=no"
  ')" || true
  rc="$(_get "$out" RC)"; unch="$(_get "$out" UNCHANGED)"
  rows="$(_row_count "$(_get "$out" YAML)")"
  if [[ "$rc" == "4" && "$unch" == "yes" && "$rows" == "1" ]] \
     && grep -q 'set_worker_pid: task not registered' "$errf"; then
    pass "test_5: rc=4, bytes unchanged, still 1 row, stderr 'set_worker_pid: task not registered'"
  else
    fail "test_5: rc='${rc}' unchanged='${unch}' rows='${rows}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

test_6_unregister_missing_file() {
  log "test_6: unregister with NO active.yaml -> rc 4, file never created, no render"
  local sb errf out rc nofile
  sb="$(_new_sandbox)"; errf="${sb}/err.log"
  out="$(_run "$sb" "$errf" '
    leadv2_active_unregister "REGFC-T1" >/dev/null
    echo "RC=$?"
    yaml="$(_leadv2_yaml_file)"
    [[ ! -e "$yaml" ]] && echo "NOFILE=yes" || echo "NOFILE=no"
  ')" || true
  rc="$(_get "$out" RC)"; nofile="$(_get "$out" NOFILE)"
  if [[ "$rc" == "4" && "$nofile" == "yes" ]] && grep -q 'registry: active.yaml missing at' "$errf"; then
    pass "test_6: rc=4, no file materialised, stderr 'active.yaml missing'"
  else
    fail "test_6: rc='${rc}' nofile='${nofile}' stderr='$(head -c 200 "$errf" 2>/dev/null)'"
  fi
  rm -rf "$sb"
}

main() {
  log "=== leadv2-active-registry.sh fail-closed tests (WAVE0-REGISTRY-FAILS-OPEN-01) ==="
  log "Registry: ${REGISTRY_SH}"
  test_1_unregister_unknown_tid
  test_2_set_worktree_bad_target
  test_3_update_phase_missing_file
  test_4_update_pulse_unknown_tid
  test_5_set_worker_pid_unknown_tid
  test_6_unregister_missing_file
  log ""
  log "=== Results: PASS=${PASS} FAIL=${FAIL} ==="
  if [[ "$FAIL" -eq 0 ]]; then
    log "All tests passed."
  else
    for e in "${ERRORS[@]}"; do log "$e"; done
    exit 1
  fi
}

main "$@"
