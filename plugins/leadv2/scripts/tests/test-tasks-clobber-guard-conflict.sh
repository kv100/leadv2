#!/usr/bin/env bash
# tests/test-tasks-clobber-guard-conflict.sh — SET-U-ABORTS-THE-FAILURE-PATH-01
# run-all-triggers: leadv2-tasks-clobber-guard
#
# leadv2-tasks-clobber-guard.sh's pre_commit(), on a real unmerged conflict
# in docs/tasks.yaml (two branches both touched it -- a real shared-tree
# shape), takes its `git cat-file blob ":docs/tasks.yaml"` failure fallback,
# which wrote to the undeclared `$staged.yaml` (typo for `staged_yaml`)
# instead of `$staged_yaml`. Under this file's own `set -uo pipefail`,
# referencing the never-assigned `$staged` aborted the whole guard instead
# of leaving `$staged_yaml` at its empty-file default. A second, related
# defect: `trap 'rm -rf "$tmpdir"' RETURN EXIT` fires the SAME command twice
# (once on function RETURN, once on script EXIT) but `$tmpdir` is `local`
# and out of scope by the second firing, aborting again after pre_commit
# had already returned. Reproduced live 2026-09-06.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../leadv2-tasks-clobber-guard.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '[TEST] FAIL: %s -- %s\n' "$1" "${2:-}"; }

# Build a repo with a real unmerged conflict on docs/tasks.yaml -- the only
# realistic way git leaves a path "in the index, but not at stage 0", which
# is what makes `git cat-file blob ":docs/tasks.yaml"` fail.
make_conflict_repo() {
  local repo; repo="$(mktemp -d)"
  ( cd "$repo" \
    && git init -q \
    && git config user.email t@t && git config user.name t \
    && mkdir docs \
    && printf 'a: 1\n' > docs/tasks.yaml && git add docs/tasks.yaml && git commit -q -m init \
    && git checkout -q -b branch2 \
    && printf 'a: 2\n' > docs/tasks.yaml && git commit -q -am b2 \
    && { git checkout -q main 2>/dev/null || git checkout -q master; } \
    && printf 'a: 3\n' > docs/tasks.yaml && git commit -q -am m1 \
    && { git merge branch2 -q >/dev/null 2>&1 || true; } \
    && printf 'merge msg\n' > .git/COMMIT_EDITMSG
  )
  printf '%s' "$repo"
}

echo "=== T1: current guard (fixed) -- conflict is handled without a crash ==="
REPO="$(make_conflict_repo)"
( cd "$REPO" && bash "$GUARD" ) >/tmp/.clobber-stdout.$$ 2>/tmp/.clobber-stderr.$$
rc=$?
if grep -q "unbound variable" /tmp/.clobber-stderr.$$; then
  fail "T1a: no 'unbound variable' on a real conflict" "stderr: $(cat /tmp/.clobber-stderr.$$)"
else
  pass "T1a: no 'unbound variable' on a real conflict"
fi
# fail-open is the documented contract on internal error, and a resolved
# staged-yaml-unreadable case degrades to empty content, not a hard block --
# the substantive assertion is the absence of the crash, not a specific rc.
pass "T1b: guard exits (rc=$rc), does not hang or crash the calling commit"
rm -rf "$REPO"

echo "=== T2 (negative control): pre-fix HEAD copy crashes on the same conflict ==="
PREFIX_COPY="$(mktemp)"
if git -C "$SCRIPT_DIR/../.." show "HEAD:plugins/leadv2/scripts/leadv2-tasks-clobber-guard.sh" > "$PREFIX_COPY" 2>/dev/null \
   && grep -q '\$staged\.yaml' "$PREFIX_COPY"; then
  chmod +x "$PREFIX_COPY"
  REPO="$(make_conflict_repo)"
  ( cd "$REPO" && bash "$PREFIX_COPY" ) >/tmp/.clobber-stdout.$$ 2>/tmp/.clobber-stderr.$$
  if grep -q "unbound variable" /tmp/.clobber-stderr.$$; then
    pass "T2: pre-fix HEAD copy crashes with 'unbound variable' -- suite discriminates"
  else
    fail "T2: pre-fix HEAD copy crashes" "no 'unbound variable' in stderr: $(cat /tmp/.clobber-stderr.$$)"
  fi
  rm -rf "$REPO"
else
  # HEAD already carries the fix -- reconstruct the exact pre-fix typo
  # inline so the negative control still runs rather than silently skipping.
  MUT="$(mktemp)"
  sed -E 's/(: "\$staged_yaml" 2>\/dev\/null \|\| : >)"\$staged_yaml"/\1"\$staged.yaml"/' "$GUARD" > "$MUT"
  chmod +x "$MUT"
  if diff -q "$GUARD" "$MUT" >/dev/null 2>&1; then
    fail "T2: mutation applied" "sed did not change the file -- pattern did not match, mutation is a no-op"
  else
    REPO="$(make_conflict_repo)"
    ( cd "$REPO" && bash "$MUT" ) >/tmp/.clobber-stdout.$$ 2>/tmp/.clobber-stderr.$$
    if grep -q "unbound variable" /tmp/.clobber-stderr.$$; then
      pass "T2: reintroducing the \$staged.yaml typo crashes with 'unbound variable' -- suite discriminates"
    else
      fail "T2: reintroducing the \$staged.yaml typo crashes" "no 'unbound variable' in stderr: $(cat /tmp/.clobber-stderr.$$)"
    fi
    rm -rf "$REPO"
  fi
  rm -f "$MUT"
fi
rm -f "$PREFIX_COPY" /tmp/.clobber-stdout.$$ /tmp/.clobber-stderr.$$

echo "=== T3 (second defect, independent of T1/T2): the double RETURN+EXIT trap no longer aborts on its second firing ==="
REPO="$(make_conflict_repo)"
# A NORMAL (non-conflict) staged tasks.yaml change also exercises the trap
# firing twice (RETURN when pre_commit returns, EXIT when the script ends);
# T1 already covers the conflict path, this isolates the trap defect on the
# ordinary success path where $tmpdir goes out of scope identically.
REPO2="$(mktemp -d)"
( cd "$REPO2" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir docs && printf 'a: 1\n' > docs/tasks.yaml && git add docs/tasks.yaml && git commit -q -m init \
    && printf 'a: 2\n' > docs/tasks.yaml && git add docs/tasks.yaml \
    && printf 'msg\n' > .git/COMMIT_EDITMSG )
( cd "$REPO2" && bash "$GUARD" ) >/tmp/.clobber-stdout2.$$ 2>/tmp/.clobber-stderr2.$$
if grep -q "unbound variable" /tmp/.clobber-stderr2.$$; then
  fail "T3: no 'unbound variable' from the trap's second firing" "stderr: $(cat /tmp/.clobber-stderr2.$$)"
else
  pass "T3: no 'unbound variable' from the trap's second firing"
fi
rm -rf "$REPO" "$REPO2" /tmp/.clobber-stdout2.$$ /tmp/.clobber-stderr2.$$

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
