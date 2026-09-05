#!/usr/bin/env bash
# REVIEW-GATE-IS-MUTE-01 — declared negative controls, run.
#
# Both mutations are applied by REGEX to a line INSIDE a function/block body of
# leadv2-review-run.sh, never by line number, and always to a SCRATCH COPY of a
# pinned tree — never to the live checkout, where wave-B1's merge is still open
# on this very file.
#
# Usage: bash rg-mutation-run.sh <pinned tree>
set -uo pipefail
SRC="${1:?a pinned scratch tree is required — never the live checkout}"
SUITE_REL="plugins/leadv2/scripts/tests/test-review-gate-names-the-unreadable.sh"
FILE_REL="plugins/leadv2/scripts/leadv2-review-run.sh"

run_one() {
  local name="$1" sed_expr="$2" kills="$3"
  local scratch; scratch="$(cd "$(mktemp -d)" && pwd -P)"
  cp -R "$SRC/." "$scratch/" 2>/dev/null
  local target="$scratch/$FILE_REL" before after
  before="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"
  sed -i '' "$sed_expr" "$target" 2>/dev/null || sed -i "$sed_expr" "$target"
  after="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"

  printf '\n==== %s\n' "$name"
  printf 'sed: %s\n' "$sed_expr"
  if [[ "$before" == "$after" ]]; then
    printf 'RESULT: control_not_applied (noop edit — the anchor did not match)\n'
    rm -rf "$scratch"; return 2
  fi
  printf 'expected to kill: %s\n' "$kills"
  printf -- '--- the mutated line, in the context of its block ---\n'
  grep -n -A1 -m1 -E '_rv_unreadable\(\)|UNREADABLE_LINE=' "$target" | head -4
  printf -- '--- suite against the mutant ---\n'
  local rc
  timeout 590 bash "$scratch/$SUITE_REL" > /tmp/rg-mc 2>&1; rc=$?
  grep -E '^(PASS|FAIL):|^\[REVIEW-GATE' /tmp/rg-mc | cut -c1-150
  if [[ "$rc" -ne 0 ]]; then
    printf 'RESULT: ok — the suite goes RED under this mutation (rc=%d)\n' "$rc"
  else
    printf 'RESULT: MUTANT SURVIVED — the gate stayed green. The control is worthless.\n'
  fi
  rm -rf "$scratch"
  return $(( rc == 0 ? 1 : 0 ))
}

printf 'baseline (unmutated pinned tree): '
timeout 590 bash "$SRC/$SUITE_REL" 2>&1 | tail -1

# A. the exact production bug: nothing is ever recorded as unreadable, so the
#    gate reports `unreadable: none` and `degraded=false` beside a mute arm.
run_one \
  'REVIEW-GATE-CALLS-A-MUTE-ARM-HEALTHY' \
  's|  _REVIEW_UNREADABLE="\${_REVIEW_UNREADABLE:+\${_REVIEW_UNREADABLE},}\$1=\$2"|  :|' \
  'cases 1, 2, 4 — the mute arm vanishes and the gate calls itself undegraded'
rcA=$?

# B. the gate knows, and does not say: the list is kept but never printed.
run_one \
  'REVIEW-GATE-KNOWS-AND-DOES-NOT-SAY' \
  "s|UNREADABLE_LINE=\"\$(printf 'unreadable: %s' \"\${_REVIEW_UNREADABLE:-none}\")\"|UNREADABLE_LINE=\"\"|" \
  'cases 1 and 5 — nothing on the gate file; case 2 stays green because degraded is still forced'
rcB=$?

printf '\n==== controls: mute-arm-healthy=%s knows-and-does-not-say=%s\n' \
  "$( [[ $rcA -eq 0 ]] && echo ok || echo FAILED )" \
  "$( [[ $rcB -eq 0 ]] && echo ok || echo FAILED )"
[[ $rcA -eq 0 && $rcB -eq 0 ]]
