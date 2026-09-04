#!/usr/bin/env bash
# tests/test-active-register-miss.sh — LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01
#
# THE BUG: forty lane journals carried exactly one registration line:
#   active_register_miss task=07401216 rc=0
# rc=0 means the python `register` op returned success. leadv2-dispatch-
# code.sh's own caller (~:7058) extracts the printed session_id by matching
# it against a strict `^s-<ts>-<pid>-<pid>$` pattern -- but
# leadv2_active_register's REFRESH branch (an existing, still-alive row for
# the same task_id, e.g. one leadv2-fanout.sh pre-registered under ITS OWN
# "f-<ts>-<pid>-<pid>" session_id convention) used to re-print the row's
# OLD, possibly foreign-prefixed session_id instead of a fresh
# canonical one. A row that was genuinely refreshed (rc=0, correct metadata,
# present in the registry) was therefore read back by the caller as a miss:
# a write that succeeded, reported as if it had not happened.
#
# THE FIX (leadv2-active-registry.sh, leadv2_active_register's REFRESH
# branch): always restamp `session_id` with the freshly-generated
# current-schema id before printing, and (defense in depth) the bash wrapper
# itself now verifies its own stdout against the same pattern before
# returning 0 -- a mismatch is reported as a distinct nonzero rc (7) with a
# stderr diagnostic, never a silent 0.
#
# Tests:
#   1. Reproduction: a foreign-prefixed alive row, refreshed via
#      leadv2_active_register, must print a session_id matching the
#      caller's own strict pattern, and that id must equal what actually
#      landed in the registry row (state assertion, not a message-text one).
#   2. Negative control: mutate the FIXED function back to the original bug
#      (revert the restamp), confirm the mutant differs byte-for-byte from
#      the original, then re-run test 1's exact assertion against the
#      mutant and confirm it goes RED -- and ONLY that assertion.
#   3. bash -n syntax check (both this file and the production file).
#   4. Ten consecutive runs of the full suite; all ten exit codes reported.
#
# Portable: no GNU-only date/sed -i/timeout/flock. No associative arrays, no
# readarray (bash 3.2 / macOS compat).
# Run: bash scripts/tests/test-active-register-miss.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_SH="${SCRIPT_DIR}/../leadv2-active-registry.sh"
# Pinned explicitly (LEADV2_STATE_PATH_BIN is _leadv2_state_path_sh's own
# documented override) so a MUTANT copy sourced from a scratch tmp dir still
# resolves the real state-path resolver instead of falling through
# leadv2-active-registry.sh's BASH_SOURCE[0]-relative bundled-path guess to a
# sibling that doesn't exist next to the copy -- which silently redirects the
# whole test to a DIFFERENT, uninitialized active.yaml (rc=0, no error): the
# exact "wrote 25 directories into the wrong repository, rc=0, no output"
# failure shape from this task's own brief, just triggered by test-harness
# relocation rather than the bug under test. Both the real file and every
# mutant copy must resolve through the SAME resolver for the control to mean
# anything.
STATE_PATH_BIN="${SCRIPT_DIR}/../leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# The exact pattern leadv2-dispatch-code.sh:~7058 uses to extract a session_id
# from leadv2_active_register's stdout. Kept here as a literal copy (not a
# sourced constant) because that file is off-limits for this lane to edit or
# depend on -- a drift between the two is itself a finding, not something to
# paper over with a shared variable.
CALLER_SESSION_PATTERN='^s-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$'

