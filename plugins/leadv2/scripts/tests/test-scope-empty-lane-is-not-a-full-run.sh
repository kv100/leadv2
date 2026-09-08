#!/usr/bin/env bash
# run-all-triggers: run-core-offline
# Real runner and curated count, isolated Git history; no suite-body stubs for
# the empty run. Negative controls target the empty return and unmapped return
# INSIDE _core_offline_scope_changed_select via leadv2-mutation-control.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/scope-empty.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT
RUNNER=plugins/leadv2/scripts/tests/run-core-offline.sh
mkdir -p "$FIX/plugins/leadv2/scripts/tests"
cp "$SCRIPT_DIR/run-core-offline.sh" "$FIX/$RUNNER"
git -C "$FIX" init -q
git -C "$FIX" config user.email scope-empty@test.local
git -C "$FIX" config user.name scope-empty-test
git -C "$FIX" symbolic-ref HEAD refs/heads/main
git -C "$FIX" add -- "$RUNNER"
git -C "$FIX" commit -qm base
git -C "$FIX" checkout -qb lane
git -C "$FIX" commit --allow-empty -qm anchor

PASS=0
FAIL=0
field() {
  printf '%s\n' "$OUT" | sed -n 's/^.*SCOPE_RESULT //p' \
    | tr ' ' '\n' | sed -n "s/^$1=//p"
}
check() {
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s expected=%s actual=%s\n' "$1" "$3" "$2"
    FAIL=$((FAIL + 1))
  fi
}
dump() {
  local rc=0
  OUT="$(/usr/bin/time -p env -u LEADV2_SUITE_DEFS_OVERRIDE LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 \
    bash "$FIX/$RUNNER" --scope changed 2>&1)" || rc=$?
  check "$1 rc" "$rc" 0
  printf 'case=%s\n' "$1"
  printf '%s\n' "$OUT" | sed -n '/SCOPE_RESULT/p; /^real /p'
}
empty_check() {
  check "$1 selected" "$(field selected)" 0
  check "$1 changed" "$(field changed)" 0
  check "$1 unmapped" "$(field unmapped)" 0
  check "$1 reason" "$(field reason)" no_relevant_changed_files
  check "$1 verdict" "$(field verdict)" nothing_to_run
}

dump anchor
empty_check anchor
TOTAL="$(field total)"
[[ "$TOTAL" =~ ^[1-9][0-9]*$ ]] || { printf 'FAIL: invalid curated total=%s\n' "$TOTAL"; exit 1; }
printf '# Docs only\n' > "$FIX/README.md"
git -C "$FIX" add -- README.md
git -C "$FIX" commit -qm docs-only
dump docs
empty_check docs

# Exercise execution as well as introspection, including the lock re-exec.
# A 10-second bound prevents the original full-run regression hanging tests.
rc=0
OUT="$(/usr/bin/time -p env -u LEADV2_SUITE_DEFS_OVERRIDE -u LEADV2_CORE_OFFLINE_SCOPE_DUMP \
  LEADV2_SUITE_LOCK_DISABLE=0 LEADV2_SUITE_LOCK_WAIT_S=2 \
  timeout 10 bash "$FIX/$RUNNER" --scope changed 2>&1)" || rc=$?
check 'docs execution rc' "$rc" 0
empty_check 'docs execution'
printf 'case=docs-execution\n'
printf '%s\n' "$OUT" | sed -n '/SCOPE_RESULT/p; /^real /p'
check 'docs execution summary' "$(printf '%s\n' "$OUT" | sed -n \
  's/.*suites passed=\([0-9]*\) failed=\([0-9]*\) missing=\([0-9]*\).*/\1 \2 \3/p')" '0 0 0'

# Same fixture, genuine source outside every convention/map. Both untracked
# and staged forms must retain the complete curated fallback.
printf 'export const uncovered = true;\n' > "$FIX/uncovered-source.js"
for state in untracked staged; do
  if [[ "$state" == staged ]]; then git -C "$FIX" add -- uncovered-source.js; fi
  dump "$state"
  check "$state selected" "$(field selected)" "$TOTAL"
  check "$state changed" "$(field changed)" 1
  check "$state unmapped" "$(field unmapped)" 1
  check "$state reason" "$(field reason)" unmapped_files
done
printf 'scope-empty: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
