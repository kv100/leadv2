#!/usr/bin/env bash
# run-all-triggers: run-all.sh
#
# test-scope-changed-is-deterministic.sh — B6-SCOPE-CHANGED /
# SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01 +
# SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01.
#
# tests/run-all.sh --scope changed used to pick its diff range from the
# checkpoint its PREVIOUS run had written, so the same question twice gave
# different answers (a correctly registered suite could look unregistered
# on the second run — it cost the lead two wrong conclusions in one day),
# and with no checkpoint + no resolvable main/origin/main it silently
# degraded to HEAD~1..HEAD: the last commit only, a plausible wrong answer
# on any multi-commit branch. Now:
#   --scope changed       = stateless <merge-base>..HEAD + uncommitted diff
#   --scope changed-since = checkpoint anchor (the old behaviour, explicit)
#   no anchor at all      = refusal with a named reason (exit 2), never a set
#
# Every assertion below reads run-all's OWN selected set (the [SELECT]
# block, sorted and byte-compared — never a human-readable line a mutant
# could reword), the exit code, or the fake core-offline stub's recorded
# argv.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the marker lines INSIDE scope_changed_
# anchor's body in tests/run-all.sh:
#   M1 scope-changed-mut-1: checkpoint visible under --scope changed again
#      (lie (a) reintroduced) -> case 1 goes RED: the post-checkpoint
#      --scope changed run selects fewer suites than the first; selected-set
#      equality fails.
#   M2 scope-changed-mut-2: unresolvable base degrades to HEAD~1..HEAD
#      (lie (b) reintroduced) -> case 2 goes RED: rc=0 with a selected set
#      and the stub invoked, instead of rc=2 + the named no_base_ref
#      refusal.
# A top-level insert is NOT a valid control: it reddens every case for the
# wrong reason and reads as a pass.
#
# Hermetic: fixtures are throwaway git repos under mktemp -d; nothing under
# docs/leadv2 or the real tests tree is touched or executed.
# Run: bash plugins/leadv2/tests/test-scope-changed-is-deterministic.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ALL_UNDER_TEST="${SCRIPT_DIR}/../../../tests/run-all.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

FIXTURES=()
cleanup() { local d; for d in ${FIXTURES[@]+"${FIXTURES[@]}"}; do rm -rf "$d"; done; }
trap cleanup EXIT

if [[ ! -f "${RUN_ALL_UNDER_TEST}" ]]; then
  fail "run-all.sh not found at ${RUN_ALL_UNDER_TEST}"
  printf 'FAIL: %d, PASS: %d\n' "${FAIL}" "${PASS}"
  exit 1
fi

# ── fixture: throwaway git repo with a copy of the FILE UNDER TEST, a fake
#    core-offline stub that records its argv, and the two fake suites the
#    selection maps to. <branch> pins the init branch: "main" gives the
#    selection a resolvable base; anything else ("trunk") takes it away. ──
new_fixture() { # <branch-name> -> sets FIX, CKPT
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/scope-det-fix.XXXXXX")"
  FIX="$(cd -P "${FIX}" && pwd)"   # macOS TMPDIR symlink: match git's realpath
  FIXTURES+=("${FIX}")
  mkdir -p "${FIX}/tests" "${FIX}/plugins/leadv2/scripts/tests" \
           "${FIX}/plugins/leadv2/scripts/lib" "${FIX}/plugins/leadv2/tests"
  cp "${RUN_ALL_UNDER_TEST}" "${FIX}/tests/run-all.sh"
  cat > "${FIX}/plugins/leadv2/scripts/tests/run-core-offline.sh" <<'STUB'
#!/usr/bin/env bash
printf 'FAKE-CORE-OFFLINE argv=%s\n' "$*"
exit 0
STUB
  chmod +x "${FIX}/plugins/leadv2/scripts/tests/run-core-offline.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${FIX}/plugins/leadv2/scripts/tests/test-leadv2-dummy-b6.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${FIX}/plugins/leadv2/scripts/tests/test-leadv2-second-b6.sh"
  ( cd "${FIX}" \
      && git init -q \
      && git branch -m "$1" \
      && git add -A \
      && git -c user.email=t@local -c user.name=t commit -qm base ) >/dev/null 2>&1
  CKPT="${FIX}/.git/leadv2-run-all-last-checked-sha"
}

commit_file() { # <path> — commit one new file on the current branch
  local path="$1"
  mkdir -p "${FIX}/$(dirname "${path}")"
  printf 'content\n' > "${FIX}/${path}"
  git -C "${FIX}" add "${path}"
  git -C "${FIX}" -c user.email=t@local -c user.name=t commit -qm "add ${path}" >/dev/null 2>&1
}

# selection query: [SELECT] block only, no suites run -> sets OUT, RC, SEL
select_run() { # <scope>
  OUT="$(cd "${FIX}" && LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope "$1" 2>&1)"; RC=$?
  SEL="$(printf '%s\n' "${OUT}" | grep '^\[SELECT\] ' | sort)"
}

sel_has() { printf '%s\n' "${SEL}" | grep -qF "$1"; }   # fixed-string, no regex
out_has() { printf '%s\n' "${OUT}" | grep -qF "$1"; }

