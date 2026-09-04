#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: run-core-offline.sh
# test-suite-lock-scope.sh — SUITE-LOCK-ORPHAN-FD-04
#
# Exercises the ACTUAL production lock section of run-core-offline.sh (never
# a reimplementation) against fixture repo roots and a fixture lock dir --
# never /tmp/leadv2-core-offline*.lock, never a real lane. Each fixture root
# is a throwaway git repo with a symlink to the real run-core-offline.sh (the
# same shape persona-engine/m3-market/respiro-ios already use), so REPO_ROOT
# resolution and the per-root slug run exactly as they do in production.
#
# Case 7 is a mutation/negative control: it edits the real production line
# in-place (LEADV2_SUITE_LOCK_FILE default), re-proves case 1 goes red, then
# restores the file byte-for-byte from a pre-mutation backup before this
# script exits (trap-guarded, so a crash mid-mutation never leaves the
# production file altered).

set -euo pipefail

# --- SUITE-LOCK-ORPHAN-FD-04 round 4: hermetic against inherited lock knobs
# This suite's subject IS the lock; an inherited LEADV2_SUITE_LOCK_DISABLE=1
# makes the runner skip its lock section entirely, so every lock-holding
# assertion (cases 2/4/6/7-RED) fails for a reason that has nothing to do
# with the code under test (measured 2026-09-01: pass=8 fail=4 under an
# inherited kill-switch, pass=12 fail=0 without it). Scrub the knobs here;
# case 5 re-applies the kill-switch per-run via `env`, so the kill-switch
# itself stays covered. run-core-offline.sh already scrubs LEADV2_* for its
# inner suites; this guard covers direct invocation, where the lead's
# round-4 measurement was burned.
if [[ -n "${LEADV2_SUITE_LOCK_DISABLE:-}" || -n "${LEADV2_SUITE_LOCK_WAIT_S:-}" \
      || -n "${LEADV2_SUITE_LOCK_FILE:-}" ]]; then
  printf -- '[LOCK-SCOPE] NOTE: scrubbing inherited lock knobs (DISABLE=%s WAIT_S=%s FILE=%s) -- cases set their own per-run\n' \
    "${LEADV2_SUITE_LOCK_DISABLE:-}" "${LEADV2_SUITE_LOCK_WAIT_S:-}" "${LEADV2_SUITE_LOCK_FILE:-}" >&2
fi
unset LEADV2_SUITE_LOCK_DISABLE LEADV2_SUITE_LOCK_WAIT_S LEADV2_SUITE_LOCK_FILE

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER_REAL="$TEST_DIR/run-core-offline.sh"

pass=0
fail=0
cleanup_items=()
mutated=0
cleanup() {
  local item
  if [[ "$mutated" == "1" ]]; then
    cp -p "$RUNNER_REAL.lockscope-backup" "$RUNNER_REAL" 2>/dev/null || true
    mutated=0
  fi
  rm -f "$RUNNER_REAL.lockscope-backup" 2>/dev/null || true
  for item in "${cleanup_items[@]:-}"; do
    [ -n "$item" ] && rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

FIXTURE_BASE="$(mktemp -d "${TMPDIR:-/tmp}/lv2-suite-lock-scope.XXXXXX")"
cleanup_items+=("$FIXTURE_BASE")

check() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "[LOCK-SCOPE]   $desc OK"
    pass=$((pass + 1))
  else
    echo "[LOCK-SCOPE]   $desc FAILED"
    fail=$((fail + 1))
  fi
}

make_fixture_root() {
  local name="$1" root
  root="$FIXTURE_BASE/$name"
  mkdir -p "$root/plugins/leadv2/scripts/tests"
  ( cd "$root" && git init -q && git config user.email t@t.example && git config user.name t )
  ln -s "$RUNNER_REAL" "$root/plugins/leadv2/scripts/tests/run-core-offline.sh"
  printf '%s' "$root"
}

