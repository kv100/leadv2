#!/usr/bin/env bash
# PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01 — negative controls.
#
# Each mutation is applied by REGEX to a line INSIDE a function body, never by
# line number: a line-number insert lands at top level, reddens every case for
# the wrong reason, and reads like a successful control.
#
# Applied to a COPY of the tree under a mktemp root, never to the shared
# canonical file — other lanes are live in this checkout.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_REL='plugins/leadv2/scripts/tests/test-phase-gate-names-everything.sh'
TGT_REL='plugins/leadv2/scripts/leadv2-phase-record.sh'

stage(){
  local m; m="$(mktemp -d)"
  mkdir -p "$m/scripts/tests"
  cp "$REPO/$TGT_REL" "$m/scripts/"
  cp "$REPO/$SUITE_REL" "$m/scripts/tests/"
  printf '%s\n' "$m"
}

mutate(){ # <root> <name> <regex> <replacement>
  python3 - "$1/scripts/leadv2-phase-record.sh" "$2" "$3" "$4" <<'PY'
import re,sys
path,name,pat,repl=sys.argv[1:5]
s=open(path).read()
n=len(re.findall(pat,s,flags=re.M))
if n!=1:
    print('MUTATION %s DID NOT APPLY (matches=%d) - control invalid'%(name,n)); raise SystemExit(9)
open(path,'w').write(re.sub(pat,repl,s,flags=re.M))
print('mutation %s applied: 1 site, inside a function body'%name)
PY
}

control(){ # <name> <regex> <replacement> <grep-context>
  local name="$1" ctx="$4" m rc
  m="$(stage)"
  printf '\n===== NEGATIVE CONTROL: %s =====\n' "$name"
  mutate "$m" "$name" "$2" "$3" || { printf 'ABORT: %s\n' "$name"; return 1; }
  bash -n "$m/scripts/leadv2-phase-record.sh" && printf 'mutant still parses\n'
  printf -- '--- mutated line in context (proof it landed inside the function) ---\n'
  grep -n -B2 -A2 "$ctx" "$m/scripts/leadv2-phase-record.sh" | head -12
  printf -- '--- suite against the mutated writer ---\n'
  timeout 240 bash "$m/scripts/tests/test-phase-gate-names-everything.sh" 2>&1; rc=$?
  printf 'suite exit=%d (0 here would mean the control FAILED to falsify)\n' "$rc"
  rm -rf "$m"
  return 0
}

{
  printf 'PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01 negative controls - %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'repo=%s head=%s\n' "$REPO" "$(git -C "$REPO" rev-parse --short HEAD)"

  printf '\n===== UNMUTATED BASELINE =====\n'
  timeout 240 bash "$REPO/$SUITE_REL" 2>&1
  printf 'suite exit=%d (must be 0)\n' "$?"

  # 1: cmd_assert stops naming anything beyond its own scope.
  control PHASE-GATE-NAMES-ONLY-ITS-OWN-SCOPE \
    '^  required_csv="\$\(IFS=,; printf .%s. "\$\{required_full\[\*\]-\}"\)"$' \
    '  required_csv=""' 'required_csv='

  # 2: cmd_record writes the dead-on-arrival record anyway, as it used to.
  control PHASE-RECORD-WRITES-THE-DEAD-RECORD-ANYWAY \
    '^      exit 5$' '      _proof="unverified"' 'phase_record_refused'
} 2>&1 | tee "$OUT/negative-controls.log"
