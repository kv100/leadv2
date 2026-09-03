#!/usr/bin/env bash
# LANE-WRITESET-REGISTRY-01: admission must be atomic, distinguish legacy
# unknown rows, and make the commit-time drift re-check observable.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_SH="${SCRIPT_DIR}/../leadv2-active-registry.sh"
PRODUCT_CLOSE_SH="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0
log()  { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

new_sandbox() {
  local root
  root="$(lv2_mktemp_dir "writeset-admission")"
  mkdir -p "${root}/docs/leadv2"
  printf '%s\n' "$root"
}

run_live_signal() {
  local root="$1" out rc active
  active="${root}/docs/leadv2/active.yaml"
  out="$(
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" \
      LEADV2_WRITESET_ENFORCE=block bash -s "$REGISTRY_SH" "$root" <<'EOF'
set -e
source "$1"
root="$2"
leadv2_active_register "LANE-A" Standard "$root" wt-A false "" "" "plugins/leadv2/scripts/leadv2-dispatch-code.sh" >/dev/null
set +e
out="$(leadv2_active_register "LANE-B" Standard "$root" wt-B false "" "" "plugins/leadv2/scripts/leadv2-dispatch-code.sh" 2>&1)"; rc=$?
set -e
printf 'rc=%s\n%s\n' "$rc" "$out"
EOF
  )" || true
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p' | head -1)"
  if [[ "$rc" == 5 ]] && grep -q 'writeset conflict: other=LANE-A' <<<"$out" \
      && ! grep -q 'task_id: LANE-B' "$active"; then
    pass "live signal: rc=5, conflict names LANE-A, LANE-B not appended"
  else
    fail "live signal: ${out}"
  fi
}

run_race() {
  local root="$1" rca rcb total
  (
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
      bash -c 'source "$1"; leadv2_active_register RACE-A Standard "$2" a false "" "" target/path >/dev/null' _ "$REGISTRY_SH" "$root"
  ) & local pa=$!
  (
    LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
      bash -c 'source "$1"; leadv2_active_register RACE-B Standard "$2" b false "" "" target/path >/dev/null' _ "$REGISTRY_SH" "$root"
  ) & local pb=$!
  set +e; wait "$pa"; rca=$?; wait "$pb"; rcb=$?; set -e
  total="$(grep -c 'task_id: RACE-' "${root}/docs/leadv2/active.yaml" 2>/dev/null || true)"
  if [[ "$total" == 1 ]] && { [[ "$rca" == 0 && "$rcb" == 5 ]] || [[ "$rca" == 5 && "$rcb" == 0 ]]; }; then
    pass "race: exactly one intersecting register wins under the registry lock"
  else
    fail "race: rc_a=${rca} rc_b=${rcb} registered=${total}"
  fi
}

run_legacy_and_drift() {
  local root="$1" warn_rc block_rc free_rc hit_rc
  cat > "${root}/docs/leadv2/active.yaml" <<'YAML'
meta: {}
sessions:
  - task_id: LEGACY
    stale: false
YAML
  set +e
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=warn \
    bash -c 'source "$1"; leadv2_active_register CANDIDATE Standard "$2" c false "" "" declared/a >/dev/null' _ "$REGISTRY_SH" "$root"; warn_rc=$?
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_register BLOCKED Standard "$2" b false "" "" declared/b >/dev/null' _ "$REGISTRY_SH" "$root"; block_rc=$?
  set -e
  cat > "${root}/docs/leadv2/active.yaml" <<'YAML'
meta: {}
sessions:
  - task_id: PEER
    stale: false
    writes: contested/b
YAML
  set +e
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_check_writes_conflict SELF free/a' _ "$REGISTRY_SH" "$root"; free_rc=$?
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=block \
    bash -c 'source "$1"; leadv2_active_check_writes_conflict SELF contested/b' _ "$REGISTRY_SH" "$root"; hit_rc=$?
  set -e
  if [[ "$warn_rc" == 0 && "$block_rc" == 6 && "$free_rc" == 0 && "$hit_rc" == 5 ]]; then
    pass "legacy and drift re-check: warn admits, block=6, free=0, contested=5"
  else
    fail "legacy and drift re-check: warn=${warn_rc} block=${block_rc} free=${free_rc} hit=${hit_rc}"
  fi
}

