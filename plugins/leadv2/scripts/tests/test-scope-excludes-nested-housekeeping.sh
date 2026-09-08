#!/usr/bin/env bash
# run-all-triggers: run-core-offline
#
# test-scope-excludes-nested-housekeeping.sh —
# LANE-LIVENESS-ARTIFACTS-FORCE-A-95-SUITE-RUN-01.
#
# run-core-offline.sh's --scope changed selector excluded housekeeping with
# `case "$f" in *.md|docs/*) continue ;; esac` — anchored at the START of the
# path. A lane worktree accumulates untracked runtime artifacts under BOTH
# docs/leadv2/.lane-liveness-share/<hash>/{rc,result,ts} (matches, correctly
# excluded) and plugins/docs/leadv2/.lane-liveness-share/<hash>/{rc,result,ts}
# (does NOT match — "docs" is not the first path segment). Each unmatched
# artifact file counted as an unmapped changed file, which trips the
# cannot-prove-coverage safety net and forces the full 95-suite set even on a
# one-line diff (measured: lane d2823c51e670, 900s ceiling, verdict=timeout
# rc=124 -- see GATE-BUDGET-TOO-SMALL-FOR-run-all-OWN-SUITES-01).
#
# The exclusion now matches `docs/` as a full path segment at ANY depth
# (docs/* leading, */docs/* nested) plus the .lane-liveness-share artifact
# dir by name at any depth — never a bare `*docs*`, which would also swallow
# a real source file under some future plugins/docs-tool/.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), both inserted INSIDE
# _core_offline_scope_changed_select()'s body in run-core-offline.sh, proved
# with leadv2-mutation-control.sh against THIS suite (see developer.full.md
# for the raw exit-code transcript, not reproduced here to keep this suite
# hermetic and side-effect-free):
#   M1 restore-leading-anchor — revert the case pattern to the original
#      `*.md|docs/*) continue ;;`. nested_housekeeping_case must go RED on
#      SCOPE_UNMAPPED_COUNT/selected= (the values under test), never on a log
#      string: the nested artifact is again miscounted as unmapped and the
#      narrow diff falls back to the full set.
#   M2 swallow-everything — widen the case pattern to `*) continue ;;` (skip
#      every path). genuine_unmapped_still_fallback_case must go RED: a
#      genuine unmapped SOURCE file (not housekeeping) is silently excluded
#      instead of tripping the safety net, so the full-set fallback never
#      fires for a diff that is NOT provably covered — a selector that never
#      falls back has stopped proving coverage, which is worse than the bug.
# A top-level insert (outside the function body) is NOT a valid control for
# either mutation — it would not exercise the per-file exclusion at all.
#
# Hermetic: every fixture is a throwaway git repo under mktemp -d; nothing
# under docs/leadv2 or plugins/docs is touched in the real checkout.
# Run: bash test-scope-excludes-nested-housekeeping.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_RUNNER="${SCRIPT_DIR}/run-core-offline.sh"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"

