#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: gitignore
# test-handoff-docs-not-leaked.sh — HANDOFF-DOCS-INVISIBLE-IN-LANES-01
#
# test-handoff-artifacts-tracked.sh (HANDOFF-ARTIFACTS-GITIGNORED-01) proves
# authored docs/handoff/<id>/ artifacts are ADDABLE (the .gitignore allowlist
# lets a plain `git add` stage them). It does not catch the actual regression
# this task exists for: a worker writes brief.md / fix-round-N.md /
# continue-round-N.md and simply never runs `git add` at all. Because a git
# worktree only ever contains TRACKED content, that file is invisible to
# every other checkout of this repo (other lanes, the lead's own worktree)
# until someone remembers to add it — the lead was doing this by hand with
# `git add -f` per lane before this task.
#
# This suite proves a detector exists that flags an authored doc sitting
# untracked-but-not-ignored in docs/handoff/, and demonstrates it red (leak
# present) -> green (leak tracked) on a fixture, per the task's DoD #3.
#
# Runs entirely inside fixture repos under a temp dir, never against this
# repo's own working tree.
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

new_fixture() { # -> prints fixture dir, git-inits it with the real .gitignore
  local d
  d="$(mktemp -d)"
  FIXTURES+=("${d}")
  ( cd "${d}" && git init -q && git config user.email t@example.com && git config user.name t )
  cp "${GITIGNORE_SRC}" "${d}/.gitignore"
  printf '%s\n' "${d}"
}

# find_leaked_handoff_docs <repo-dir> — prints, one per line, every path
# under docs/handoff/ that is (a) untracked, (b) NOT excluded by .gitignore
# (i.e. `git add` would stage it), and (c) matches an authored-doc naming
# convention. Empty output = clean.
find_leaked_handoff_docs() {
  local d="$1" f base
  ( cd "${d}" && git ls-files --others --exclude-standard -- docs/handoff ) | while IFS= read -r f; do
    case "${f}" in
      */round*-red/*) printf '%s\n' "${f}"; continue ;;
    esac
    base="$(basename "${f}")"
    case "${base}" in
      brief.md|brief-*.md|report.md|context.yaml|architect-prepass.md|.gate1-passed|divergence.md) \
        printf '%s\n' "${f}" ;;
      fix-round-*.md|continue-round-*.md) printf '%s\n' "${f}" ;;
    esac
  done
}

seed_docs() { # <fixture-dir>
  local d="$1"
  mkdir -p "${d}/docs/handoff/FIXTURE-ID/round1-red"
  printf '# brief\n' > "${d}/docs/handoff/FIXTURE-ID/brief.md"
  printf 'continuation notes\n' > "${d}/docs/handoff/FIXTURE-ID/continue-round-2.md"
  printf 'proof\n' > "${d}/docs/handoff/FIXTURE-ID/round1-red/output.txt"
  printf 'transient dispatch output\n' > "${d}/docs/handoff/FIXTURE-ID/dispatch.log"
}

# ── 1: RED — freshly-written authored docs, never `git add`ed, are flagged ─
d="$(new_fixture)"; seed_docs "${d}"
leaked="$(find_leaked_handoff_docs "${d}")"
if [[ "${leaked}" == *"docs/handoff/FIXTURE-ID/brief.md"* && "${leaked}" == *"continue-round-2.md"* && "${leaked}" == *"round1-red/output.txt"* ]]; then
  pass "1: RED — untracked brief.md, continue-round-2.md, round1-red/ proof all flagged as leaked"
else
  fail "1: RED — detector missed a leaked authored doc (got: ${leaked})"
fi

# ── 2: generated scratch never shows up, tracked or not ────────────────────
if [[ "${leaked}" != *"dispatch.log"* ]]; then
  pass "2: transient dispatch.log (gitignored) is not reported as a leak"
else
  fail "2: dispatch.log false-positived as a leak"
fi

# ── 3: GREEN — tracking the flagged docs clears the report ─────────────────
( cd "${d}" && git add docs/handoff/FIXTURE-ID/brief.md docs/handoff/FIXTURE-ID/continue-round-2.md \
    docs/handoff/FIXTURE-ID/round1-red/output.txt )
leaked_after="$(find_leaked_handoff_docs "${d}")"
if [[ -z "${leaked_after}" ]]; then
  pass "3: GREEN — after \`git add\`, the same fixture reports zero leaks"
else
  fail "3: GREEN — leak report still non-empty after tracking (got: ${leaked_after})"
fi

# ── 4: partial tracking still flags what's left behind ─────────────────────
d="$(new_fixture)"; seed_docs "${d}"
( cd "${d}" && git add docs/handoff/FIXTURE-ID/brief.md )
leaked_partial="$(find_leaked_handoff_docs "${d}")"
if [[ "${leaked_partial}" != *"brief.md"* && "${leaked_partial}" == *"continue-round-2.md"* ]]; then
  pass "4: tracking one doc clears it while the still-untracked one stays flagged"
else
  fail "4: partial-tracking case behaved wrong (got: ${leaked_partial})"
fi

# ── 5: the real checkout is clean, too ─────────────────────────────────────
# The fixture checks prove the detector moves red -> green. This live check is
# the regression guard: when a future worker leaves an authored handoff doc in
# this checkout untracked, this suite fails instead of silently passing only on
# its private fixture.
live_leaked="$(find_leaked_handoff_docs "${ROOT}")"
if [[ -z "${live_leaked}" ]]; then
  pass "5: live checkout has no untracked authored handoff docs"
else
  fail "5: live checkout has leaked authored handoff docs: ${live_leaked}"
fi

printf 'test-handoff-docs-not-leaked: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