### ---- fix-round-1: live-wire cases (round-1 review H1/H2/H3/H4/H5) ----

# H1 regression guard: reproduces dispatch-code.sh's own two-phase pattern
# (register self BEFORE writes are known, patch writes in LATER once the
# architect prepass resolves them -- dispatch-code.sh:~5859 and :~6005) and
# proves a concurrent lane intersecting the still-unresolved incumbent is
# REFUSED (rc=5, reason=pending_resolution), not silently admitted under the
# default `warn` enforce mode. Before the fix this test fails: the "unknown"
# branch alone admits under warn regardless of how young the row is.
run_pending_window_race() {
  local root="$1" out rc
  set +e
  LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=warn \
    bash -c 'source "$1"; leadv2_active_register PENDING-A Standard "$2" a false >/dev/null' _ "$REGISTRY_SH" "$root"
  out="$(LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" CLAUDE_PROJECT_DIR="$root" LEADV2_WRITESET_ENFORCE=warn \
    bash -c 'source "$1"; leadv2_active_register PENDING-B Standard "$2" b false "" "" plugins/leadv2/scripts/leadv2-dispatch-code.sh 2>&1' _ "$REGISTRY_SH" "$root")"; rc=$?
  set -e
  if [[ "$rc" == 5 ]] && grep -q 'reason=pending_resolution' <<<"$out" && grep -q 'other=PENDING-A' <<<"$out"; then
    pass "H1: a lane mid-resolution (writes not yet persisted) refuses an intersecting concurrent register, even under warn"
  else
    fail "H1 pending window: rc=${rc} out=${out}"
  fi
}

# H2/H3 live wire: sources the EXACT _pc_git_diff_names function body out of
# the shipped leadv2-dispatch-product-close.sh (not a reimplementation) and
# runs it against a real git repo -- proves (H2) a brand-new UNTRACKED file
# outside any declared write set is visible, and (H3) a tracked
# docs/leadv2/ write is excluded so routine lane-state churn never counts as
# drift.
run_product_close_drift_wire() {
  local root="$1" fn_file names
  fn_file="$(lv2_mktemp_dir "pc-drift-fn")/fn.sh"
  sed -n '/^_pc_git_diff_names() {/,/^}/p' "$PRODUCT_CLOSE_SH" > "$fn_file"
  git -C "$root" init -q
  git -C "$root" config user.email t@t.example; git -C "$root" config user.name t
  mkdir -p "$root/docs/leadv2"
  printf 'a\n' > "$root/tracked.txt"
  git -C "$root" add tracked.txt >/dev/null
  git -C "$root" commit -qm base
  base="$(git -C "$root" rev-parse HEAD)"
  printf 'new\n' > "$root/undeclared-new-file.txt"      # H2: untracked, never staged
  printf 'x\n' >> "$root/docs/leadv2/bus.jsonl"
  git -C "$root" add docs/leadv2/bus.jsonl >/dev/null    # H3: tracked, excluded path
  names="$(bash -c 'source "$1"; _pc_git_diff_names "$2" "$3"' _ "$fn_file" "$root" "$base")"
  if grep -qx 'undeclared-new-file.txt' <<<"$names" && ! grep -q '^docs/leadv2/' <<<"$names"; then
    pass "H2/H3: _pc_git_diff_names sees an untracked new file and excludes docs/leadv2/"
  else
    fail "H2/H3 drift wire: names=[${names}]"
  fi
}

