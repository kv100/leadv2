#!/usr/bin/env bash
# tests/test-leadv2-state-path.sh — REGISTRY-MUST-LEAVE-GIT-01
#
# The live-lane registry (docs/leadv2/active.yaml) was git-tracked, so every
# `git worktree add` checkout got its own private copy frozen at the branch's
# commit -- fourteen divergent copies measured 2026-09-04 across worktrees.
# This suite covers the two independent repairs:
#
#   1. docs/leadv2/active.yaml must be untracked + gitignored in THIS repo,
#      so a future worktree checkout never re-materializes a real file there.
#   2. Path resolution in leadv2-active-registry.sh and
#      lib/leadv2-lane-state.sh must not depend on BASH_SOURCE[0] being set --
#      sourcing via `eval "$(cat file)"` (no file backing, e.g. a headless
#      worker wrapper) previously crashed with `set -u` callers:
#      "BASH_SOURCE[0]: unbound variable" -- resolution derailed instead of
#      degrading to a fallback root.
#
# Every assertion here has a paired mutation/negative control: revert the
# fix under test and prove the same assertion goes red. That is the actual
# proof this suite tests the fix, not a coincidence of the fixture.
#
# Portable: no GNU-only date/sed -i/timeout/flock. bash 3.2 compatible.
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-state-path.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
source "${SCRIPT_DIR}/../leadv2-temp.sh"

REGISTRY_SH="${SCRIPT_DIR}/../leadv2-active-registry.sh"
LANE_STATE_SH="${SCRIPT_DIR}/../lib/leadv2-lane-state.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── Test 1: active.yaml is untracked + gitignored in the real repo ─────────
test_1_active_yaml_untracked() {
  log "Test 1: docs/leadv2/active.yaml is NOT git-tracked (baseline)"
  local baseline_rc
  if git -C "$ROOT" ls-files --error-unmatch docs/leadv2/active.yaml >/dev/null 2>&1; then
    baseline_rc=0
  else
    baseline_rc=1
  fi
  if [[ "$baseline_rc" -ne 0 ]]; then
    pass "active.yaml untracked: baseline_rc=${baseline_rc} (git ls-files does not find it)"
  else
    fail "active.yaml is STILL git-tracked: baseline_rc=${baseline_rc}"
  fi

  # Negative control: stage it into a SCRATCH index copy (never git's real
  # index -- `git reset` restores tracking from HEAD, which would undo the
  # untracking fix this test exists to prove) and confirm ls-files sees it
  # as tracked there.
  log "Test 1 negative control: staged into a scratch index copy -> check must flip red"
  local mutated_rc scratch_index
  scratch_index="$(lv2_mktemp_file "gitindex-scratch" "idx")"
  rm -f "$scratch_index"
  GIT_INDEX_FILE="$scratch_index" git -C "$ROOT" add -f docs/leadv2/active.yaml >/dev/null 2>&1
  if GIT_INDEX_FILE="$scratch_index" git -C "$ROOT" ls-files --error-unmatch docs/leadv2/active.yaml >/dev/null 2>&1; then
    mutated_rc=0
  else
    mutated_rc=1
  fi
  lv2_rmtemp_file "$scratch_index"
  if [[ "$baseline_rc" -eq 1 && "$mutated_rc" -eq 0 ]]; then
    pass "negative control confirmed: baseline_rc=1 (untracked) -> mutated_rc=0 (tracked) after re-adding to index"
  else
    fail "negative control did NOT flip: baseline_rc=${baseline_rc} mutated_rc=${mutated_rc}"
  fi
}

# ── Test 2: .gitignore actually covers the path ─────────────────────────────
test_2_gitignore_covers_path() {
  log "Test 2: git check-ignore reports docs/leadv2/active.yaml as ignored"
  local baseline_rc=0
  git -C "$ROOT" check-ignore -q docs/leadv2/active.yaml || baseline_rc=$?
  if [[ "$baseline_rc" -eq 0 ]]; then
    pass "gitignore covers docs/leadv2/active.yaml: baseline_rc=0"
  else
    fail "gitignore does NOT cover docs/leadv2/active.yaml: baseline_rc=${baseline_rc}"
  fi

  log "Test 2 negative control: gitignore rule removed -> check-ignore must go red"
  local giline mutated_rc=0
  giline=$(grep -n '^/docs/leadv2/active\.yaml$' "$ROOT/.gitignore" | head -1 | cut -d: -f1)
  if [[ -z "$giline" ]]; then
    fail "could not locate the gitignore rule to mutate"
    return
  fi
  local tmpgi; tmpgi="$(lv2_mktemp_file "gitignore-backup" "txt")"
  cp "$ROOT/.gitignore" "$tmpgi"
  # Portable in-place delete of one line without sed -i (BSD/GNU differ).
  awk -v ln="$giline" 'NR!=ln' "$tmpgi" > "$ROOT/.gitignore"
  git -C "$ROOT" check-ignore -q docs/leadv2/active.yaml || mutated_rc=$?
  cp "$tmpgi" "$ROOT/.gitignore"
  lv2_rmtemp_file "$tmpgi"
  if [[ "$baseline_rc" -eq 0 && "$mutated_rc" -ne 0 ]]; then
    pass "negative control confirmed: baseline_rc=0 -> mutated_rc=${mutated_rc} after removing the gitignore rule"
  else
    fail "negative control did NOT flip: baseline_rc=${baseline_rc} mutated_rc=${mutated_rc}"
  fi
}