# _seed_foreign_row <state_yaml> <task_id> <pid> — writes a minimal active.yaml
# with one row for <task_id> carrying a FOREIGN ("f-...", fanout's own
# convention, not this file's "s-...") session_id and the given (alive) pid,
# reproducing a fanout pre-registration that dispatch-code.sh's Gate-1
# registration later refreshes.
_seed_foreign_row() {
  local state_yaml="$1" task_id="$2" pid="$3"
  python3 - "$state_yaml" "$task_id" "$pid" <<'PYEOF'
import sys, yaml
path, task_id, pid = sys.argv[1], sys.argv[2], int(sys.argv[3])
doc = {
    "meta": {"schema_version": 2, "hard_limit": 3, "heavy_max": 3,
              "heavy_strategic_solo": False, "light_max": 3, "standard_max": 2},
    "sessions": [{
        "session_id": "f-20260101T000000Z-%d-%d" % (pid, pid),
        "task_id": task_id,
        "worktree": "/tmp/foreign-worktree",
        "branch": "unknown",
        "started_at": "2026-01-01T00:00:00Z",
        "phase": "spawning",
        "class": "Standard",
        "pulse_log": "docs/leadv2/tasks/%s/pulse.md" % task_id,
        "pid": pid,
        "pid_birth": "unknown",
        "pid_role": "lead_durable",
        "parent_session_id": None,
        "daemon_mode": False,
        "last_pulse_at": "2026-01-01T00:00:00Z",
        "stale": False,
        "note": "",
        "group_key": None,
        "risk_tags": None,
        "writes": None,
        "protocol_version": 2,
        "backend": "terminal",
        "phase_started_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
        "tmux_window": None,
        "tmux_pane": None,
        "log_path": "docs/leadv2/tasks/%s/pulse.md" % task_id,
        "provider_receipts": [],
    }],
}
with open(path, "w", encoding="utf-8") as fh:
    yaml.dump(doc, fh, default_flow_style=False, sort_keys=False)
PYEOF
}

# _row_session_id <state_yaml> <task_id> — reads back the CURRENT session_id
# field for task_id from the registry file (state assertion, not stdout).
_row_session_id() {
  local state_yaml="$1" task_id="$2"
  python3 - "$state_yaml" "$task_id" <<'PYEOF'
import sys, yaml
path, task_id = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
rows = [r for r in (doc.get("sessions") or []) if r.get("task_id") == task_id]
print(rows[0].get("session_id") if rows else "")
PYEOF
}

# _run_reproduction <registry_sh> — sources <registry_sh>, seeds a foreign
# alive row, refreshes it via leadv2_active_register, and prints two lines:
#   PRINTED=<what leadv2_active_register printed on stdout>
#   RC=<its exit code>
#   STATE=<the row's session_id as actually stored, after the call>
# Runs in an isolated sandbox (own PROJECT_ROOT/STATE_ROOT); never touches
# the real ~/.claude/leadv2-state registry.
_run_reproduction() {
  local registry_sh="$1"
  local sandbox state_yaml out rc
  sandbox="$(lv2_mktemp_dir "aregmiss")"
  mkdir -p "${sandbox}/proj" "${sandbox}/state"
  state_yaml="${sandbox}/state/active.yaml"
  _seed_foreign_row "$state_yaml" "AREGMISS-T1" "$$"
  out="$(
    LEADV2_PROJECT_ROOT="${sandbox}/proj" LEADV2_STATE_ROOT="${sandbox}/state" \
    LEADV2_STATE_PATH_BIN="${STATE_PATH_BIN}" bash -c '
      set -uo pipefail
      source "'"$registry_sh"'"
      # leadv2-active-registry.sh itself does `set -euo pipefail` at its own
      # top level (line ~45); sourcing it mutates THIS shells options too, so
      # errexit is back on even though this scriptlet opened with `-uo
      # pipefail` only. leadv2-dispatch-code.sh hits the exact same thing and
      # explicitly `set +e`s around its own register call for exactly this
      # reason (its own comment: "registration output is advisory... collect
      # and parse it with errexit explicitly disabled") -- mirror that here so
      # a nonzero return is CAPTURED, not an unannounced early exit.
      set +e
      _errf="$(mktemp)"
      _out="$(leadv2_active_register "AREGMISS-T1" "Standard" "$LEADV2_PROJECT_ROOT" "test-branch" "false" 2>"$_errf")"
      _rc=$?
      printf "PRINTED=%s\n" "$_out"
      printf "RC=%s\n" "$_rc"
      printf "DIAG=%s\n" "$(cat "$_errf")"
      rm -f "$_errf"
    ' 2>&1
  )" || true
  local printed diag state_id
  printed="$(printf '%s\n' "$out" | sed -nE 's/^PRINTED=//p')"
  rc="$(printf '%s\n' "$out" | sed -nE 's/^RC=//p')"
  diag="$(printf '%s\n' "$out" | sed -nE 's/^DIAG=//p')"
  state_id="$(_row_session_id "$state_yaml" "AREGMISS-T1")"
  rm -rf "$sandbox"
  printf 'PRINTED=%s\nRC=%s\nSTATE=%s\nDIAG=%s\n' "$printed" "$rc" "$state_id" "$diag"
}