# ── case 1 (the symptom): --scope changed is deterministic, checkpoint or no
#    checkpoint; and it never writes one ────────────────────────────────────
new_fixture main
git -C "${FIX}" checkout -q -b work
commit_file "plugins/leadv2/scripts/lib/leadv2-dummy-b6.sh"

select_run changed
[[ ${RC} -eq 0 ]] \
  && pass "case1 run1 rc=0" \
  || fail "case1 run1 rc=${RC}: $(printf '%s' "${OUT}" | tail -2)"
sel_has "test-leadv2-dummy-b6.sh" \
  && pass "case1 run1 selects the dummy suite (registered)" \
  || fail "case1 run1 did NOT select test-leadv2-dummy-b6.sh — selection: ${SEL}"
SEL1="${SEL}"
[[ ! -f "${CKPT}" ]] \
  && pass "case1 --scope changed writes no checkpoint" \
  || fail "case1 --scope changed WROTE ${CKPT} — its answer leaves residue"

# Now CREATE the residue the old lie fed on: a checkpoint from a prior
# changed-since run sitting at HEAD with all branch work already behind it.
select_run changed-since
[[ ${RC} -eq 0 ]] \
  && pass "case1 first changed-since run rc=0 (merge-base fallback)" \
  || fail "case1 first changed-since rc=${RC}"
sel_has "test-leadv2-dummy-b6.sh" \
  && pass "case1 first changed-since falls back to the merge-base (selects dummy)" \
  || fail "case1 first changed-since selected nothing: ${SEL}"
[[ -f "${CKPT}" ]] \
  && pass "case1 changed-since writes the checkpoint (the mechanism survives)" \
  || fail "case1 changed-since did NOT write ${CKPT} — incremental mode is dead"

select_run changed
[[ "${SEL}" == "${SEL1}" ]] \
  && pass "case1 run2 == run1: checkpoint residue does not change the answer" \
  || fail "case1 run2 selection differs from run1 (state leaked):
  run1: ${SEL1}
  run2: ${SEL}"
select_run changed
[[ "${SEL}" == "${SEL1}" ]] \
  && pass "case1 run3 == run1: --scope changed is idempotent" \
  || fail "case1 run3 differs: ${SEL}"

# ── case 3 (property 3): changed-since stays genuinely incremental while
#    changed stays complete ─────────────────────────────────────────────────
commit_file "plugins/leadv2/scripts/lib/leadv2-second-b6.sh"
select_run changed-since
if sel_has "test-leadv2-second-b6.sh" && ! sel_has "test-leadv2-dummy-b6.sh"; then
  pass "case3 changed-since selects only the work SINCE the checkpoint"
else
  fail "case3 changed-since is not incremental (expected second only): ${SEL}"
fi
select_run changed
if sel_has "test-leadv2-dummy-b6.sh" && sel_has "test-leadv2-second-b6.sh"; then
  pass "case3 changed stays complete (both suites) even with a checkpoint present"
else
  fail "case3 changed under-selected with checkpoint present: ${SEL}"
fi

# ── case 4: run-core-offline receives the branch-anchored 'changed' scope
#    under BOTH changed modes (it deliberately has no incremental mode) ────
OUT="$(cd "${FIX}" && bash tests/run-all.sh --scope changed-since 2>&1)"; RC=$?
if [[ ${RC} -eq 0 ]] && out_has "FAKE-CORE-OFFLINE argv=--scope changed" \
   && ! out_has "argv=--scope changed-since"; then
  pass "case4 changed-since forwards 'changed' to run-core-offline (rc=0)"
else
  fail "case4 changed-since forwarding wrong (rc=${RC}): $(printf '%s' "${OUT}" | grep FAKE-CORE || true)"
fi

# ── case 2 (the guard): no resolvable base + multi-commit branch → named
#    refusal, never a silent HEAD~1..HEAD set ───────────────────────────────
new_fixture trunk
commit_file "plugins/leadv2/scripts/lib/leadv2-dummy-b6.sh"   # 2nd commit: HEAD~1 exists — the old fallback's fuel
OUT="$(cd "${FIX}" && bash tests/run-all.sh --scope changed 2>&1)"; RC=$?
[[ ${RC} -eq 2 ]] \
  && pass "case2 unresolvable base refuses (rc=2), not a plausible rc=0" \
  || fail "case2 expected rc=2 refusal, got rc=${RC}: $(printf '%s' "${OUT}" | head -3)"
out_has "FATAL no_base_ref" \
  && pass "case2 refusal names its reason (no_base_ref)" \
  || fail "case2 refusal did not name a reason: ${OUT}"
if printf '%s\n' "${OUT}" | grep -q 'FAKE-CORE-OFFLINE'; then
  fail "case2 refusal ran suites anyway (returned a set): ${OUT}"
else
  pass "case2 refusal returns no selection — nothing ran"
fi

if [[ ${FAIL} -gt 0 ]]; then
  printf '  Failures:\n'
  for e in "${ERRORS[@]}"; do printf '    - %s\n' "${e}"; done
fi
printf 'test-scope-changed-is-deterministic: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