# Scratch fixture root for tests 3/4 -- NEVER $ROOT. leadv2_active_unregister
# does a real atomic write of active.yaml on every call (even a no-op removal
# still rewrites+re-renders); running it against $ROOT would mutate the real
# control-plane file this whole task exists to stop clobbering. Guarded by
# lv2_assert_scratch_repo, mirroring test-active-registry-failclosed.sh.
_scratch_repo_root=""
_mk_scratch_repo() {
  local dir; dir="$(lv2_mktemp_dir "state-path-scratch")"
  ( cd "$dir" && git init -q )
  lv2_assert_scratch_repo "$dir"
  printf '%s' "$dir"
}

# Sentinel resolver fixture for test 4: a deterministic stand-in for
# leadv2-state-path.sh planted at <scratch>/plugins/leadv2/scripts/, reachable
# ONLY through the BASH_SOURCE-less fallback branch. It prints
# <LEADV2_STATE_ROOT>/<name>, so the test asserts on the observable
# consequence of resolution -- WHICH file the chain settled on -- rather than
# on bash's stderr wording: an unguarded BASH_SOURCE[0] under eval-sourcing
# kills only the inner command-substitution subshell, so the parent prints the
# "unbound variable" error AND STILL EXITS 0. A control that greps that
# message cannot tell a fixed resolver from a derailed one that swallows the
# error; a control that compares the resolved path can (round 2, item 1).
_mk_sentinel_state_path() { # <scratch-root>
  local dir="$1/plugins/leadv2/scripts"
  mkdir -p "$dir" "$1/.state"
  cat > "${dir}/leadv2-state-path.sh" <<'EOF'
#!/usr/bin/env bash
# test fixture (REGISTRY-MUST-LEAVE-GIT-01): sentinel state-path resolver.
# Flags are ignored; prints <LEADV2_STATE_ROOT>/<last non-flag arg>.
name=""
for a in "$@"; do
  case "$a" in
    -*) ;;
    *) name="$a" ;;
  esac
done
printf '%s/%s\n' "${LEADV2_STATE_ROOT:?LEADV2_STATE_ROOT unset}" "$name"
EOF
  chmod +x "${dir}/leadv2-state-path.sh"
}

# ── Test 3: leadv2-active-registry.sh's resolver survives BASH_SOURCE-less sourcing ─
test_3_registry_survives_eval_sourcing() {
  log "Test 3: sourcing leadv2-active-registry.sh via eval (no BASH_SOURCE) must not crash under set -u"
  local scratch out baseline_rc=0
  scratch="$(_mk_scratch_repo)"
  out="$(
    LEADV2_STATE_ROOT="${scratch}/.state" LEADV2_PROJECT_ROOT="$scratch" bash -uc '
      eval "$(cat "'"$REGISTRY_SH"'")"
      leadv2_active_unregister "__test_leadv2_state_path_nonexistent__" >/dev/null 2>&1
      echo RC=$?
    ' 2>&1
  )" || baseline_rc=$?
  rm -rf "$scratch"
  if [[ "$out" == *"RC=0"* && "$out" != *"parameter not set"* && "$out" != *"unbound variable"* ]]; then
    pass "registry resolver survives eval-sourcing: baseline_rc=0, output=[${out}]"
  else
    fail "registry resolver crashed under eval-sourcing: baseline_rc=${baseline_rc} output=[${out}]"
  fi

  log "Test 3 negative control: reintroduce bare BASH_SOURCE[0] -> must crash the same way"
  local tmp_registry mutated_out mutated_rc=0
  tmp_registry="$(lv2_mktemp_file "registry-mutated" "sh")"
  awk '
    /if \[\[ -n "\$\{BASH_SOURCE\[0\]:-\}" \]\]; then/ { skip=1 }
    skip==0 { print }
    /bundled="\$\{LEADV2_PROJECT_ROOT\}\/plugins\/leadv2\/scripts\/leadv2-state-path\.sh"/ { skip=0; next }
  ' "$REGISTRY_SH" > "$tmp_registry"
  # Splice back a single unguarded assignment in place of the guarded block.
  awk -v repl='  bundled="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-state-path.sh"' '
    /if \[\[ -n "\$\{BASH_SOURCE\[0\]:-\}" \]\]; then/ { print repl; skip=1; next }
    skip==1 { if (/bundled="\$\{LEADV2_PROJECT_ROOT\}\/plugins\/leadv2\/scripts\/leadv2-state-path\.sh"/) { skip=0 }; next }
    { print }
  ' "$REGISTRY_SH" > "$tmp_registry"
  scratch="$(_mk_scratch_repo)"
  mutated_out="$(
    LEADV2_STATE_ROOT="${scratch}/.state" LEADV2_PROJECT_ROOT="$scratch" bash -uc '
      eval "$(cat "'"$tmp_registry"'")"
      leadv2_active_unregister "__test_leadv2_state_path_nonexistent__" >/dev/null 2>&1
      echo RC=$?
    ' 2>&1
  )" || mutated_rc=$?
  rm -rf "$scratch"
  lv2_rmtemp_file "$tmp_registry"
  if [[ "$mutated_out" == *"unbound variable"* || "$mutated_out" == *"parameter not set"* || "$mutated_rc" -ne 0 ]]; then
    pass "negative control confirmed: mutated (unguarded BASH_SOURCE[0]) crashes: output=[${mutated_out}] rc=${mutated_rc}"
  else
    fail "negative control did NOT reproduce the crash: output=[${mutated_out}] rc=${mutated_rc}"
  fi
}

