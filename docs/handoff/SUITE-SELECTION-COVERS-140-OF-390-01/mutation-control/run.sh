#!/usr/bin/env bash
# SUITE-SELECTION-COVERS-140-OF-390-01 — declared negative controls, run.
#
# Both mutations are applied by REGEX to a line INSIDE a function body, never by
# line number, and always to a SCRATCH COPY of the tree — never to the shared
# canonical checkout, where a suite that writes over a production file has
# already destroyed one live lane's work today.
#
# Usage: bash docs/handoff/SUITE-SELECTION-COVERS-140-OF-390-01/mutation-control/run.sh <scratch tree>
set -uo pipefail
SRC="${1:?a pinned scratch tree is required — never the live checkout}"
SUITE_REL="plugins/leadv2/scripts/tests/test-suite-selection-coverage.sh"

run_one() {
  local name="$1" file_rel="$2" sed_expr="$3" kills="$4"
  # pwd -P: on macOS mktemp hands back /var/folders/..., a symlink to
  # /private/var/folders/..., and run-all.sh FATALs with root_escape when its
  # resolved root differs from the path it was invoked under. That would redden
  # case 4 in every mutant for a reason that has nothing to do with the mutation.
  local scratch; scratch="$(cd "$(mktemp -d)" && pwd -P)"
  cp -R "$SRC/." "$scratch/" 2>/dev/null
  local target="$scratch/$file_rel"
  local before after
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
  printf -- '--- the mutated line, in context ---\n'
  grep -n -m1 -E 'run-all-triggers|marker removed' "$target" | head -3
  printf -- '--- suite against the mutant ---\n'
  local rc
  timeout 240 bash "$scratch/$SUITE_REL" > /tmp/mc-out 2>&1; rc=$?
  grep -E '^(PASS|FAIL):|^\[SUITE-SELECTION' /tmp/mc-out | cut -c1-160
  if [[ "$rc" -ne 0 ]]; then
    printf 'RESULT: ok — the suite goes RED under this mutation (rc=%d)\n' "$rc"
  else
    printf 'RESULT: MUTANT SURVIVED — the guard stayed green. The control is worthless.\n'
  fi
  rm -rf "$scratch"
  return $(( rc == 0 ? 1 : 0 ))
}

printf 'baseline (unmutated scratch tree): '
timeout 240 bash "$SRC/$SUITE_REL" 2>&1 | tail -1

# A. the guard must actually READ the marker, not assume it.
run_one \
  'SUITE-SELECTION-GUARD-IGNORES-THE-MARKER' \
  "$SUITE_REL" \
  "s|grep -q '\^# run-all-triggers:' \"\$f\"|grep -q '^# NEVER-MATCHES-run-all-triggers:' \"\$f\"|" \
  'case 1 — with the marker unreadable every suite becomes an orphan'
rcA=$?

# B. the regression this row exists to catch: a real suite loses its marker.
#    Mutating the SUITE CORPUS, not the guard, is the honest control here —
#    it reproduces the actual production defect rather than a proxy for it.
run_one \
  'A-SUITE-SILENTLY-LOSES-ITS-TRIGGER' \
  'plugins/leadv2/scripts/tests/test-active-registry-failclosed.sh' \
  's|^# run-all-triggers:.*$|# (marker removed by the negative control)|' \
  'case 1 — the un-marked, un-declared suite is named as an orphan'
rcB=$?

printf '\n==== controls: ignores-marker=%s loses-trigger=%s\n' \
  "$( [[ $rcA -eq 0 ]] && echo ok || echo FAILED )" \
  "$( [[ $rcB -eq 0 ]] && echo ok || echo FAILED )"
[[ $rcA -eq 0 && $rcB -eq 0 ]]
