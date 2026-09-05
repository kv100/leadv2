#!/usr/bin/env bash
# FIVE-RED-SUITES-THE-GATE-SELECTS-01 — negative controls for T5's
# known-violator list.
#
# The property under test is NOT "the scanner works" -- T5-NC already covers
# that -- but "the LIST excuses exactly the listed violation and nothing else".
# Both mutations insert a real class member inside a function body of a scanned
# PRODUCTION lib, as an unexecuted heredoc: bash-valid (the suite sources these
# libs, so an unparseable mutant would redden everything for the wrong reason)
# and textually identical in shape to the standing violator.
set -uo pipefail
SC="$(cd "$(dirname "$0")" && pwd)"
PIN="$SC/pin3"
SUITE='plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh'

inject() { # <file> -- insert after the first top-level function opening
  python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r'^[A-Za-z_][A-Za-z_0-9]*\(\) \{\n', s, re.M)
assert m, 'no function opening found in ' + p
ins = ("  : <<'MC_BLOCK'\n"
       "  ps -axo pid=,command=\n"
       "  if worktree not in line: continue\n"
       "MC_BLOCK\n")
open(p, 'w').write(s[:m.end()] + ins + s[m.end():])
print('    injected after: ' + m.group(0).strip())
PY
}

run_control() { # <name> <target> <expected>
  local name="$1" target="$2" want="$3"
  local W="$SC/ts-mut-$name"; rm -rf "$W"; cp -R "$PIN" "$W"; cd "$W" || return 1
  echo "--- $name ---"
  echo "    target: $target"
  inject "$target" || { echo "    MUTATION FAILED -- control invalid"; cd "$SC"; rm -rf "$W"; return 2; }
  if diff -q "$PIN/$target" "$W/$target" >/dev/null; then
    echo "    MUTATION DID NOT APPLY -- control invalid"; cd "$SC"; rm -rf "$W"; return 2
  fi
  bash -n "$target" || { echo "    mutant does not parse -- control invalid"; cd "$SC"; rm -rf "$W"; return 2; }
  echo "    expected to kill: $want"
  timeout 300 bash "$SUITE" >"/tmp/tsmut-$name.log" 2>&1
  printf '    suite: rc=%s  %s\n' "$?" "$(grep -oE '[0-9]+ passed, [0-9]+ failed' "/tmp/tsmut-$name.log" | tail -1)"
  grep -E '^\[TEST\] (FAIL|PASS): T5:' "/tmp/tsmut-$name.log" | sort -u | sed 's/^/      /' | head -3
  cd "$SC"; rm -rf "$W"
}

echo "BASELINE (unmutated pin3)"
( cd "$PIN" && timeout 300 bash "$SUITE" >/tmp/tsmut-base.log 2>&1 )
echo "    suite: $(grep -oE '[0-9]+ passed, [0-9]+ failed' /tmp/tsmut-base.log | tail -1)"
grep -E '^\[TEST\] PASS: T5:' /tmp/tsmut-base.log | head -1 | sed 's/^/    /'
echo

run_control new-violation-in-a-clean-file \
  plugins/leadv2/scripts/lib/leadv2-watch-lifecycle.sh \
  'T5 -- a violation in an unlisted file must be NEW, not excused'

# The one an allow-list keyed on the FILE would miss: it would excuse a file
# rather than a violation, which is how an allow-list becomes a blindfold.
run_control second-violation-in-a-listed-file \
  plugins/leadv2/scripts/lib/leadv2-lane-state.sh \
  'T5 -- a SECOND violation in a listed file must be NEW, not read as the standing one having moved'