ROOT_A="$(make_fixture_root root-a)"
ROOT_B="$(make_fixture_root root-b)"
RUNNER_A="$ROOT_A/plugins/leadv2/scripts/tests/run-core-offline.sh"
RUNNER_B="$ROOT_B/plugins/leadv2/scripts/tests/run-core-offline.sh"

discover_default_path() {
  # LEADV2_SUITE_LOCK_FILE left unset -> production computes its own default
  # from REPO_ROOT. Extract it from the probe line instead of recomputing
  # the slug ourselves (recomputing would test our own logic, not theirs).
  local runner="$1" out
  out="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_PROBE=1 bash "$runner" 2>&1)"
  printf '%s' "$out" | sed -n 's/.*file=\(.*\)$/\1/p'
}

# ============================================================ case 1 / 7 ===
run_case_1() {
  local path_a path_b holder_pid out_a out_b ok
  path_a="$(discover_default_path "$RUNNER_A")"
  path_b="$(discover_default_path "$RUNNER_B")"
  rm -f "$path_a" "$path_b" 2>/dev/null || true

  ok=1
  [[ -n "$path_a" && -n "$path_b" && "$path_a" != "$path_b" ]] || ok=0
  check "case1: two different fixture roots resolve to two different lock files" "$ok"

  # Hold root A's own resolved file externally, then prove root B's run
  # (different root) proceeds without ever waiting.
  ( exec 9>"$path_a"; flock -x 9; sleep 3 ) &
  holder_pid=$!
  sleep 0.3

  out_b="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_WAIT_S=5 LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$RUNNER_B" 2>&1)"
  ok=1
  echo "$out_b" | grep -q 'waiting for lock' && ok=0
  echo "$out_b" | grep -q 'lock-probe acquired' || ok=0
  check "case1: root B proceeds immediately while root A's file is held" "$ok"

  wait "$holder_pid" 2>/dev/null || true
  rm -f "$path_a" "$path_b" 2>/dev/null || true
}

# ================================================================ case 2 ===
run_case_2() {
  local path_a holder_pid out rc
  path_a="$(discover_default_path "$RUNNER_A")"
  rm -f "$path_a" 2>/dev/null || true

  ( exec 9>"$path_a"; flock -x 9; sleep 2 ) &
  holder_pid=$!
  sleep 0.3

  if out="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_WAIT_S=5 LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$RUNNER_A" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  wait "$holder_pid" 2>/dev/null || true

  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  echo "$out" | grep -q 'waiting for lock' || ok=0
  echo "$out" | grep -q 'lock-probe acquired' || ok=0
  check "case2: same root -- second run waits for the holder, then proceeds" "$ok"
  rm -f "$path_a" 2>/dev/null || true
}

# ============================================================ case 3 =======
run_case_3() {
  local path_a spawn_log orphan_pid ok out
  path_a="$(discover_default_path "$RUNNER_A")"
  rm -f "$path_a" 2>/dev/null || true

  # The production run acquires the lock, forks a long-lived child, then
  # exits -- exactly the incident shape (a run killed right after a spawn).
  # Capture via a file, NOT `$(...)`: bash reaps/HUPs a command substitution
  # subshell's own background jobs when the subshell exits, which would kill
  # our simulated orphan before we ever got to check it -- a harness
  # artifact, not the thing under test.
  spawn_log="$FIXTURE_BASE/case3-spawn.log"
  env LEADV2_SUITE_LOCK_FILE="$path_a" LEADV2_SUITE_LOCK_ORPHAN_TEST_SLEEP_S=20 \
    bash "$RUNNER_A" >"$spawn_log" 2>&1
  orphan_pid="$(sed -n 's/.*pid=\([0-9]*\)$/\1/p' "$spawn_log")"

  sleep 0.3
  ok=1
  [[ -n "$orphan_pid" ]] && kill -0 "$orphan_pid" 2>/dev/null || ok=0
  check "case3: the orphan child is actually alive after its parent run exited" "$ok"

  if out="$(env LEADV2_SUITE_LOCK_FILE="$path_a" LEADV2_SUITE_LOCK_WAIT_S=2 \
    LEADV2_SUITE_LOCK_PROBE=1 bash "$RUNNER_A" 2>&1)"; then
    :
  fi
  ok=1
  echo "$out" | grep -q 'waiting for lock' && ok=0
  echo "$out" | grep -q 'lock-probe acquired' || ok=0
  check "case3: a fresh run acquires immediately despite the surviving orphan" "$ok"

  [[ -n "$orphan_pid" ]] && kill -9 "$orphan_pid" 2>/dev/null || true
  rm -f "$path_a" 2>/dev/null || true
}

