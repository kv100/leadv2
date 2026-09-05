#!/usr/bin/env bash
# run-all-triggers: run-all leadv2-run-all
#
# SUITE-SELECTION-COVERS-140-OF-390-01 — the invariant that keeps "the suite is
# green" meaningful: **every tracked suite is either selectable by a
# change-scoped run, or declared unselectable on purpose.** Silence is not a
# third answer.
#
# Measured at 27f3bd83 before the fix: of 427 suites in the four discovery
# directories, 167 could be selected by `run-all.sh --scope changed` (144 by a
# `# run-all-triggers:` marker, 27 by the name convention, 4 by both) and
# `EXTRA_SUITE_MAP` was EMPTY. 260 could only ever run under `--scope all`.
# Three suites literally named test-active-regist* sat unselected while
# leadv2-active-registry.sh changed under them.
#
# WHAT IS REAL HERE. The suite re-derives selectability the way run-all.sh
# itself does — by scanning for the marker with run-all's own prefix and by
# applying its stem convention against the real production directories — and
# reads the real declaration file. Nothing is stubbed and no count is carried:
# every number below is computed from the tree it runs in.
#
# DECLARED NEGATIVE CONTROL (mutation-control/, tests/mutations/catalog.yaml),
# applied by REGEX to a line INSIDE _selectable()'s body:
#   SUITE-SELECTION-GUARD-CALLS-EVERYTHING-SELECTABLE  the marker test is
#     short-circuited to true, so an unmarked, undeclared suite passes. Kills (1).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# The four directories run-all.sh discovers, minus .claude/scripts/tests, which
# holds untracked drifted copies of the canonical suites (the symlink farm the
# drift guard reports). Those are not this repo's source of truth and a marker
# written into one of them would be lost by the next symlink restore.
DIRS=(plugins/leadv2/scripts/tests plugins/leadv2/tests tests)
DECL="${ROOT}/tests/unselected-by-design.txt"

# _selectable <abs suite path> -> 0 when a change-scoped run can select it
_selectable() {
  local f="$1" base stem
  base="$(basename "$f")"
  if grep -q '^# run-all-triggers:' "$f" 2>/dev/null; then
    return 0
  fi
  # run-all.sh's stem convention: a changed production file X.sh selects
  # tests/test-X.sh and plugins/leadv2/scripts/tests/test-X.sh by name alone.
  stem="${base#test-}"; stem="${stem%.sh}"
  for d in plugins/leadv2/scripts plugins/leadv2/scripts/lib plugins/leadv2/hooks; do
    [[ -f "${ROOT}/${d}/${stem}.sh" ]] && return 0
  done
  return 1
}

_declared() {
  [[ -f "$DECL" ]] || return 1
  grep -qE "^$(basename "$1")[[:space:]]" "$DECL" 2>/dev/null
}

# ── 1. THE INVARIANT. Nothing is selected by silence.
orphans=""; total=0
for d in "${DIRS[@]}"; do
  [[ -d "${ROOT}/${d}" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    total=$((total+1))
    _selectable "$f" && continue
    _declared "$f" && continue
    orphans="${orphans}$(basename "$f")
"
  done < <(find "${ROOT}/${d}" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort)
done
if [[ -z "$orphans" ]]; then
  ok "all ${total} tracked suites are either selectable or declared unselectable"
else
  bad "1: $(printf '%s' "$orphans" | tr '\n' ' ' | cut -c1-300)"
fi

# ── 2. THE DECLARATION IS NOT A DUMPING GROUND. Every name in it must exist,
#      or the file quietly excuses suites that were deleted years ago.
missing=""
while IFS=$'\t' read -r name _rest; do
  case "$name" in ''|'#'*) continue ;; esac
  found=0
  for d in "${DIRS[@]}"; do [[ -f "${ROOT}/${d}/${name}" ]] && found=1; done
  [[ "$found" == 1 ]] || missing="${missing}${name} "
done < "$DECL"
if [[ -z "$missing" ]]; then
  ok "every name in unselected-by-design.txt names a suite that exists"
else
  bad "2: stale declarations: ${missing}"
fi

# ── 3. EVERY DECLARATION CARRIES A REASON. A bare name is silence with extra
#      steps — the exact thing this row exists to kill.
noreason=""
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  printf '%s' "$line" | grep -qE '^[^[:space:]]+[[:space:]]+(writes-production|needs-network|no-production-file|dead)$' \
    || noreason="${noreason}${line%%[[:space:]]*} "
done < "$DECL"
if [[ -z "$noreason" ]]; then
  ok "every declaration carries one of the four allowed reasons"
else
  bad "3: declarations without a valid reason: ${noreason}"
fi

# ── 4. THE MARKER MUST PARSE. run-all.sh treats a malformed declaration as a
#      FATAL, so a marker this lane wrote badly would take the whole run down.
out="$(LEADV2_RUN_ALL_LIST_TRIGGERS=1 timeout 120 bash "${ROOT}/tests/run-all.sh" 2>&1)"; rc=$?
if [[ "$rc" == 0 ]] && [[ -n "$out" ]]; then
  ok "run-all.sh parses every marker in the tree (LIST_TRIGGERS rc=0, $(printf '%s' "$out" | wc -l | tr -d ' ') rows)"
else
  bad "4: LIST_TRIGGERS rc=${rc} out=$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi

printf '[SUITE-SELECTION-COVERAGE] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
