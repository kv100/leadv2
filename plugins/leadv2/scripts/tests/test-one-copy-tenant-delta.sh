#!/usr/bin/env bash
# tests/test-one-copy-tenant-delta.sh — PLUGIN-SELF-SUFFICIENT-TENANTS-ONLY-
# DELTA-01 DoD suite for leadv2-one-copy-convert.sh --check's tenant-delta
# coverage: every live repo's .claude/<subroot> is a tenant tree, an
# undeclared REAL copy of a plugin-owned file gates (identical or diverged),
# caches and lane worktrees never count, and the exception list cannot rot.
#
# Runs entirely against a disposable scratch fixture (own canonical root
# with the real convert script COPIED into it so CANONICAL_ROOT resolves
# inside the fixture — same containment pattern as
# test-one-copy-drift-hook-postsync.sh; the copy is made fresh each run so
# it cannot drift). Only --check is exercised.
#
# Run: bash scripts/tests/test-one-copy-tenant-delta.sh
# run-all-triggers: leadv2-one-copy-convert one-copy-exceptions

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONVERT="${SCRIPT_DIR}/leadv2-one-copy-convert.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${CONVERT}" 2>/dev/null; then pass "bash -n leadv2-one-copy-convert.sh"; else fail "bash -n leadv2-one-copy-convert.sh"; fi

# mk_fixture -> prints "tmp" with:
#   $tmp/canon/                       fixture canonical root (.git marker)
#   $tmp/canon/plugins/leadv2/{scripts,agents,ref,config,contracts}
#   $tmp/canon/plugins/leadv2/scripts/leadv2-one-copy-convert.sh (fresh copy)
#   $tmp/shared/leadv2-shared/scripts, $tmp/shared/agents-shared  (empty)
#   $tmp/repo-a/.claude/ref           live-repo tenant tree
#   $tmp/repo-b                       repo listed in the yaml WITHOUT .claude
#   $tmp/crossrepo.yaml               fixture repo registry
#   $tmp/exceptions.txt               empty (each case rewrites it)
mk_fixture() {
  local tmp; tmp="$(lv2_mktemp_dir tenant-delta-fixture)"
  local canon="${tmp}/canon"
  mkdir -p "${canon}/.git" \
           "${canon}/plugins/leadv2/scripts" "${canon}/plugins/leadv2/agents" \
           "${canon}/plugins/leadv2/ref" "${canon}/plugins/leadv2/config" \
           "${canon}/plugins/leadv2/contracts" \
           "${tmp}/shared/leadv2-shared/scripts" "${tmp}/shared/agents-shared" \
           "${tmp}/repo-a/.claude/ref" "${tmp}/repo-b"
  cp "${CONVERT}" "${canon}/plugins/leadv2/scripts/leadv2-one-copy-convert.sh"
  cat > "${tmp}/crossrepo.yaml" <<YAML
repos:
  repo-a:
    path: ${tmp}/repo-a

  repo-b:
    path: ${tmp}/repo-b
YAML
  : > "${tmp}/exceptions.txt"
  printf '%s' "$tmp"
}

run_check() { # <tmp> -> sets RC, OUT
  local tmp="$1"
  OUT="$(
    LEADV2_ONE_COPY_SCRIPTS_SHARED_ROOT="${tmp}/shared/leadv2-shared/scripts" \
    LEADV2_ONE_COPY_SCRIPTS_CANONICAL_ROOT="${tmp}/canon/plugins/leadv2/scripts" \
    LEADV2_ONE_COPY_AGENTS_SHARED_ROOT="${tmp}/shared/agents-shared" \
    LEADV2_ONE_COPY_AGENTS_CANONICAL_ROOT="${tmp}/canon/plugins/leadv2/agents" \
    LEADV2_ONE_COPY_CROSS_REPO_CONFIG="${tmp}/crossrepo.yaml" \
    LEADV2_ONE_COPY_PROJECT_ROOTS=1 \
    LEADV2_ONE_COPY_EXCEPTIONS_FILE="${tmp}/exceptions.txt" \
    bash "${tmp}/canon/plugins/leadv2/scripts/leadv2-one-copy-convert.sh" --check 2>&1
  )"
  RC=$?
}

# ── T1 (acceptance 1a): identical real copy in a repo tenant tree → named, exit 1
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
cp "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml" "${tmp}/repo-a/.claude/ref/leadv2-main-model.yaml"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'REGRESSION:.*\.claude/ref/leadv2-main-model\.yaml is a real file' <<<"$OUT"; then
  pass "T1 identical real copy in repo .claude/ref -> REGRESSION, exit 1"
else
  fail "T1 identical real copy in repo .claude/ref -> REGRESSION, exit 1 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T1b (acceptance 1b): diverged real copy → named, exit 1 ────────────────
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
printf 'model: tenant-diverged\n' > "${tmp}/repo-a/.claude/ref/leadv2-main-model.yaml"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'DIVERGED:.*\.claude/ref/leadv2-main-model\.yaml differs' <<<"$OUT"; then
  pass "T1b diverged real copy in repo .claude/ref -> DIVERGED, exit 1"
else
  fail "T1b diverged real copy in repo .claude/ref -> DIVERGED, exit 1 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T2 (acceptance 2, paired to T1b): same file + one exception line →