# H4 live wire: sources the EXACT narrowed landed-foreign escape block (lines
# guarded by `blocked_reason == unscopable_diff`) and proves a
# writeset_drift_conflict verdict (D6's one BLOCK) is NEVER reclassified
# landed_foreign even when a matching foreign commit exists -- while the
# escape still fires for the case it was written for (unscopable_diff).
run_product_close_landed_foreign_wire() {
  local root="$1" block_file foreign_repo hdir out1 rc1 out2 rc2
  block_file="$(lv2_mktemp_dir "pc-lf-block")/block.sh"
  sed -n '/^if \[\[ "\${blocked_reason}" == "unscopable_diff" \]\]; then$/,/^fi$/p' "$PRODUCT_CLOSE_SH" > "$block_file"
  [[ -s "$block_file" ]] || { fail "H4 wire: could not extract landed-foreign block from live source"; return; }
  foreign_repo="$(lv2_mktemp_dir "pc-lf-foreign")"
  git -C "$foreign_repo" init -q
  git -C "$foreign_repo" config user.email t@t.example; git -C "$foreign_repo" config user.name t
  printf 'x\n' > "$foreign_repo/f.txt"; git -C "$foreign_repo" add f.txt >/dev/null
  git -C "$foreign_repo" commit -qm "T-WIRE landed elsewhere" >/dev/null
  hdir="$(lv2_mktemp_dir "pc-lf-handoff")"
  set +e
  out1="$(TASK=T-WIRE HANDOFF="$hdir" LANE_TARGET_REPO="$foreign_repo" blocked_reason="writeset_drift_conflict" \
    bash -c '
      emit() { :; }; _dl_note() { :; }; _stamp_review_terminal() { :; }
      source "$1"
      echo "READY_AFTER_SNIPPET blocked_reason=${blocked_reason}"
    ' _ "$block_file")"; rc1=$?
  out2="$(TASK=T-WIRE HANDOFF="$hdir" LANE_TARGET_REPO="$foreign_repo" blocked_reason="unscopable_diff" \
    bash -c '
      emit() { :; }; _dl_note() { :; }; _stamp_review_terminal() { :; }
      source "$1"
      echo "READY_AFTER_SNIPPET blocked_reason=${blocked_reason}"
    ' _ "$block_file")"; rc2=$?
  set -e
  if grep -q 'READY_AFTER_SNIPPET blocked_reason=writeset_drift_conflict' <<<"$out1" \
      && ! grep -q 'READY_AFTER_SNIPPET' <<<"$out2" && grep -q 'reason: landed_foreign' "${hdir}/review-gate.md" 2>/dev/null; then
    pass "H4: writeset_drift_conflict is never reclassified landed_foreign; unscopable_diff escape still fires"
  else
    fail "H4 landed-foreign wire: out1=[${out1}] out2=[${out2}] rc1=${rc1} rc2=${rc2}"
  fi
}

