#!/usr/bin/env bash
# tests/test-control-plane-merge.sh — CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01
#
# Proves, end to end and against the REAL scripts, that merging an old branch
# no longer needs hand-holding and can no longer destroy the control-plane
# symlinks:
#   T1  leadv2-merge-old-branch.sh finishes a distinct-types (symlink vs file)
#       merge mechanically: parked ~<branch> file dropped, ours symlink kept,
#       the branch's REAL code change still lands, merge committed, guard green.
#   T2  a conflict outside the control-plane shape is NOT swallowed: the merge
#       is left in progress, the script exits 1 and names the file.
#   T3  the guard fires: a deliberately broken invariant (one symlink replaced
#       by a regular file) makes leadv2-control-plane-merge-driver.sh --verify
#       exit 1. A guard never observed failing is not known to work.
#   T4  leadv2-lane-salvage.sh's exit code carries the verdict:
#       verdict=conflict → rc 3, salvaged_red → rc 1, salvaged_green → rc 0.
#       (2026-09-04 defect: verdict=conflict carried=0/4 exited 0.)
#
# Every case runs in its own `git init` scratch repo (never `git worktree add`
# into the live repo); the live checkout is only read.
#
# Negative control for this lane: the committed artifact under
# docs/handoff/CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01/mutation-control/
# (leadv2-mutation-control.sh output; mutating the wrapper's `git rm` line
# turns T1 red).
#
# run-all-triggers: leadv2-lane-salvage.sh leadv2-merge-old-branch.sh leadv2-control-plane-merge-driver.sh
#
# Run: bash plugins/leadv2/scripts/tests/test-control-plane-merge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIVER="${PLUGIN_DIR}/scripts/leadv2-control-plane-merge-driver.sh"
MERGER="${PLUGIN_DIR}/scripts/leadv2-merge-old-branch.sh"
SALVAGE="${PLUGIN_DIR}/scripts/leadv2-lane-salvage.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

SCRATCH_ROOT=""
cleanup() {
  [[ -n "${SCRATCH_ROOT}" && -d "${SCRATCH_ROOT}" ]] && rm -rf "${SCRATCH_ROOT}"
  return 0
}
trap cleanup EXIT

# ── fixture helpers ───────────────────────────────────────────────────────────
# A scratch repo whose control plane is 3 symlinks (2 pinned in
# .gitattributes + 1 unpinned) so the guard's count invariant is checkable at
# small scale; LEADV2_CP_EXPECTED_LINKS=3.
R=""   # current fixture repo dir (a global: cd inside $() does not survive)
new_scratch() { # <name> -> sets R, leaves cwd at R
  SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cpmerge-test.XXXXXX")"
  R="${SCRATCH_ROOT}/$1"
  mkdir -p "${R}" && cd "${R}" || return 1
  git init -q .
  git symbolic-ref HEAD refs/heads/main   # the salvage script demands a 'main'
  git config user.email t@t.local
  git config user.name t
  # old-branch state: control plane as ordinary files
  mkdir -p docs/leadv2 src tests
  printf 'active-v1\n' > docs/leadv2/active.yaml
  printf 'bus-v1\n'    > docs/leadv2/bus.jsonl
  printf 'other-v1\n'  > docs/leadv2/other.jsonl
  printf 'code-v1\n'   > src/feat.txt
  printf '#!/usr/bin/env bash\necho suite-stub rc=0\nexit 0\n' > tests/run-all.sh
  chmod +x tests/run-all.sh
  git add -A
  git commit -qm "base: control plane as regular files"
}

to_control_plane() { # in cwd: swap the control plane to symlinks + pin attrs
  rm docs/leadv2/active.yaml docs/leadv2/bus.jsonl docs/leadv2/other.jsonl
  ln -s ../../.state/active.yaml docs/leadv2/active.yaml
  ln -s ../../.state/bus.jsonl    docs/leadv2/bus.jsonl
  ln -s ../../.state/other.jsonl  docs/leadv2/other.jsonl
  cat > .gitattributes <<'EOF'
docs/leadv2/active.yaml merge=leadv2-control-plane
docs/leadv2/bus.jsonl merge=leadv2-control-plane
EOF
  git add -A
  git commit -qm "main: control plane moves out of the tree (symlinks)"
}