# ================================================================ case 4 ===
run_case_4() {
  local path_a holder_pid out rc ok
  path_a="$(discover_default_path "$RUNNER_A")"
  rm -f "$path_a" 2>/dev/null || true

  # Pre-seed a realistic holder diagnostic (same format the production
  # script itself writes) so the FATAL line under test has real holder/age
  # content to report, not an external holder's silence.
  ( exec 9>"$path_a"; flock -x 9
    printf 'pid=%s host=faketest since=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$path_a"
    sleep 5
  ) &
  holder_pid=$!
  sleep 0.3

  if out="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_WAIT_S=1 LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$RUNNER_A" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true

  ok=1
  [[ "$rc" -ne 0 ]] || ok=0
  echo "$out" | grep -q "FATAL lock_timeout file=$path_a" || ok=0
  echo "$out" | grep -q 'holder=pid=' || ok=0
  echo "$out" | grep -qE 'since=[0-9T:-]+Z' || ok=0
  check "case4: budget exhausted -> non-zero exit naming file, holder and age" "$ok"
  rm -f "$path_a" 2>/dev/null || true
}

# ================================================================ case 5 ===
run_case_5() {
  local path_a holder_pid out rc ok
  path_a="$(discover_default_path "$RUNNER_A")"
  rm -f "$path_a" 2>/dev/null || true

  ( exec 9>"$path_a"; flock -x 9; sleep 2 ) &
  holder_pid=$!
  sleep 0.3

  if out="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_DISABLE=1 LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$RUNNER_A" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  wait "$holder_pid" 2>/dev/null || true

  ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  echo "$out" | grep -q 'waiting for lock' && ok=0
  echo "$out" | grep -q 'lock-probe acquired' || ok=0
  check "case5: LEADV2_SUITE_LOCK_DISABLE=1 bypasses a held lock entirely" "$ok"
  rm -f "$path_a" 2>/dev/null || true
}

# ================================================================ case 6 ===
run_case_6() {
  local override_path holder_pid out rc ok
  override_path="$FIXTURE_BASE/explicit-override.lock"
  rm -f "$override_path" 2>/dev/null || true

  ( exec 9>"$override_path"; flock -x 9; sleep 2 ) &
  holder_pid=$!
  sleep 0.3

  if out="$(env LEADV2_SUITE_LOCK_FILE="$override_path" LEADV2_SUITE_LOCK_WAIT_S=5 \
    LEADV2_SUITE_LOCK_PROBE=1 bash "$RUNNER_A" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  wait "$holder_pid" 2>/dev/null || true

  ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  echo "$out" | grep -q "waiting for lock file=$override_path" || ok=0
  check "case6: LEADV2_SUITE_LOCK_FILE override still wins over the default" "$ok"
  rm -f "$override_path" 2>/dev/null || true
}

echo "[LOCK-SCOPE] case 1: different fixture roots never block each other"
run_case_1
echo "[LOCK-SCOPE] case 2: same root serializes"
run_case_2
echo "[LOCK-SCOPE] case 3: an orphaned child never holds the lock"
run_case_3
echo "[LOCK-SCOPE] case 4: exhausted wait budget fails loudly"
run_case_4
echo "[LOCK-SCOPE] case 5: LEADV2_SUITE_LOCK_DISABLE kill-switch"
run_case_5
echo "[LOCK-SCOPE] case 6: LEADV2_SUITE_LOCK_FILE override regression guard"
run_case_6

