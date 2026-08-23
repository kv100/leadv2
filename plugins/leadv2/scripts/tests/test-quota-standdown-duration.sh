#!/usr/bin/env bash
# tests/test-quota-standdown-duration.sh — CODEX-DOOR-DEAD-01 §3: `record-quota-lockout`
# gains a duration-based stand-down mode (--hours/--minutes), distinct from the
# existing quota-classification mode. A stand-down asserts a provider is broken; it
# does not classify launcher output, and it must overwrite an expired lockout file
# rather than leave it stale (the exact reported failure: `--provider codex --hours 3`
# recorded a `quota=no` verdict and left an expired lockout file untouched).
#
# Drives the REAL leadv2-dispatch-code.sh CLI (never a reimplementation).
#
# Run: bash scripts/tests/test-quota-standdown-duration.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

DISPATCH_CODE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$DISPATCH_CODE_SH"; then
  pass "bash -n clean (leadv2-dispatch-code.sh)"
else
  fail "bash -n failed on leadv2-dispatch-code.sh"
fi
if /bin/bash -n "$DISPATCH_CODE_SH" 2>/dev/null; then
  pass "/bin/bash 3.2 -n clean (leadv2-dispatch-code.sh)"
else
  fail "/bin/bash 3.2 -n failed on leadv2-dispatch-code.sh"
fi

SUITE_TMP="$(lv2_mktemp_dir "quota-standdown-test")"
trap 'rm -rf "$SUITE_TMP"' EXIT

now_epoch() { date +%s; }

run_code() { # <lockout-dir> [extra args...]
  local lockout_dir="$1"; shift
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir" \
  LEADV2_JOURNAL_BIN=/bin/true \
    bash "$DISPATCH_CODE_SH" record-quota-lockout "$@" 2>&1
}

journal_line() { # <lockout-dir> [extra args...] -> stderr `emit`/`log` line (JOURNAL_TASK is
  # unset for this subcommand, so emit() only ever reaches its `log` stderr fallback, never
  # LEADV2_JOURNAL_BIN -- capture that directly rather than stubbing a journal binary.
  local lockout_dir="$1"; shift
  LEADV2_QUOTA_LOCKOUT_DIR="$lockout_dir" \
  LEADV2_JOURNAL_BIN=/bin/true \
    bash "$DISPATCH_CODE_SH" record-quota-lockout "$@" 2>&1
}

