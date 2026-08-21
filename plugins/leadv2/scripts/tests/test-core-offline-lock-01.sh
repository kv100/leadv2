#!/usr/bin/env bash
# test-core-offline-lock-01.sh — SUITE-SPEED-01 item 1
# Verifies run-core-offline.sh takes an exclusive flock before running suites:
#   (a) a held lock blocks a second run until released (LEADV2_SUITE_LOCK_WAIT_S)
#   (b) an unreleased lock past the wait budget is a bounded, journaled failure
#   (c) LEADV2_SUITE_LOCK_DISABLE=1 is a real bypass
#
# Uses LEADV2_SUITE_LOCK_PROBE=1 so each case acquires-then-exits instead of
# running the full 57-suite offline batch — the lock behaviour under test does
# not depend on what runs after acquisition.

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER="$TEST_DIR/run-core-offline.sh"

pass=0
fail=0
cleanup_items=()
cleanup() {
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

LOCK_FILE="$(mktemp -u "${TMPDIR:-/tmp}/lv2-lock-test.XXXXXX")"
cleanup_items+=("$LOCK_FILE")

# --- case (a)+(b): hold the lock externally, verify a bounded wait times out --
echo "[LOCK-01] case (a)/(b): held lock -> bounded wait times out"
(
  exec 9>"$LOCK_FILE"
  flock -x 9
  sleep 3
) &
holder_pid=$!
sleep 0.3 # let the holder actually acquire before we race it

if out_timeout="$(env LEADV2_SUITE_LOCK_FILE="$LOCK_FILE" LEADV2_SUITE_LOCK_WAIT_S=1 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$RUNNER" 2>&1)"; then
  rc_timeout=0
else
  rc_timeout=$?
fi
wait "$holder_pid" 2>/dev/null || true

if [[ "$rc_timeout" -ne 0 ]] && echo "$out_timeout" | grep -q 'waiting for lock' \
  && echo "$out_timeout" | grep -q 'FATAL lock_timeout'; then
  echo "[LOCK-01]   (a)/(b) bounded wait times out with journaled lines ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-01]   (a)/(b) FAILED rc=$rc_timeout out=<<<$out_timeout>>>"
  fail=$((fail + 1))
fi

# --- case (c): a long-enough wait succeeds once the holder releases ----------
echo "[LOCK-01] case (c): wait long enough to outlast the holder"
(
  exec 9>"$LOCK_FILE"
  flock -x 9
  sleep 2
) &
holder_pid=$!
sleep 0.3

start_ts=$(date +%s)
if out_wait="$(env LEADV2_SUITE_LOCK_FILE="$LOCK_FILE" LEADV2_SUITE_LOCK_WAIT_S=10 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$RUNNER" 2>&1)"; then
  rc_wait=0
else
  rc_wait=$?
fi
end_ts=$(date +%s)
wait "$holder_pid" 2>/dev/null || true

if [[ "$rc_wait" -eq 0 ]] && echo "$out_wait" | grep -q 'waiting for lock' \
  && echo "$out_wait" | grep -q 'lock-probe acquired'; then
  echo "[LOCK-01]   (c) waited then acquired ✓ (elapsed $((end_ts - start_ts))s)"
  pass=$((pass + 1))
else
  echo "[LOCK-01]   (c) FAILED rc=$rc_wait out=<<<$out_wait>>>"
  fail=$((fail + 1))
fi

# --- case (d): LEADV2_SUITE_LOCK_DISABLE=1 bypasses the lock entirely --------
echo "[LOCK-01] case (d): kill-switch bypasses a held lock"
(
  exec 9>"$LOCK_FILE"
  flock -x 9
  sleep 2
) &
holder_pid=$!
sleep 0.3

if out_bypass="$(env LEADV2_SUITE_LOCK_FILE="$LOCK_FILE" LEADV2_SUITE_LOCK_DISABLE=1 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$RUNNER" 2>&1)"; then
  rc_bypass=0
else
  rc_bypass=$?
fi
wait "$holder_pid" 2>/dev/null || true

if [[ "$rc_bypass" -eq 0 ]] && ! echo "$out_bypass" | grep -q 'waiting for lock' \
  && echo "$out_bypass" | grep -q 'lock-probe acquired'; then
  echo "[LOCK-01]   (d) kill-switch bypassed the held lock ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-01]   (d) FAILED rc=$rc_bypass out=<<<$out_bypass>>>"
  fail=$((fail + 1))
fi

echo "[LOCK-01] pass=$pass fail=$fail"
(( fail == 0 ))
