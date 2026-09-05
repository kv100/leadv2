#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative controls for the lane-watch
# unreadable-queue fix. Each control is applied BY REGEX INSIDE A FUNCTION
# BODY of the PRODUCTION file, on a scratch copy, and the suite is then run in
# BOTH environments (ordinary HOME and a scrubbed one) because the property
# under test is precisely the one that must not depend on the environment.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
FAKE="$SC/herm-home"; mkdir -p "$FAKE"; cp "$HOME/.gitconfig" "$FAKE/.gitconfig" 2>/dev/null || true
PROD='plugins/leadv2/scripts/leadv2-lane-watch-v2.sh'
SUITE='plugins/leadv2/scripts/tests/test-lane-watch-v2.sh'

run_control() { # <name> <sed-expr> <what it should kill>
  local name="$1" expr="$2" want="$3"
  local W="$SC/lw-mut-$name"; rm -rf "$W"; cp -R "$PIN" "$W"
  sed -i '' "$expr" "$W/$PROD" || { echo "$name: sed failed"; return 1; }
  if diff -q "$PIN/$PROD" "$W/$PROD" >/dev/null; then
    echo "$name: MUTATION DID NOT APPLY -- control invalid"; return 2
  fi
  bash -n "$W/$PROD" || { echo "$name: mutant does not parse -- control invalid"; return 2; }
  echo "--- $name ---"
  echo "    mutation: $(diff "$PIN/$PROD" "$W/$PROD" | grep -c '^[<>]') line(s) changed inside _lw_queued_task_count / its caller"
  echo "    expected to kill: $want"
  ( cd "$W" && timeout 240 bash "$SUITE" >/tmp/lwmut-$name-a.log 2>&1 ); local rcA=$?
  ( cd "$W" && HOME="$FAKE" timeout 240 bash "$SUITE" >/tmp/lwmut-$name-b.log 2>&1 ); local rcB=$?
  printf '    ordinary HOME : rc=%s  %s\n' "$rcA" "$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' /tmp/lwmut-$name-a.log | tail -1)"
  printf '    scrubbed HOME : rc=%s  %s\n' "$rcB" "$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' /tmp/lwmut-$name-b.log | tail -1)"
  echo "    failing cases (ordinary):"; grep -E '^\[TEST\] FAIL' /tmp/lwmut-$name-a.log | sed 's/^/      /'
  rm -rf "$W"
}

echo "BASELINE (unmutated pin3)"
( cd "$PIN" && timeout 240 bash "$SUITE" >/tmp/lwmut-base-a.log 2>&1 ); echo "    ordinary HOME : rc=$? $(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' /tmp/lwmut-base-a.log | tail -1)"
( cd "$PIN" && HOME="$FAKE" timeout 240 bash "$SUITE" >/tmp/lwmut-base-b.log 2>&1 ); echo "    scrubbed HOME : rc=$? $(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' /tmp/lwmut-base-b.log | tail -1)"
echo

# Control A removes the PROPERTY, not one implementation of it: BOTH exits
# that refuse to answer zero become an answer of zero. (Lesson from
# MUTATION-CONTROL-...-01: a single-site mutation of a twice-implemented
# property leaves the property intact and the mutant survives.)
run_control unreadable-queue-answers-zero \
  '/no parser at all/s|.*|    print(0); sys.exit(0)|; /present but unparseable/s|.*|    print(0); sys.exit(0)|' \
  'r2-unknown, in BOTH environments'

# Control B is the arbiter shape one floor up: the caller still COMPUTES the
# unknown state and simply does not act on it.
run_control watcher-knows-and-does-not-say \
  '/if \[ "\$queued_rc" -ne 0 \]; then/s|.*|  if false; then|' \
  'r2-unknown (the state is computed, never announced)'