# ── Test 4: lib/leadv2-lane-state.sh's resolver survives BASH_SOURCE-less sourcing ─
test_4_lane_state_survives_eval_sourcing() {
  log "Test 4: eval-sourced lane-state must resolve the sentinel state-path helper, not merely exit 0"
  local scratch expected out baseline_rc=0
  scratch="$(_mk_scratch_repo)"
  _mk_sentinel_state_path "$scratch"
  expected="${scratch}/.state/active.yaml"
  out="$(
    LEADV2_STATE_ROOT="${scratch}/.state" LEADV2_PROJECT_ROOT="$scratch" \
    LEADV2_EXPECTED_STATE_PATH="$expected" bash -uc '
      eval "$(cat "'"$LANE_STATE_SH"'")"
      got="$(_lv2_lane_state_path)"
      printf "RESOLVED=%s\n" "$got"
      # Assert the observable consequence -- WHICH file resolution settled on
      # -- because a derailed resolver can print an unbound-variable error to
      # stderr and still exit 0 (the subshell death is swallowed by the
      # parent). Exit 7 = wrong file; exit 8 = API call failed.
      [[ "$got" == "$LEADV2_EXPECTED_STATE_PATH" ]] || exit 7
      lane_count_live "__test_nonexistent_lead__" >/dev/null 2>&1 || exit 8
      exit 0
    ' 2>&1
  )" || baseline_rc=$?
  rm -rf "$scratch"
  if [[ "$baseline_rc" -eq 0 && "$out" == *"RESOLVED=${expected}"* \
        && "$out" != *"parameter not set"* && "$out" != *"unbound variable"* ]]; then
    pass "lane-state resolver survives eval-sourcing AND resolves the sentinel: baseline_rc=0 output=[${out}]"
  else
    fail "lane-state resolver derailed under eval-sourcing: baseline_rc=${baseline_rc} output=[${out}]"
  fi

  log "Test 4 negative control: reintroduce bare BASH_SOURCE[0] -> resolution check must fail with NONZERO rc"
  local tmp_lane mutated_out mutated_rc=0
  tmp_lane="$(lv2_mktemp_file "lane-state-mutated" "sh")"
  awk -v repl='_lv2_lane_state_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' '
    /^if \[\[ -n "\$\{BASH_SOURCE\[0\]:-\}" \]\]; then$/ { print repl; skip=1; next }
    skip==1 { if (/^fi$/) { skip=0 }; next }
    { print }
  ' "$LANE_STATE_SH" > "$tmp_lane"
  scratch="$(_mk_scratch_repo)"
  _mk_sentinel_state_path "$scratch"
  mutated_out="$(
    LEADV2_STATE_ROOT="${scratch}/.state" LEADV2_PROJECT_ROOT="$scratch" \
    LEADV2_EXPECTED_STATE_PATH="${scratch}/.state/active.yaml" bash -uc '
      eval "$(cat "'"$tmp_lane"'")"
      got="$(_lv2_lane_state_path)"
      printf "RESOLVED=%s\n" "$got"
      [[ "$got" == "$LEADV2_EXPECTED_STATE_PATH" ]] || exit 7
      lane_count_live "__test_nonexistent_lead__" >/dev/null 2>&1 || exit 8
      exit 0
    ' 2>&1
  )" || mutated_rc=$?
  rm -rf "$scratch"
  lv2_rmtemp_file "$tmp_lane"
  if [[ "$mutated_rc" -ne 0 ]]; then
    pass "negative control confirmed: mutated resolver resolved a WRONG path and the check caught it by rc: mutated_rc=${mutated_rc} output=[${mutated_out}]"
  else
    fail "negative control did NOT flip: mutated_rc=0 -- derailed resolver still passed (rc-0 from success indistinguishable from rc-0 from failure) output=[${mutated_out}]"
  fi
}

# ── Test 5: bash -n syntax check on both changed files ──────────────────────
test_5_syntax() {
  log "Test 5: bash -n on changed files"
  if bash -n "$REGISTRY_SH" && bash -n "$LANE_STATE_SH"; then
    pass "bash -n clean on both changed files"
  else
    fail "bash -n failed on a changed file"
  fi
}

test_1_active_yaml_untracked
test_2_gitignore_covers_path
test_3_registry_survives_eval_sourcing
test_4_lane_state_survives_eval_sourcing
test_5_syntax

log "----------------------------------------"
log "RESULTS: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