PASS=0; FAIL=0; NOTRUN=0; ERRORS=()
log()    { printf -- '[TEST] %s\n' "$*"; }
pass()   { PASS=$((PASS + 1)); log "PASS: $1"; }
fail()   { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
notrun() { NOTRUN=$((NOTRUN + 1)); log "NOT RUN: $1"; }

FIXTURES=()
cleanup() { local d; for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done; }
trap cleanup EXIT

scope_field() { # <transcript> <field>= -> value
  printf '%s\n' "$1" | grep -o "$2=[^ ]*" | head -1 | cut -d= -f2-
}
executed_from() { # <transcript> -> number of suites actually executed
  printf '%s\n' "$1" \
    | sed -n 's/.*suites passed=\([0-9]*\) failed=\([0-9]*\) missing=\([0-9]*\).*/\1 \2 \3/p' \
    | awk '{ s += $1 + $2 + $3 } END { print s + 0 }'
}

# ── fixture: a throwaway git repo with a copied runner + one real suite ─────
# modes: nested_housekeeping | genuine_unmapped
build_fix() { # <mode> -> sets FIX, DEFS
  local mode="$1"
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/scope-nest-fix.XXXXXX")"
  FIXTURES+=("$FIX")
  mkdir -p "$FIX/plugins/leadv2/scripts" "$FIX/plugins/leadv2/scripts/tests" "$FIX/tests"
  cp "${REAL_RUNNER}" "$FIX/plugins/leadv2/scripts/tests/run-core-offline.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/tests/test-greeble.sh"
  printf 'v1\n' > "$FIX/plugins/leadv2/scripts/greeble.sh"
  DEFS="greeble contract|||bash $FIX/tests/test-greeble.sh"
  git -C "$FIX" init -q
  git -C "$FIX" config user.email scope@test.local
  git -C "$FIX" config user.name scope-test
  git -C "$FIX" symbolic-ref HEAD refs/heads/main
  git -C "$FIX" add -A
  git -C "$FIX" commit -qm base
  git -C "$FIX" checkout -q -b lane
  # the real source change every mode shares: greeble.sh, maps to one suite.
  printf 'v2\n' > "$FIX/plugins/leadv2/scripts/greeble.sh"
  # the nested runtime debris this suite exists to exclude — untracked, two
  # levels under plugins/, exactly the shape lane d2823c51e670 measured.
  mkdir -p "$FIX/plugins/docs/leadv2/.lane-liveness-share/deadbeef01"
  printf '0\n' > "$FIX/plugins/docs/leadv2/.lane-liveness-share/deadbeef01/rc"
  printf '{}\n' > "$FIX/plugins/docs/leadv2/.lane-liveness-share/deadbeef01/result"
  printf '1700000000\n' > "$FIX/plugins/docs/leadv2/.lane-liveness-share/deadbeef01/ts"
  if [[ "$mode" == "genuine_unmapped" ]]; then
    # a real, non-housekeeping file that maps to no suite at all — must still
    # trip the safety net regardless of the nested-docs fix.
    printf 'note\n' > "$FIX/notes.txt"
  fi
  git -C "$FIX" add -A
  git -C "$FIX" commit -qm lane-work
}

run_fix() { # [runner args...] -> transcript, rc in $?
  (
    cd "$FIX" || exit 9
    exec env LEADV2_SUITE_SHARDS=1 \
      LEADV2_SUITE_LOCK_DISABLE=1 \
      LEADV2_SUITE_DEFS_OVERRIDE="$DEFS" \
      bash "$FIX/plugins/leadv2/scripts/tests/run-core-offline.sh" "$@"
  ) 2>&1
}

# ── (a) nested plugins/docs/leadv2/.lane-liveness-share/... never counts as
#        unmapped: a one-file source diff stays narrow (selected=1), not the
#        95-suite fallback ────────────────────────────────────────────────
nested_housekeeping_case() {
  local out rc sel unmapped reason changed
  build_fix nested_housekeeping
  out="$(run_fix --scope changed)"; rc=$?
  sel="$(scope_field "$out" selected)"
  unmapped="$(scope_field "$out" unmapped)"
  reason="$(scope_field "$out" reason)"
  changed="$(scope_field "$out" changed)"
  [[ $rc -eq 0 ]] && pass "nested: exit 0" || { fail "nested: rc=$rc"; return; }
  [[ "$unmapped" == "0" ]] && pass "nested: SCOPE_UNMAPPED_COUNT=0 (nested docs debris excluded)" \
    || fail "nested: unmapped=[$unmapped] — nested plugins/docs/leadv2/.lane-liveness-share counted as unmapped"
  [[ "$sel" == "1" ]] && pass "nested: selected=1 (narrow, not full-set fallback)" \
    || fail "nested: selected=[$sel]"
  [[ "$reason" == "-" ]] && pass "nested: no fallback claimed" \
    || fail "nested: reason=[$reason]"
  [[ "$changed" == "1" ]] && pass "nested: changed=1 (only the real source edit counted)" \
    || fail "nested: changed=[$changed] — housekeeping debris leaked into the changed-file count"
}

# ── (b) a genuine unmapped SOURCE file still forces the full-set fallback —
#        the fix narrows what counts as housekeeping, it does not touch the
#        fallback policy itself ────────────────────────────────────────────
genuine_unmapped_still_fallback_case() {
  local out rc executed unmapped reason
  build_fix genuine_unmapped
  out="$(run_fix --scope changed)"; rc=$?
  executed="$(executed_from "$out")"
  unmapped="$(scope_field "$out" unmapped)"
  reason="$(scope_field "$out" reason)"
  [[ $rc -eq 0 ]] && pass "genuine-unmapped: exit 0" || { fail "genuine-unmapped: rc=$rc"; return; }
  [[ "$executed" == "1" ]] && pass "genuine-unmapped: full curated set executed (1 of 1 defined)" \
    || fail "genuine-unmapped: expected 1 executed (full-set fallback), got $executed"
  [[ "$unmapped" == "1" ]] && pass "genuine-unmapped: SCOPE_UNMAPPED_COUNT=1 (notes.txt still counted)" \
    || fail "genuine-unmapped: unmapped=[$unmapped] — a real unmapped file was swallowed by the housekeeping fix"
  [[ "$reason" == *unmapped_files* ]] && pass "genuine-unmapped: reason names unmapped_files" \
    || fail "genuine-unmapped: reason=[$reason]"
}

# ── (c) one registration, both runners ──────────────────────────────────────
registration_case() {
  local run_all="${REPO_ROOT}/tests/run-all.sh" rows
  if [[ -z "${REPO_ROOT}" || ! -f "${run_all}" ]]; then
    notrun "registration: no tests/run-all.sh in this checkout"
    return
  fi
  rows="$(LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash "${run_all}" 2>/dev/null \
    | grep -E '^run-core-offline(\.sh)?:' | grep -c 'test-scope-excludes-nested-housekeeping.sh')"
  if [[ "${rows}" -ge 1 ]]; then
    pass "registration: run-all lists this suite under the run-core-offline key"
  else
    fail "registration: run-all trigger list has no row for this suite"
  fi
}

nested_housekeeping_case
genuine_unmapped_still_fallback_case
registration_case

printf -- '\n[TEST-RESULT] scope-excludes-nested-housekeeping passed=%d failed=%d notrun=%d\n' "$PASS" "$FAIL" "$NOTRUN"
for e in ${ERRORS[@]+"${ERRORS[@]}"}; do printf -- '  %s\n' "$e"; done
(( FAIL == 0 ))