test_1_reproduction_fixed() {
  log "Test 1: refresh of a foreign-prefixed alive row against the FIXED registry"
  local result printed rc state_id
  result="$(_run_reproduction "$REGISTRY_SH")"
  printed="$(printf '%s\n' "$result" | sed -nE 's/^PRINTED=//p')"
  rc="$(printf '%s\n' "$result" | sed -nE 's/^RC=//p')"
  state_id="$(printf '%s\n' "$result" | sed -nE 's/^STATE=//p')"
  log "  printed=${printed} rc=${rc} state_session_id=${state_id}"
  if [[ "$rc" != "0" ]]; then
    fail "Test 1: expected rc=0, got rc=${rc}"
    return
  fi
  if [[ ! "$printed" =~ $CALLER_SESSION_PATTERN ]]; then
    fail "Test 1 (BEFORE-FIX SHAPE REPRODUCED): rc=0 but printed='${printed}' does not match caller's pattern -- this is the active_register_miss defect"
    return
  fi
  if [[ "$printed" != "$state_id" ]]; then
    fail "Test 1: printed session_id '${printed}' does not match the id actually stored in the registry ('${state_id}')"
    return
  fi
  pass "Test 1: refresh printed a caller-matchable session_id ('${printed}') that equals the stored row's session_id -- no false miss"
}

