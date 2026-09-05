#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative control for the two selection
# proofs re-pointed at the live mechanism (test-lane-watch-v2.sh and
# test-skill-telemetry.sh). One control, two suites: the discovery loop inside
# scan_suite_triggers() in the PRODUCTION file tests/run-all.sh is made to
# collect nothing, by regex, inside the function body.
#
# The property under test is not "my row is present" but "an empty map is a
# DIFFERENT fact from a missing row" — the distinction the old EXTRA_SUITE_MAP
# assertions could not make, which is how they went stale in silence.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
W="$SC/sel-mut"; rm -rf "$W"; cp -R "$PIN" "$W"; cd "$W" || exit 1

python3 - <<'PY'
import re
p = 'tests/run-all.sh'
s = open(p).read()
i = s.index('scan_suite_triggers() {'); j = s.index('\n}\n', i)
body = s[i:j]
mut = body.replace('[[ -n "${_hits}" ]] || continue', 'continue', 1)
assert mut != body, 'mutation anchor not found inside scan_suite_triggers'
open(p, 'w').write(s[:i] + mut + s[j:])
print('    mutation applied inside scan_suite_triggers()')
PY

echo "    changed: $(diff "$PIN/tests/run-all.sh" tests/run-all.sh | grep -c '^[<>]') line(s)"
bash -n tests/run-all.sh && echo "    mutant parses"
echo "    discovered map now: [$(LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh 2>/dev/null | head -c 60)]"
for s in lane-watch-v2 skill-telemetry; do
  timeout 240 bash "plugins/leadv2/scripts/tests/test-$s.sh" >"/tmp/sm-$s.log" 2>&1; rc=$?
  printf '    %-18s rc=%s  %s\n' "$s" "$rc" "$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' "/tmp/sm-$s.log" | tail -1)"
  grep -E '^\[TEST\] FAIL: run-all' "/tmp/sm-$s.log" | head -1 | sed 's/^/      /'
done
cd "$SC" && rm -rf "$W"