echo "[LOCK-SCOPE] case 7: mutation control -- restore the machine-wide literal"
cp -p "$RUNNER_REAL" "$RUNNER_REAL.lockscope-backup"
mutated=1
sed -i.bak \
  's#^LEADV2_SUITE_LOCK_FILE="\${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline-\$(_core_offline_lock_slug "\$REPO_ROOT")\.lock}"$#LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline.lock}"#' \
  "$RUNNER_REAL"
rm -f "$RUNNER_REAL.bak"
if ! grep -q '_core_offline_lock_slug "\$REPO_ROOT"' "$RUNNER_REAL"; then
  echo "[LOCK-SCOPE]   mutation applied (default is now the machine-wide literal)"
else
  echo "[LOCK-SCOPE]   FAILED: mutation sed did not match -- case 7 cannot run"
  fail=$((fail + 1))
fi

path_a_mut="$(discover_default_path "$RUNNER_A")"
path_b_mut="$(discover_default_path "$RUNNER_B")"
ok=1
[[ "$path_a_mut" == "$path_b_mut" ]] || ok=0
check "case7 RED-pre: under the mutation, two different roots collide on one file" "$ok"

# The required negative control is behavioral, not just a path equality: run
# the exact case-1 scenario under the mutation and prove it FAILS there.
ok=1
( exec 9>"$path_a_mut"; flock -x 9; sleep 3 ) &
holder_pid=$!
sleep 0.3
if out_mut="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_WAIT_S=1 LEADV2_SUITE_LOCK_PROBE=1 \
  bash "$RUNNER_B" 2>&1)"; then
  rc_mut=0
else
  rc_mut=$?
fi
kill "$holder_pid" 2>/dev/null || true
wait "$holder_pid" 2>/dev/null || true
[[ "$rc_mut" -ne 0 ]] || ok=0
echo "$out_mut" | grep -q "FATAL lock_timeout file=$path_a_mut" || ok=0
check "case7 RED: with the machine-wide literal restored, the case-1 scenario FAILS (rc=$rc_mut)" "$ok"

cp -p "$RUNNER_REAL.lockscope-backup" "$RUNNER_REAL"
mutated=0
rm -f "$RUNNER_REAL.lockscope-backup"
path_a_fixed="$(discover_default_path "$RUNNER_A")"
path_b_fixed="$(discover_default_path "$RUNNER_B")"
ok=1
[[ -n "$path_a_fixed" && -n "$path_b_fixed" && "$path_a_fixed" != "$path_b_fixed" ]] || ok=0
check "case7 GREEN: reverted -- two different roots resolve to two different files again" "$ok"

# Same scenario after revert must succeed again, or the RED meant nothing.
if out_fixed="$(env -u LEADV2_SUITE_LOCK_FILE LEADV2_SUITE_LOCK_WAIT_S=5 LEADV2_SUITE_LOCK_PROBE=1 \
  bash "$RUNNER_B" 2>&1)"; then
  rc_fixed=0
else
  rc_fixed=$?
fi
ok=1
[[ "$rc_fixed" -eq 0 ]] || ok=0
echo "$out_fixed" | grep -q 'lock-probe acquired' || ok=0
check "case7 GREEN: reverted -- the case-1 scenario passes again (rc=$rc_fixed)" "$ok"
rm -f "$path_a_mut" "$path_b_mut" "$path_a_fixed" "$path_b_fixed" 2>/dev/null || true

echo "[LOCK-SCOPE] pass=$pass fail=$fail"
# Exit contract (round-4 Critical 1): CI keys off THIS status, never off the
# printed lines. fail>0 => exit 1, regardless of what was echoed.
(( fail == 0 )) || exit 1
exit 0