# ── T1/T2: the merge finisher ─────────────────────────────────────────────────
test_merge_finisher() {
  new_scratch t1 || { fail "T1 fixture"; return; }

  # old branch: still regular files, plus REAL work main must not lose
  git checkout -qb stale-lane
  printf 'code-v2-from-stale-lane\n' > src/feat.txt
  git add -A && git commit -qm "stale lane: real work"
  git checkout -q master 2>/dev/null || git checkout -q main
  to_control_plane
  mkdir -p .state && printf 'live-active\n' > .state/active.yaml

  # T1: mechanical merge, no hand-holding
  export LEADV2_CP_EXPECTED_LINKS=3
  local out rc
  out="$(bash "${MERGER}" stale-lane 2>&1)"; rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    fail "T1 wrapper exited ${rc}: $(printf '%s' "${out}" | tail -3)"
    return
  fi
  pass "T1 wrapper exit 0"
  if [[ -L docs/leadv2/active.yaml && -L docs/leadv2/bus.jsonl ]]; then
    pass "T1 control plane kept as symlinks"
  else
    fail "T1 symlink destroyed: $(ls -la docs/leadv2/active.yaml)"
  fi
  if [[ "$(cat src/feat.txt)" == "code-v2-from-stale-lane" ]]; then
    pass "T1 branch's real work landed"
  else
    fail "T1 branch work lost: $(cat src/feat.txt)"
  fi
  if git ls-files | grep -q 'active.yaml~'; then
    fail "T1 parked ~<branch> file still tracked: $(git ls-files | grep '~')"
  else
    pass "T1 parked file dropped from the index"
  fi
  if [[ "$(git rev-parse --verify -q MERGE_HEAD 2>/dev/null || echo none)" == "none" ]] \
       && [[ "$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')" -eq 0 ]]; then
    pass "T1 merge committed, tree clean"
  else
    fail "T1 merge not concluded: MERGE_HEAD=$(git rev-parse -q --verify MERGE_HEAD || echo none) dirty=$(git status --porcelain | head -2 | tr '\n' ';')"
  fi
  if "${DRIVER}" --verify >/dev/null 2>&1; then
    pass "T1 guard green after merge"
  else
    fail "T1 guard red after a good merge"
  fi

  # T2: a non-control-plane conflict must NOT be swallowed
  git checkout -qb conflicty
  printf 'theirs\n' > src/feat.txt && git add -A && git commit -qm "stale: edits src/feat.txt"
  git checkout -q master 2>/dev/null || git checkout -q main
  printf 'ours\n' > src/feat.txt && git add -A && git commit -qm "main: edits src/feat.txt"
  out="$(bash "${MERGER}" conflicty 2>&1)"; rc=$?
  if [[ "${rc}" -eq 1 ]] && git diff --name-only --diff-filter=U | grep -q 'src/feat.txt' \
       && printf '%s' "${out}" | grep -q 'unresolved'; then
    pass "T2 foreign conflict reported, exit 1, merge left in progress"
  else
    fail "T2 foreign conflict mishandled rc=${rc}: $(printf '%s' "${out}" | tail -2)"
  fi
  git merge --abort 2>/dev/null || true
  cd /; rm -rf "${R}"
}

