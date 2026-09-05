#!/usr/bin/env bash
# ARBITER-REMEMBERS-FAILURES-01 — negative controls.
#
# Each mutation is applied by REGEX to a line INSIDE a function body, never by
# line number: a line-number insert lands at top level, reddens every case for
# the wrong reason, and reads like a successful control.
#
# The mutation is applied to a COPY of the tree under a mktemp root, never to the
# shared canonical file — other lanes are live in this checkout and a two-second
# mutation of plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh would reach
# them. The copy reproduces the layout the suite derives from its own location
# (scripts/lib, scripts/tests, ../config).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_REL='plugins/leadv2/scripts/tests/test-route-arbiter-failure-memory.sh'
ARB_REL='plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh'

stage(){
  local m; m="$(mktemp -d)"
  mkdir -p "$m/scripts/lib" "$m/scripts/tests" "$m/config"
  cp "$REPO/$ARB_REL" "$m/scripts/lib/"
  cp "$REPO/$SUITE_REL" "$m/scripts/tests/"
  cp "$REPO"/plugins/leadv2/config/*.yaml "$m/config/" 2>/dev/null || true
  printf '%s\n' "$m"
}

mutate(){ # <scratch-root> <name> <python-regex> <replacement>
  python3 - "$1/scripts/lib/leadv2-route-arbiter.sh" "$2" "$3" "$4" <<'PY'
import re,sys
path,name,pat,repl=sys.argv[1:5]
s=open(path).read()
n=len(re.findall(pat,s,flags=re.M))
if n!=1:
    print('MUTATION %s DID NOT APPLY (matches=%d) - control invalid'%(name,n)); raise SystemExit(9)
open(path,'w').write(re.sub(pat,repl,s,flags=re.M))
s=open(path).read()
body=s.split("python3 - \"$routing\" <<'PY'",1)[1].rsplit('\nPY\n',1)[0]
compile(body,'mutated','exec')
print('mutation %s applied: 1 site, inside a function body, file still compiles'%name)
PY
}

control(){ # <name> <regex> <replacement> <function-to-print>
  local name="$1" fn="$4" m rc
  m="$(stage)"
  printf '\n===== NEGATIVE CONTROL: %s =====\n' "$name"
  mutate "$m" "$name" "$2" "$3" || { printf 'ABORT: %s\n' "$name"; return 1; }
  printf -- '--- mutated function body (proof the edit landed INSIDE it) ---\n'
  awk -v fn="$fn" '$0 ~ "^def "fn"\\(" {p=1} p{print} p && /^[^ #]/ && $0 !~ "^def "fn"\\(" {exit}' \
      "$m/scripts/lib/leadv2-route-arbiter.sh" | head -60
  printf -- '--- suite against the mutated arbiter ---\n'
  timeout 240 bash "$m/scripts/tests/test-route-arbiter-failure-memory.sh" 2>&1; rc=$?
  printf 'suite exit=%d (0 here would mean the control FAILED to falsify)\n' "$rc"
  rm -rf "$m"
  return 0
}

{
  printf 'ARBITER-REMEMBERS-FAILURES-01 negative controls - %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'repo=%s head=%s\n' "$REPO" "$(git -C "$REPO" rev-parse --short HEAD)"

  printf '\n===== UNMUTATED BASELINE =====\n'
  timeout 240 bash "$REPO/$SUITE_REL" 2>&1
  printf 'suite exit=%d (must be 0)\n' "$?"

  # A: the ledger-to-arm attribution inside read_failure_memory stops counting.
  control ARBITER-FAILURE-MEMORY-STOPS-COUNTING \
    'counts\[arm\]=counts\.get\(arm,0\)\+1' 'pass' read_failure_memory

  # B: capped() forgets that an unmeasured arm is not a busy one.
  control ARBITER-UNKNOWN-IS-CAPPED-AGAIN \
    '^    if unk\.get\(provider\): return False\n' '' capped
} 2>&1 | tee "$OUT/negative-controls.log"
