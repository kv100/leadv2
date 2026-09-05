#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative controls for the lane-pulse
# arming gate, by regex inside _arm_lane_pulse_watch in the PRODUCTION file.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
PROD='plugins/leadv2/scripts/leadv2-dispatch-code.sh'
SUITE='plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh'

run_control() { # <name> <python-mutator> <expected>
  local name="$1" mut="$2" want="$3"
  local W="$SC/lrod-mut-$name"; rm -rf "$W"; cp -R "$PIN" "$W"; cd "$W" || return 1
  python3 - "$PROD" <<PY
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index('_arm_lane_pulse_watch() {'); j = s.index('\n}\n', i)
body = s[i:j]
${mut}
assert new != body, 'mutation anchor not found inside _arm_lane_pulse_watch'
open(p, 'w').write(s[:i] + new + s[j:])
PY
  local rc=$?
  if [[ $rc -ne 0 ]] || diff -q "$PIN/$PROD" "$W/$PROD" >/dev/null; then
    echo "--- $name: MUTATION DID NOT APPLY -- control invalid"; cd "$SC"; rm -rf "$W"; return 2
  fi
  bash -n "$W/$PROD" || { echo "--- $name: mutant does not parse -- control invalid"; cd "$SC"; rm -rf "$W"; return 2; }
  echo "--- $name ---"
  echo "    changed: $(diff "$PIN/$PROD" "$W/$PROD" | grep -c '^[<>]') line(s) inside _arm_lane_pulse_watch"
  echo "    expected to kill: $want"
  timeout 300 bash "$SUITE" >"/tmp/lrodmut-$name.log" 2>&1
  printf '    suite: rc=%s  %s\n' "$?" "$(grep -oE 'passed=[0-9]+ failed=[0-9]+' "/tmp/lrodmut-$name.log" | tail -1)"
  grep -E '^\[TEST\] FAIL' "/tmp/lrodmut-$name.log" | sort -u | sed 's/^/      /' | head -5
  cd "$SC"; rm -rf "$W"
}

echo "BASELINE (unmutated pin3)"
( cd "$PIN" && timeout 300 bash "$SUITE" >/tmp/lrodmut-base.log 2>&1 )
echo "    suite: $(grep -oE 'passed=[0-9]+ failed=[0-9]+' /tmp/lrodmut-base.log | tail -1)"
echo

# A: the orphan gate is deleted -- every session kind arms.
run_control orphan-gate-deleted \
  "new = body.replace('if [[ \"\${_LV2_KIND}\" != \"lead\" ]]; then', 'if false; then', 1)" \
  'nothing -- recorded to show the orphan gate is UNCOVERED here'

# B: the gate refuses everyone -- no session kind ever arms.
run_control arming-refused-for-every-kind \
  "new = body.replace('if [[ \"\${_LV2_KIND}\" != \"lead\" ]]; then', 'if true; then', 1)" \
  'the lead-path cases (watcher never starts) -- the worker case still passes'