# ── Test 1: --provider codex --hours 3 writes a lockout ~3h out, source starts standdown: ──
dir1="${SUITE_TMP}/t1"; mkdir -p "$dir1"
out1="$(run_code "$dir1" --provider codex --hours 3)"; rc1=$?
lock1="${dir1}/quota-lockout-codex.json"
if [[ $rc1 -eq 0 ]]; then pass "Test 1: exit 0"; else fail "Test 1: expected exit 0, got ${rc1} -- ${out1}"; fi
if [[ -f "$lock1" ]]; then
  epoch1="$(python3 -c "import json;print(json.load(open('$lock1')).get('locked_until_epoch',0))")"
  source1="$(python3 -c "import json;print(json.load(open('$lock1')).get('source',''))")"
  expect1=$(( $(now_epoch) + 10800 ))
  delta1=$(( epoch1 - expect1 )); delta1=${delta1#-}
  if [[ "$delta1" -le 120 ]]; then pass "Test 1: locked_until_epoch ~= now+10800 (delta=${delta1}s)"; else fail "Test 1: locked_until_epoch off by ${delta1}s"; fi
  if [[ "$source1" == standdown:* ]]; then pass "Test 1: source starts 'standdown:' (got ${source1})"; else fail "Test 1: source is '${source1}', expected standdown:*"; fi
else
  fail "Test 1: quota-lockout-codex.json not written"
fi

# ── Test 2: overwrites a pre-existing EXPIRED lockout file (the exact reported failure) ──
dir2="${SUITE_TMP}/t2"; mkdir -p "$dir2"
lock2="${dir2}/quota-lockout-codex.json"
python3 -c "
import json
json.dump({'provider':'codex','locked_until':'2020-01-01T00:00:00Z','locked_until_epoch':1577836800,'source':'launcher_refusal:quota'}, open('$lock2','w'))
"
run_code "$dir2" --provider codex --hours 3 >/dev/null; rc2=$?
if [[ $rc2 -eq 0 ]]; then pass "Test 2: exit 0"; else fail "Test 2: expected exit 0, got ${rc2}"; fi
epoch2="$(python3 -c "import json;print(json.load(open('$lock2')).get('locked_until_epoch',0))")"
if [[ "$epoch2" -gt $(now_epoch) ]]; then
  pass "Test 2: expired lockout file overwritten, epoch now in the future"
else
  fail "Test 2: lockout file still expired (epoch=${epoch2}, now=$(now_epoch))"
fi

# ── Test 3: quota precheck (_provider_available) refuses codex after the stand-down ──
# _provider_available's own reader contract (leadv2-dispatch-code.sh:989) is exactly
# "locked_until_epoch > now => locked" -- this test exercises the SAME file this
# stand-down call wrote and applies that identical, unmodified contract to it.
dir3="${SUITE_TMP}/t3"; mkdir -p "$dir3"
run_code "$dir3" --provider codex --hours 3 >/dev/null
lock3="${dir3}/quota-lockout-codex.json"
epoch3="$(python3 -c "import json;print(json.load(open('$lock3')).get('locked_until_epoch',0))" 2>/dev/null || echo 0)"
if [[ "$epoch3" -gt $(now_epoch) ]]; then
  pass "Test 3: codex refused by the quota precheck (locked_until_epoch in the future)"
else
  fail "Test 3: codex would NOT be refused -- locked_until_epoch=${epoch3}, now=$(now_epoch)"
fi

# ── Test 4: legacy path intact -- --arm/--handle with non-quota output, no duration ──
dir4="${SUITE_TMP}/t4"; mkdir -p "$dir4"
handle4="${SUITE_TMP}/t4/handle.txt"
printf 'plain error, nothing quota-shaped here\n' > "$handle4"
# _arm_final_output reads from the ledger dir by handle; simplest is to point
# LEADV2_QUOTA_LOCKOUT_DIR at dir4 and rely on _arm_final_output's fallback (a
# missing/unreadable handle record yields empty output, which is not quota-shaped).
out4="$(journal_line "$dir4" --arm codex --handle nonexistent-handle-4 --sig8 tsig004)"; rc4=$?
lock4="${dir4}/quota-lockout-codex.json"
if [[ $rc4 -eq 0 ]]; then pass "Test 4: exit 0"; else fail "Test 4: expected exit 0, got ${rc4} -- ${out4}"; fi
if [[ ! -f "$lock4" ]]; then
  pass "Test 4: no lockout file written (legacy quota=no path)"
else
  fail "Test 4: lockout file unexpectedly written for non-quota-shaped output"
fi
if [[ "$out4" == *'arm_postspawn_verdict arm=codex state=failed quota=no'* ]]; then
  pass "Test 4: journal shows arm_postspawn_verdict ... quota=no"
else
  fail "Test 4: journal missing arm_postspawn_verdict quota=no line -- ${out4}"
fi

# ── Test 5: bad --hours values -- rc0, no file written, stderr names the bad value ──
dir5a="${SUITE_TMP}/t5a"; mkdir -p "$dir5a"
out5a="$(run_code "$dir5a" --provider codex --hours abc)"; rc5a=$?
if [[ $rc5a -eq 0 && ! -f "${dir5a}/quota-lockout-codex.json" && "$out5a" == *"--hours"* ]]; then
  pass "Test 5a: --hours abc -> rc0, no file, stderr names bad value"
else
  fail "Test 5a: --hours abc -- rc=${rc5a} out=${out5a} file=$(ls "$dir5a" 2>/dev/null)"
fi

dir5b="${SUITE_TMP}/t5b"; mkdir -p "$dir5b"
out5b="$(run_code "$dir5b" --provider codex --hours 0)"; rc5b=$?
if [[ $rc5b -eq 0 && ! -f "${dir5b}/quota-lockout-codex.json" ]]; then
  pass "Test 5b: --hours 0 -> rc0, no file"
else
  fail "Test 5b: --hours 0 -- rc=${rc5b} out=${out5b} file=$(ls "$dir5b" 2>/dev/null)"
fi

dir5c="${SUITE_TMP}/t5c"; mkdir -p "$dir5c"
out5c="$(run_code "$dir5c" --provider codex --hours 999)"; rc5c=$?
if [[ $rc5c -eq 0 && ! -f "${dir5c}/quota-lockout-codex.json" ]]; then
  pass "Test 5c: --hours 999 (out of 1..168 range) -> rc0, no file"
else
  fail "Test 5c: --hours 999 -- rc=${rc5c} out=${out5c} file=$(ls "$dir5c" 2>/dev/null)"
fi

# ── Test 6: journal shows quota_standdown_recorded, NOT quota_lockout_recorded ──
dir6="${SUITE_TMP}/t6"; mkdir -p "$dir6"
out6="$(journal_line "$dir6" --provider codex --hours 3)"
if [[ "$out6" == *'quota_standdown_recorded provider=codex hours=3'* ]]; then
  pass "Test 6: journal emits quota_standdown_recorded provider=codex hours=3"
else
  fail "Test 6: journal missing quota_standdown_recorded line -- ${out6}"
fi
if [[ "$out6" == *'quota_lockout_recorded'* ]]; then
  fail "Test 6: journal ALSO emitted quota_lockout_recorded (must be distinct from stand-down)"
else
  pass "Test 6: journal does NOT emit quota_lockout_recorded for a stand-down"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