#    EXPECTED-OVERRIDE, no violation, exit 0. The ONLY difference from T1b
#    is the exception-list line.
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
printf 'model: tenant-diverged\n' > "${tmp}/repo-a/.claude/ref/leadv2-main-model.yaml"
printf 'project/repo-a/ref/leadv2-main-model.yaml\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'EXPECTED-OVERRIDE:.*repo-a/.claude/ref/leadv2-main-model\.yaml' <<<"$OUT" \
   && ! grep -qE 'DIVERGED:|REGRESSION:' <<<"$OUT"; then
  pass "T2 same declared copy -> EXPECTED-OVERRIDE, exit 0 (paired to T1b)"
else
  fail "T2 same declared copy -> EXPECTED-OVERRIDE, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T3 (acceptance 3): __pycache__/worktrees copies are never violations ──
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
mkdir -p "${tmp}/repo-a/.claude/ref/__pycache__" "${tmp}/repo-a/.claude/ref/worktrees/lane-1"
cp "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml" "${tmp}/repo-a/.claude/ref/__pycache__/leadv2-main-model.yaml"
cp "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml" "${tmp}/repo-a/.claude/ref/worktrees/lane-1/leadv2-main-model.yaml"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && ! grep -qE '__pycache__|worktrees' <<<"$OUT" \
   && grep -q 'root project/repo-a/ref: files=0 ' <<<"$OUT"; then
  pass "T3 __pycache__/worktrees copies pruned, not violations, exit 0"
else
  fail "T3 __pycache__/worktrees copies pruned, not violations, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T4 (acceptance 4): exception line whose canonical twin is gone → ROTTEN, exit 1
tmp="$(mk_fixture)"
printf 'agents/gone.md\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'ROTTEN-EXCEPTION: agents/gone\.md' <<<"$OUT"; then
  pass "T4 exception line without canonical twin -> ROTTEN-EXCEPTION, exit 1"
else
  fail "T4 exception line without canonical twin -> ROTTEN-EXCEPTION, exit 1 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T5 (edge): tenant-only file, no canonical twin -> not a violation ─────
tmp="$(mk_fixture)"
printf 'note: repo-native\n' > "${tmp}/repo-a/.claude/ref/tenant-only.yaml"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && ! grep -qE 'REGRESSION:|DIVERGED:|BADLINK:|ROTTEN' <<<"$OUT"; then
  pass "T5 tenant-only file (no canonical twin) -> info, exit 0"
else
  fail "T5 tenant-only file (no canonical twin) -> info, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T6 (edge): symlink pointing outside canonical -> BADLINK, exit 1 ──────
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
printf 'model: elsewhere\n' > "${tmp}/elsewhere.yaml"
ln -sfn "${tmp}/elsewhere.yaml" "${tmp}/repo-a/.claude/ref/leadv2-main-model.yaml"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'BADLINK:.*\.claude/ref/leadv2-main-model\.yaml' <<<"$OUT"; then
  pass "T6 symlink not into canonical -> BADLINK, exit 1"
else
  fail "T6 symlink not into canonical -> BADLINK, exit 1 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T7 (edge): repo in the yaml without .claude -> skip, never refuse ─────
tmp="$(mk_fixture)"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'root project/repo-b/ref: files=0 ' <<<"$OUT"; then
  pass "T7 repo without .claude/ -> skipped with visible files=0 root line, exit 0"
else
  fail "T7 repo without .claude/ -> skipped with visible files=0 root line, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T8 (parity with T4b of test-one-copy-drift.sh): declared + identical →
#    EXPECTED-OVERRIDE + STALE-EXCEPTION advisory, still exit 0 ────────────
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
cp "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml" "${tmp}/repo-a/.claude/ref/leadv2-main-model.yaml"
printf 'project/repo-a/ref/leadv2-main-model.yaml\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'STALE-EXCEPTION: project/repo-a/ref/leadv2-main-model\.yaml' <<<"$OUT"; then
  pass "T8 declared identical copy -> STALE-EXCEPTION advisory, exit 0"
else
  fail "T8 declared identical copy -> STALE-EXCEPTION advisory, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T9: the dead scripts root is NAMED dead on every check ────────────────
tmp="$(mk_fixture)"
run_check "$tmp"
if grep -q 'root scripts:.*DEAD-ROOT: no readers since 2026-09-06' <<<"$OUT"; then
  pass "T9 scripts root carries the DEAD-ROOT marker every run"
else
  fail "T9 scripts root carries the DEAD-ROOT marker every run OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T10: exception line whose tenant side is gone -> UNUSED advisory only ──
tmp="$(mk_fixture)"
printf 'not yet ported\n' > "${tmp}/canon/plugins/leadv2/agents/architect.md"
printf 'agents/architect.md\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'UNUSED-EXCEPTION: agents/architect\.md' <<<"$OUT"; then
  pass "T10 exception with no tenant file -> UNUSED-EXCEPTION advisory, exit 0"
else
  fail "T10 exception with no tenant file -> UNUSED-EXCEPTION advisory, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T11 (edge): exception naming a repo absent from the yaml -> no rot, ───
#     no crash (canonical twin exists; tenant side simply unresolvable) ────
tmp="$(mk_fixture)"
printf 'model: canonical\n' > "${tmp}/canon/plugins/leadv2/ref/leadv2-main-model.yaml"
printf 'project/ghost-repo/ref/leadv2-main-model.yaml\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && ! grep -qE 'ROTTEN|REGRESSION:|DIVERGED:|BADLINK:' <<<"$OUT"; then
  pass "T11 exception for repo not in yaml -> inert, exit 0"
else
  fail "T11 exception for repo not in yaml -> inert, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

log "── ${PASS} passed, ${FAIL} failed ──"
[[ "$FAIL" -eq 0 ]]
