#!/usr/bin/env bash
# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 — declared negative controls,
# run. A control on the control machinery itself.
#
# Both mutations are applied by REGEX to a unique anchor line, never by line
# number, and always to a SCRATCH COPY of a pinned tree.
#
# Usage: bash mc-mutation-run.sh <pinned tree>
set -uo pipefail
SRC="${1:?a pinned scratch tree is required — never the live checkout}"
SUITE_REL="plugins/leadv2/scripts/tests/test-mutation-control-lane-identity.sh"

run_one() {
  local name="$1" file_rel="$2" sed_expr="$3" kills="$4"
  local scratch; scratch="$(cd "$(mktemp -d)" && pwd -P)"
  cp -R "$SRC/." "$scratch/" 2>/dev/null
  local target="$scratch/$file_rel" before after
  before="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"
  sed -i '' "$sed_expr" "$target" 2>/dev/null || sed -i "$sed_expr" "$target"
  after="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"

  printf '\n==== %s\n' "$name"
  printf 'file: %s\nsed:  %s\n' "$file_rel" "$sed_expr"
  if [[ "$before" == "$after" ]]; then
    printf 'RESULT: control_not_applied (noop edit — the anchor did not match)\n'
    rm -rf "$scratch"; return 2
  fi
  printf 'expected to kill: %s\n' "$kills"
  printf -- '--- suite against the mutant ---\n'
  local rc
  timeout 590 bash "$scratch/$SUITE_REL" > /tmp/mc-mc 2>&1; rc=$?
  grep -E '^(PASS|FAIL):|^\[MUTATION-CONTROL' /tmp/mc-mc | cut -c1-140
  if [[ "$rc" -ne 0 ]]; then
    printf 'RESULT: ok — the suite goes RED under this mutation (rc=%d)\n' "$rc"
  else
    printf 'RESULT: MUTANT SURVIVED — the control machinery stayed green about itself.\n'
  fi
  rm -rf "$scratch"
  return $(( rc == 0 ? 1 : 0 ))
}

printf 'baseline (unmutated pinned tree): '
timeout 590 bash "$SRC/$SUITE_REL" 2>&1 | tail -1

# A. the producer stops refusing an empty lane diff — the measured bug returns.
run_one \
  'MUTATION-CONTROL-STAMPS-AN-EMPTY-IDENTITY' \
  'plugins/leadv2/scripts/leadv2-mutation-control.sh' \
  's|^if git -C "${ROOT}" diff --quiet "${MC_BASE}" HEAD|if false \&\& git -C "${ROOT}" diff --quiet "${MC_BASE}" HEAD|; /LANE_DIFF_HASH}" == "e3b0c442/s|.*|if false; then|' \
  'cases 1, 2, 3, 5 — the artifact is written again with the empty-diff hash. Cases 4 and 6 stay green. BOTH producer guards are removed: the property is implemented twice, so a single-site mutation survives — measured, first run'
rcA=$?

# B. the consumer stops requiring a real lane identity — two empty hashes
#    compare equal again and the gate confirms itself on zero information.
run_one \
  'DOD-GATE-ACCEPTS-AN-EMPTY-IDENTITY' \
  'plugins/leadv2/scripts/lib/leadv2-dod-gate.sh' \
  '/lane_hash.*!= e3b0c442/s|.*|  :|' \
  'case 6 only — every producer-side case stays green'
rcB=$?

printf '\n==== controls: stamps-empty-identity=%s gate-accepts-empty=%s\n' \
  "$( [[ $rcA -eq 0 ]] && echo ok || echo FAILED )" \
  "$( [[ $rcB -eq 0 ]] && echo ok || echo FAILED )"
[[ $rcA -eq 0 && $rcB -eq 0 ]]