run_product_close_reclassify_wire() {
  local root="$1" block_file hdir lane_root
  # Create a temporary script that includes just the block (pattern anchored)
  local block_file
  block_file="$(lv2_mktemp_dir "pc-reclass-block")/block.sh"
  sed -n '/^  _pc_terminal="refused"; _pc_cause="\${blocked_reason}"; _pc_rg_reason="\${blocked_reason}"$/,/^fi$/p' "$PRODUCT_CLOSE_SH" > "$block_file"
  [[ -s "$block_file" ]] || { fail "M1 wire: could not extract reclassification block from live source - pattern not found"; return; }

  hdir="$(lv2_mktemp_dir "pc-reclass-handoff")"
  mkdir -p "$hdir"
  local emitted_file="${hdir}/emitted.txt"

  # Test 1: writeset_drift_conflict should NOT trigger reclassification (condition false)
  local out1 rc1
  set +e
  out1="$(TASK=T-WIRE HANDOFF="$hdir" blocked_reason="writeset_drift_conflict" \
    bash -c '
      emit() { printf '"'"'%s\n'"'"' "$*" >> '"$emitted_file"'; }; _dl_note() { :; }; _stamp_review_terminal() { :; }
      _pc_join_capped() { echo "joined"; }
      _pc_lane_root_is_own_worktree() { return 1; }
      _pc_lane_dirty() { return 0; }
      _pc_drop_bootstrap_dirt() { cat; }
      _pc_phys() { echo "same"; }
      _pc_worker_reason() { echo ""; }
      source "$1"
    ' _ "$block_file")"; rc1=$?
  set -e

  # Test 2: some_other_reason (e.g., "foreign_commit") should trigger reclassification (condition true)
  lane_root="$(lv2_mktemp_dir "pc-reclass-lane-root")"
  local out2 rc2
  set +e
  out2="$(TASK=T-WIRE HANDOFF="$hdir" blocked_reason="foreign_commit" _lane_root="$lane_root" \
    bash -c '
      emit() { printf '"'"'%s\n'"'"' "$*" >> '"$emitted_file"'; }; _dl_note() { :; }; _stamp_review_terminal() { :; }
      _pc_join_capped() { echo "joined"; }
      _pc_lane_root_is_own_worktree() { return 1; }
      _pc_lane_dirty() { return 0; }
      _pc_lane_produced_files() { echo ""; }
      _pc_drop_bootstrap_dirt() { cat; }
      _pc_phys() { echo "same"; }
      _pc_worker_reason() { echo ""; }
      source "$1"
    ' _ "$block_file")"; rc2=$?
  set -e

  # Verify both tests exited with 5 (as exit 5 runs unconditionally)
  if [[ $rc1 -ne 5 ]]; then
    fail "M1 reclassify wire: Test 1 expected exit 5, got $rc1. out1=[${out1}]"
    return
  fi

  if [[ $rc2 -ne 5 ]]; then
    fail "M1 reclassify wire: Test 2 expected exit 5, got $rc2. out2=[${out2}]"
    return
  fi

  # Verify Test 1: writeset_drift_conflict -> condition FALSE -> cause should remain "writeset_drift_conflict"
  if grep -q "reason=writeset_drift_conflict.*cause=writeset_drift_conflict" "$emitted_file"; then
    # Verify Test 2: foreign_commit -> condition TRUE -> first inner branch recomputes the cause.
    if grep -q "reason=lane_root_not_a_worktree.*cause=lane_root_not_a_worktree" "$emitted_file"; then
      pass "M1: writeset_drift_conflict blocks reclassification; other non-partial_diff reasons still trigger it"
    else
      fail "M1 reclassify wire: Test 2 failed - reclassification did not fire for foreign_commit. Expected cause=lane_root_not_a_worktree in emitted output"
    fi
  else
    fail "M1 reclassify wire: Test 1 failed - writeset_drift_conflict incorrectly triggered reclassification. Checked emitted file for reason=writeset_drift_conflict cause=writeset_drift_conflict"
  fi
}

main() {
  local a b c d e f g
  log "=== lane write-set admission block (LANE-WRITESET-REGISTRY-01) ==="
  a="$(new_sandbox)"; b="$(new_sandbox)"; c="$(new_sandbox)"
  d="$(new_sandbox)"; e="$(new_sandbox)"; f="$(new_sandbox)"; g="$(new_sandbox)"
  trap 'rm -rf "${a:-}" "${b:-}" "${c:-}" "${d:-}" "${e:-}" "${f:-}" "${g:-}"' EXIT
  run_live_signal "$a"
  run_race "$b"
  run_legacy_and_drift "$c"
  run_pending_window_race "$d"
  run_product_close_drift_wire "$e"
  run_product_close_landed_foreign_wire "$f"
  run_product_close_reclassify_wire "$g"
  log "=== Results: PASS=${PASS} FAIL=${FAIL} ==="
  [[ "$FAIL" == 0 ]]
}

main "$@"