# ── T3: the guard actually fires ──────────────────────────────────────────────
test_guard_fires() {
  local r out rc
  new_scratch t3
  to_control_plane
  export LEADV2_CP_EXPECTED_LINKS=3
  # break the invariant: replace one symlink with a regular file
  rm docs/leadv2/active.yaml
  printf 'regular file where a symlink must be\n' > docs/leadv2/active.yaml
  out="$(bash "${DRIVER}" --verify 2>&1)"; rc=$?
  if [[ "${rc}" -eq 1 ]] && printf '%s' "${out}" | grep -q 'GUARD FAIL'; then
    pass "T3 guard fires on a replaced symlink (rc=1): $(printf '%s' "${out}" | head -1)"
  else
    fail "T3 guard did NOT fire (rc=${rc}): $(printf '%s' "${out}" | tail -1)"
  fi
  # also: a silently missing symlink drops the count below expected
  rm docs/leadv2/bus.jsonl
  out="$(bash "${DRIVER}" --verify 2>&1)"; rc=$?
  if [[ "${rc}" -eq 1 ]]; then
    pass "T3 guard fires on a low symlink count"
  else
    fail "T3 guard did NOT fire on count=2 (rc=${rc})"
  fi
  cd /; rm -rf "${R}"
}

# ── T4: salvage exit code carries the verdict ─────────────────────────────────
salvage_fixture() { # stub rc -> sets R; branch worktree-SALVTEST holds lane work
  local stub_rc="$1"
  new_scratch "t4-rc${stub_rc}"
  printf '#!/usr/bin/env bash\necho stub-rc=%s\nexit %s\n' "${stub_rc}" "${stub_rc}" > tests/run-all.sh
  chmod +x tests/run-all.sh
  git add -A && git commit -qm "suite stub rc=${stub_rc}"
  git checkout -qb worktree-SALVTEST
  git checkout -q main
}

test_salvage_exit_codes() {
  local out rc
  # conflict → 3
  salvage_fixture 0
  git checkout -q worktree-SALVTEST
  printf 'lane-side\n' > src/feat.txt && git add -A && git commit -qm "lane: edits src/feat.txt"
  git checkout -q master 2>/dev/null || git checkout -q main
  printf 'main-side\n' > src/feat.txt && git add -A && git commit -qm "main: edits src/feat.txt"
  out="$(bash "${SALVAGE}" SALVTEST --suite-timeout 60 2>&1)"; rc=$?
  if [[ "${rc}" -eq 3 ]] && printf '%s' "${out}" | grep -q 'verdict=conflict'; then
    pass "T4 verdict=conflict → exit 3"
  else
    fail "T4 conflict verdict rc=${rc} (want 3): $(printf '%s' "${out}" | grep SALVAGE_RESULT)"
  fi
  cd /; rm -rf "${R}"

  # green → 0
  salvage_fixture 0
  git checkout -q worktree-SALVTEST
  printf 'new-work\n' > src/only-on-lane.txt && git add -A && git commit -qm "lane: new work"
  git checkout -q master 2>/dev/null || git checkout -q main
  out="$(bash "${SALVAGE}" SALVTEST --suite-timeout 120 2>&1)"; rc=$?
  if [[ "${rc}" -eq 0 ]] && printf '%s' "${out}" | grep -q 'verdict=salvaged_green'; then
    pass "T4 verdict=salvaged_green → exit 0"
  else
    fail "T4 green verdict rc=${rc} (want 0): $(printf '%s' "${out}" | grep SALVAGE_RESULT)"
  fi
  cd /; rm -rf "${R}"

  # red → 1
  salvage_fixture 7
  git checkout -q worktree-SALVTEST
  printf 'new-work\n' > src/only-on-lane.txt && git add -A && git commit -qm "lane: new work"
  git checkout -q master 2>/dev/null || git checkout -q main
  out="$(bash "${SALVAGE}" SALVTEST --suite-timeout 120 2>&1)"; rc=$?
  if [[ "${rc}" -eq 1 ]] && printf '%s' "${out}" | grep -q 'verdict=salvaged_red'; then
    pass "T4 verdict=salvaged_red → exit 1"
  else
    fail "T4 red verdict rc=${rc} (want 1): $(printf '%s' "${out}" | grep SALVAGE_RESULT)"
  fi
  cd /; rm -rf "${R}"
}

test_merge_finisher
test_guard_fires
test_salvage_exit_codes

log "----------------------------------------"
log "pass=${PASS} fail=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "${e}"; done
  exit 1
fi
exit 0
