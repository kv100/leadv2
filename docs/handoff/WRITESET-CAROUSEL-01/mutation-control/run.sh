#!/usr/bin/env bash
# WRITESET-CAROUSEL-01 — declared negative controls, run.
#
# Both mutations are applied by REGEX to a line INSIDE the body of
# `_lv2_ws_live_worker` in leadv2-active-registry.sh — never by line number. A
# line-number insert lands at top level, reddens every suite for the wrong
# reason, and reads exactly like a passing control.
#
# The mutation is applied to a SCRATCH COPY of plugins/leadv2/scripts, never to
# the shared canonical tree: live lanes source that file, and a suite that
# writes over a production file is the very accident that destroyed this
# lane's own working copy earlier today (test-fp07-codex-rg-no-match.sh:35).
#
# Usage: bash docs/handoff/WRITESET-CAROUSEL-01/mutation-control/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SUITE_REL="scripts/tests/test-writeset-carousel.sh"
SRC="${ROOT}/plugins/leadv2/scripts"

run_one() {
  local name="$1" sed_expr="$2" kills="$3"
  local scratch; scratch="$(mktemp -d)"
  cp -R "$SRC" "$scratch/scripts"
  local target="$scratch/scripts/leadv2-active-registry.sh"

  local before after
  before="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"
  sed -i '' "$sed_expr" "$target" 2>/dev/null || sed -i "$sed_expr" "$target"
  after="$(md5 -q "$target" 2>/dev/null || md5sum "$target" | cut -d' ' -f1)"

  printf '\n════ %s\n' "$name"
  printf 'sed: %s\n' "$sed_expr"
  if [[ "$before" == "$after" ]]; then
    printf 'RESULT: control_not_applied (noop edit — the anchor did not match)\n'
    rm -rf "$scratch"; return 2
  fi
  printf 'expected to kill: %s\n' "$kills"
  printf -- '--- mutated line, in the context of its function ---\n'
  awk '/^def _lv2_ws_live_worker/,/^def _lv2_ws_pending/' "$target" | tail -12
  printf -- '--- suite against the mutant ---\n'
  local out rc
  out="$(cd "$scratch" && timeout 240 bash "$scratch/$SUITE_REL" 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -E '^(PASS|FAIL):|^\[WRITESET-CAROUSEL\]'
  if [[ "$rc" -ne 0 ]]; then
    printf 'RESULT: ok — the suite goes RED under this mutation (rc=%d)\n' "$rc"
  else
    printf 'RESULT: MUTANT SURVIVED — the suite stayed green. The control is worthless.\n'
  fi
  rm -rf "$scratch"
  return $(( rc == 0 ? 1 : 0 ))
}

printf 'baseline (unmutated canonical): '
timeout 240 bash "${SRC}/tests/test-writeset-carousel.sh" 2>&1 | tail -1

run_one \
  'WRITESET-PIDLESS-ROW-COUNTS-AS-A-WORKER' \
  '/if pid in (None, "", "null", "None"):/{n;s/return False/return True/;}' \
  'cases 1, 4, 6 — a row with no process at all blocks again, which is the carousel itself'
rc1=$?

run_one \
  'WRITESET-BYSTANDER-LEAD-COUNTS-AS-A-WORKER' \
  's/return _proc_kind(pid) != "interactive"/return True/' \
  'case 3 — a live interactive LEAD pid attached to a lane holds the lock forever again'
rc2=$?

printf '\n════ controls: pidless=%s bystander=%s\n' \
  "$( [[ $rc1 -eq 0 ]] && echo ok || echo FAILED )" \
  "$( [[ $rc2 -eq 0 ]] && echo ok || echo FAILED )"
[[ $rc1 -eq 0 && $rc2 -eq 0 ]]
