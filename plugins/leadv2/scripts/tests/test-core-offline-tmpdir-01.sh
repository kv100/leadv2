#!/usr/bin/env bash
# test-core-offline-tmpdir-01.sh — SUITE-SPEED-01 item 2
# Verifies run-core-offline.sh's run_check gives each "bash <suite>" invocation
# a private TMPDIR (mktemp -d per suite, exported), so fixture roots that
# resolve from ${TMPDIR:-/tmp} (test-stop-gate.sh, test-no-work-terminal.sh,
# test-report-only-gate.sh all do) never collide with a sibling suite's roots
# in the same run, nor with the caller's own TMPDIR.
#
# Runs the real runner against two tiny probe "suites" wired in via
# LEADV2_SUITE_DEFS_OVERRIDE so no real (slow) suite has to execute.

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

CALLER_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/lv2-caller-tmp.XXXXXX")"
cleanup_items+=("$CALLER_TMPDIR")
RECORD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lv2-tmpdir-record.XXXXXX")"
cleanup_items+=("$RECORD_DIR")

# A "suite" is just a bash script that records the TMPDIR it was invoked with.
PROBE1="$RECORD_DIR/probe1.sh"
PROBE2="$RECORD_DIR/probe2.sh"
cat > "$PROBE1" <<SH
#!/usr/bin/env bash
printf '%s' "\$TMPDIR" > "$RECORD_DIR/seen1"
exit 0
SH
cat > "$PROBE2" <<SH
#!/usr/bin/env bash
printf '%s' "\$TMPDIR" > "$RECORD_DIR/seen2"
exit 0
SH
chmod +x "$PROBE1" "$PROBE2"

echo "[TMPDIR-01] case: two suites each see a distinct, private TMPDIR"
TMPDIR="$CALLER_TMPDIR" env -u DRY_RUN LEADV2_CORE_OFFLINE_HERMETIC_GATE=0 \
  LEADV2_SUITE_LOCK_DISABLE=1 \
  LEADV2_SUITE_DEFS_OVERRIDE="probe one|||bash $PROBE1
probe two|||bash $PROBE2" \
  bash "$RUNNER" >/dev/null 2>&1 || true

if [[ -f "$RECORD_DIR/seen1" && -f "$RECORD_DIR/seen2" ]]; then
  seen1="$(cat "$RECORD_DIR/seen1")"
  seen2="$(cat "$RECORD_DIR/seen2")"
  if [[ -n "$seen1" && -n "$seen2" && "$seen1" != "$seen2" \
        && "$seen1" != "$CALLER_TMPDIR" && "$seen2" != "$CALLER_TMPDIR" ]]; then
    echo "[TMPDIR-01]   distinct private TMPDIRs: seen1=$seen1 seen2=$seen2 ✓"
    pass=$((pass + 1))
  else
    echo "[TMPDIR-01]   FAILED: not isolated. seen1=$seen1 seen2=$seen2 caller=$CALLER_TMPDIR"
    fail=$((fail + 1))
  fi
else
  echo "[TMPDIR-01]   FAILED: probes never ran (override wiring missing?) — seen1/seen2 absent"
  fail=$((fail + 1))
fi

echo "[TMPDIR-01] pass=$pass fail=$fail"
(( fail == 0 ))
