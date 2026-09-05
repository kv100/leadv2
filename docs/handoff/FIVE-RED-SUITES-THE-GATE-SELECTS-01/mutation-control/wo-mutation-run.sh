#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative controls for the write-set
# overlap checker's "could not look" line. Both are applied by regex INSIDE a
# function body of the PRODUCTION file, on a scratch copy.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
PROD='plugins/leadv2/scripts/leadv2-writes-overlap.sh'
SUITE='plugins/leadv2/scripts/tests/test-writes-overlap.sh'

run_control() { # <name> <python-mutator> <expected>
  local name="$1" mut="$2" want="$3"
  local W="$SC/wo-mut-$name"; rm -rf "$W"; cp -R "$PIN" "$W"; cd "$W" || return 1
  python3 - "$PROD" <<PY
import sys
p = sys.argv[1]
s = open(p).read()
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
  timeout 240 bash "$SUITE" >"/tmp/womut-$name.log" 2>&1
  printf '    suite: rc=%s  %s\n' "$?" "$(grep -oE '[0-9]+ passed, [0-9]+ failed' "/tmp/womut-$name.log" | tail -1)"
  grep -E '^\[TEST\] FAIL' "/tmp/womut-$name.log" | sed 's/^/      /' | head -6
  cd "$SC"; rm -rf "$W"
}

echo "BASELINE (unmutated pin3)"
( cd "$PIN" && timeout 240 bash "$SUITE" >/tmp/womut-base.log 2>&1 )
echo "    suite: $(grep -oE '[0-9]+ passed, [0-9]+ failed' /tmp/womut-base.log | tail -1)"
echo

# A: the producer stops distinguishing. Removes the PROPERTY, not one site:
# every "could not look" exit goes back to the exit code that means "looked".
run_control producer-cannot-say-it-did-not-look \
  "s = s.replace('sys.exit(20)', 'sys.exit(0)')
assert 'sys.exit(20)' not in s" \
  'the three no-parser cases and the liveness case'

# B: the consumer knows and does not say -- the arbiter shape one floor up.
run_control checker-knows-and-does-not-say \
  "old = 'if [[ -n \"\$UNCHECKED_REASON\" ]]; then'
assert s.count(old) == 1
s = s.replace(old, 'if false; then', 1)" \
  'the three no-parser cases and the liveness case (state computed, never announced)'
