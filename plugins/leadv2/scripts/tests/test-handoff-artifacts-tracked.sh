#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: gitignore
# test-handoff-artifacts-tracked.sh — HANDOFF-ARTIFACTS-GITIGNORED-01
#
# Proves docs/handoff/<id>/ proof artifacts (report.md, brief*.md, roundN-red/
# negative-control output) are trackable with a plain `git add` (no -f) while
# per-run scratch (logs, session state, etc.) stays default-ignored, and that
# deleting a TRACKED proof artifact shows up in `git status` — the
# second-order fix (a lane could otherwise destroy another lane's evidence
# invisibly).
#
# Runs entirely inside fixture repos under a temp dir, never against this
# repo. Each fixture copies the REAL .gitignore from repo root (the file
# under claim) rather than reimplementing its rules, so a future edit that
# reverts the allowlist is caught here, not just by inspection.
#
# Negative control: a mutated copy of .gitignore (the pre-fix blanket
# `docs/handoff/*/*` with the allowlist lines stripped) must fail check 1 —
# proving this suite actually asserts on `git add` behaviour and isn't a
# printed line with no bearing on the exit code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "FAIL: cannot resolve repo root from ${SCRIPT_DIR} via git" >&2
  exit 1
fi
GITIGNORE_SRC="${ROOT}/.gitignore"
if [[ ! -f "${GITIGNORE_SRC}" ]]; then
  echo "FAIL: ${GITIGNORE_SRC} missing" >&2
  exit 1
fi

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

FIXTURES=()
cleanup() {
  local d
  for d in "${FIXTURES[@]:-}"; do
    [[ -n "${d}" && -d "${d}" ]] && rm -rf "${d}"
  done
}
trap cleanup EXIT

# new_fixture [gitignore_path] -> prints fixture dir, git-inits it with the
# given .gitignore (defaults to the real one under claim).
new_fixture() {
  local src="${1:-${GITIGNORE_SRC}}" d
  d="$(mktemp -d)"
  FIXTURES+=("${d}")
  ( cd "${d}" && git init -q && git config user.email t@example.com && git config user.name t )
  cp "${src}" "${d}/.gitignore"
  printf '%s\n' "${d}"
}

seed_artifacts() { # <fixture-dir>
  local d="$1"
  mkdir -p "${d}/docs/handoff/FIXTURE-ID/round1-red"
  printf 'proof\n' > "${d}/docs/handoff/FIXTURE-ID/round1-red/output.txt"
  printf '# report\n' > "${d}/docs/handoff/FIXTURE-ID/report.md"
  printf '# brief\n' > "${d}/docs/handoff/FIXTURE-ID/brief.md"
  printf 'transient dispatch output\n' > "${d}/docs/handoff/FIXTURE-ID/dispatch.log"
}

# ── 1: roundN-red artifact addable without -f ───────────────────────────────
d="$(new_fixture)"; seed_artifacts "${d}"
add_err="$(cd "${d}" && git add docs/handoff/FIXTURE-ID/round1-red/output.txt 2>&1)"
staged="$(cd "${d}" && git diff --cached --name-only)"
if [[ "${staged}" == *"round1-red/output.txt"* ]]; then
  pass "1: roundN-red/ artifact staged by plain git add (no -f)"
else
  fail "1: roundN-red/ artifact not staged (git add said: ${add_err})"
fi

# ── 2: report.md and brief.md addable without -f ────────────────────────────
d="$(new_fixture)"; seed_artifacts "${d}"
add_err="$(cd "${d}" && git add docs/handoff/FIXTURE-ID/report.md docs/handoff/FIXTURE-ID/brief.md 2>&1)"
staged="$(cd "${d}" && git diff --cached --name-only)"
if [[ "${staged}" == *"report.md"* && "${staged}" == *"brief.md"* ]]; then
  pass "2: report.md + brief.md staged by plain git add (no -f)"
else
  fail "2: report.md/brief.md not staged (git add said: ${add_err}; staged: ${staged})"
fi

# ── 3: transient dispatch log stays ignored ─────────────────────────────────
d="$(new_fixture)"; seed_artifacts "${d}"
if ( cd "${d}" && git check-ignore -q docs/handoff/FIXTURE-ID/dispatch.log ); then
  pass "3a: transient dispatch.log still matched by check-ignore"
else
  fail "3a: dispatch.log is NOT ignored (churn would flood git status)"
fi
( cd "${d}" && git add docs/handoff/FIXTURE-ID/dispatch.log ) 2>/dev/null
staged="$(cd "${d}" && git diff --cached --name-only)"
if [[ "${staged}" != *"dispatch.log"* ]]; then
  pass "3b: plain git add is a no-op on ignored dispatch.log"
else
  fail "3b: dispatch.log got staged despite the ignore rule"
fi

# ── 4: deleting a tracked proof artifact shows in git status ───────────────
d="$(new_fixture)"; seed_artifacts "${d}"
( cd "${d}" \
  && git add docs/handoff/FIXTURE-ID/round1-red/output.txt docs/handoff/FIXTURE-ID/report.md \
  && git commit -qm seed )
rm "${d}/docs/handoff/FIXTURE-ID/round1-red/output.txt"
st="$(cd "${d}" && git status --short)"
if [[ "${st}" == *"D docs/handoff/FIXTURE-ID/round1-red/output.txt"* ]]; then
  pass "4: deleting a tracked proof artifact shows in git status"
else
  fail "4: deletion of tracked proof artifact not visible (git status: ${st})"
fi

# ── RED control: strip the allowlist, restore the pre-fix blanket ignore ───
# Named mutation: remove every `!docs/handoff/*/...` negation line HAN-01
# added. This reproduces exactly the defect this task fixes — un-ignore
# lines gone, `docs/handoff/*/*` blanket-ignores everything again — and must
# fail check 1's assertion (roundN-red/ no longer stages without -f).
d="$(new_fixture)"
mut_gitignore="${d}/.gitignore"
grep -v '^!docs/handoff/\*/' "${mut_gitignore}" > "${mut_gitignore}.tmp"
mv "${mut_gitignore}.tmp" "${mut_gitignore}"
seed_artifacts "${d}"
( cd "${d}" && git add docs/handoff/FIXTURE-ID/round1-red/output.txt ) 2>/dev/null
staged="$(cd "${d}" && git diff --cached --name-only)"
if [[ "${staged}" != *"round1-red/output.txt"* ]]; then
  pass "RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)"
else
  fail "RED control: mutation did NOT block git add — check 1 is not a real assertion"
fi

printf 'test-handoff-artifacts-tracked: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
