#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative controls for the backlog
# pump's lane reservation. Both by regex inside a function body of the
# PRODUCTION file, on a scratch copy.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
PROD='plugins/leadv2/scripts/leadv2-backlog-pump.sh'
SUITE='plugins/leadv2/scripts/tests/test-backlog-pump.sh'

run_control() { # <name> <python-mutator> <expected>
  local name="$1" mut="$2" want="$3"
  local W="$SC/bp-mut-$name"; rm -rf "$W"; cp -R "$PIN" "$W"; cd "$W" || return 1
  python3 - "$PROD" <<PY
import sys
p = sys.argv[1]; s = open(p).read()
${mut}
open(p, 'w').write(s)
PY
  local rc=$?
  if [[ $rc -ne 0 ]] || diff -q "$PIN/$PROD" "$W/$PROD" >/dev/null; then
    echo "--- $name: MUTATION DID NOT APPLY -- control invalid"; cd "$SC"; rm -rf "$W"; return 2
  fi
  bash -n "$W/$PROD" || { echo "--- $name: mutant does not parse -- control invalid"; cd "$SC"; rm -rf "$W"; return 2; }
  echo "--- $name ---"
  echo "    changed: $(diff "$PIN/$PROD" "$W/$PROD" | grep -c '^[<>]') line(s)"
  echo "    expected to kill: $want"
  timeout 300 bash "$SUITE" >"/tmp/bpmut-$name.log" 2>&1
  printf '    suite: rc=%s  %s\n' "$?" "$(grep -oE '[0-9]+ passed, [0-9]+ failed' "/tmp/bpmut-$name.log" | tail -1)"
  grep -E '^\[TEST\] FAIL' "/tmp/bpmut-$name.log" | sort -u | sed 's/^/      /' | head -6
  cd "$SC"; rm -rf "$W"
}

echo "BASELINE (unmutated pin3)"
( cd "$PIN" && timeout 300 bash "$SUITE" >/tmp/bpmut-base.log 2>&1 )
echo "    suite: $(grep -oE '[0-9]+ passed, [0-9]+ failed' /tmp/bpmut-base.log | tail -1)"
echo

# A: the arity drift itself, restored. The 16th positional field goes away and
# the registry cannot unpack the call -- exactly the shipped state.
run_control reserve-passes-the-old-arity \
  "old = '''    \"true\" \"\$ts\" \"\$pulse_log\" \"\" \"\" \\\\\\n    \"null\" \"backlog-pump reserves the lane before dispatch decides its write set\"'''
new = '''    \"true\" \"\$ts\" \"\$pulse_log\" \"\" \"\"'''
assert s.count(old) == 1, 'arity anchor'
s = s.replace(old, new, 1)" \
  'every dispatch case: the pump can reserve no lane at all'

# B: the pump knows why it could not reserve and does not say -- the shape
# that let a hard contract failure live as a soft capacity refusal.
run_control reserve-failure-loses-its-reason \
  "old = 'reason=lane_reserve_failed rc=\${_rl_rc} detail='
assert s.count(old) == 1, 'detail anchor'
s = s.replace(old, 'reason=lane_reserve_failed skip=', 1)" \
  'nothing by itself -- recorded to show the detail is not load-bearing for any assertion'