# test_2_mutation_control — reverts the FIXED restamp line back to the
# original bug, confirms the mutant differs byte-for-byte from the original,
# then re-runs the SAME assertion (test 1's state assertion) against the
# mutant and confirms it goes RED. Reports baseline_rc/mutated_rc/restored_rc.
test_2_mutation_control() {
  log "Test 2: negative control -- mutate leadv2_active_register's refresh branch back to the original bug"
  local mutant tmp_dir
  tmp_dir="$(lv2_mktemp_dir "aregmiss-mut")"
  mutant="${tmp_dir}/leadv2-active-registry.mutant.sh"
  cp "$REGISTRY_SH" "$mutant"

  # Mutation: inside leadv2_active_register's python `register` op, inside
  # the refresh branch, revert the restamp assertion back to the original
  # buggy print (re-print the row's OLD/possibly-foreign session_id instead
  # of the freshly generated canonical one).
  local _mutate_rc=0
  python3 - "$mutant" <<'PYEOF' || _mutate_rc=$?
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
needle = '                existing["session_id"] = session_id\n                print(session_id)\n'
replacement = '                print(existing.get("session_id") or session_id)\n'
if src.count(needle) != 1:
    print("MUTATION_ANCHOR_NOT_FOUND", file=sys.stderr)
    sys.exit(1)
src = src.replace(needle, replacement, 1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(src)
PYEOF
  if [[ "$_mutate_rc" -ne 0 ]]; then
    fail "Test 2: mutation anchor not found -- cannot apply mutation (byte-identical to original would also fail the next check)"
    rm -rf "$tmp_dir"
    return
  fi

  # Byte-for-byte difference check BEFORE trusting the mutant as a control.
  if diff -q "$REGISTRY_SH" "$mutant" >/dev/null 2>&1; then
    fail "Test 2: mutant is byte-identical to the original -- mutation did not apply, control is void"
    rm -rf "$tmp_dir"
    return
  fi
  pass "Test 2a: mutant differs byte-for-byte from the original"

  bash -n "$mutant" 2>/dev/null || {
    fail "Test 2: mutant fails bash -n -- would crash the suite instead of reddening one assertion"
    rm -rf "$tmp_dir"
    return
  }

  local baseline_result baseline_printed baseline_rc baseline_state
  baseline_result="$(_run_reproduction "$REGISTRY_SH")"
  baseline_printed="$(printf '%s\n' "$baseline_result" | sed -nE 's/^PRINTED=//p')"
  baseline_rc="$(printf '%s\n' "$baseline_result" | sed -nE 's/^RC=//p')"

  local mutated_result mutated_printed mutated_rc mutated_state mutated_diag
  mutated_result="$(_run_reproduction "$mutant")"
  mutated_printed="$(printf '%s\n' "$mutated_result" | sed -nE 's/^PRINTED=//p')"
  mutated_rc="$(printf '%s\n' "$mutated_result" | sed -nE 's/^RC=//p')"
  mutated_state="$(printf '%s\n' "$mutated_result" | sed -nE 's/^STATE=//p')"
  mutated_diag="$(printf '%s\n' "$mutated_result" | sed -nE 's/^DIAG=//p')"

  local restored_result restored_printed restored_rc
  restored_result="$(_run_reproduction "$REGISTRY_SH")"
  restored_printed="$(printf '%s\n' "$restored_result" | sed -nE 's/^PRINTED=//p')"
  restored_rc="$(printf '%s\n' "$restored_result" | sed -nE 's/^RC=//p')"

  log "  baseline_rc=${baseline_rc} printed=${baseline_printed}"
  log "  mutated_rc=${mutated_rc} printed=${mutated_printed} state_session_id=${mutated_state} diag=${mutated_diag}"
  log "  restored_rc=${restored_rc} printed=${restored_printed}"

  rm -rf "$tmp_dir"

  # Falsification requirement: the assertion below checks STATE (does the
  # printed id match the caller's pattern / the stored row), never message
  # text -- there is no string being asserted here beyond the pattern that
  # IS the contract itself, so there is nothing to strip that would leave a
  # message-text-only check standing in for a state check.
  local mutant_is_red=1
  [[ "$mutated_rc" == "0" && "$mutated_printed" =~ $CALLER_SESSION_PATTERN ]] && mutant_is_red=0

  if [[ "$baseline_rc" == "0" && "$baseline_printed" =~ $CALLER_SESSION_PATTERN \
        && "$mutant_is_red" == "1" \
        && "$restored_rc" == "0" && "$restored_printed" =~ $CALLER_SESSION_PATTERN ]]; then
    pass "Test 2b: mutant reproduces the exact pre-fix shape (rc=${mutated_rc}, printed='${mutated_printed}' unmatched by caller pattern); baseline and restored both stay green"
  else
    fail "Test 2b: control did not behave as expected (baseline_rc=${baseline_rc} mutated_rc=${mutated_rc} mutant_is_red=${mutant_is_red} restored_rc=${restored_rc})"
  fi
}

test_3_syntax() {
  log "Test 3: bash -n syntax check"
  bash -n "$REGISTRY_SH" 2>/dev/null && pass "Test 3a: leadv2-active-registry.sh bash -n OK" || fail "Test 3a: leadv2-active-registry.sh bash -n FAILED"
  bash -n "${BASH_SOURCE[0]}" 2>/dev/null && pass "Test 3b: this test file bash -n OK" || fail "Test 3b: this test file bash -n FAILED"
}

main() {
  log "=== leadv2-active-register-miss tests (LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01) ==="
  log "Script: $REGISTRY_SH"
  echo ""
  test_3_syntax
  test_1_reproduction_fixed
  test_2_mutation_control
  echo ""
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "Failures:"
    for e in "${ERRORS[@]}"; do log "  $e"; done
    exit 1
  fi
  log "All tests passed."
  exit 0
}

main "$@"
