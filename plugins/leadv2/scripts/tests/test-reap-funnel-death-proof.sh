#!/usr/bin/env bash
# tests/test-reap-funnel-death-proof.sh — D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF
#
# Drives the REAL `leadv2-dispatch-ledger.sh reap` (real subprocess, real git fixture
# repos) exactly as shipped. Only leadv2-lane-liveness.sh is faked, one level lower, via
# LEADV2_REAP_LIVENESS_BIN — reap must never compute liveness itself (D2 owns that).
#
# Cases (brief §7 + the 2026-09-03 self-incident addendum):
#   C1  SIGKILL, real prior commit + uncommitted diff  -> dead_with_unlanded_work, rescued
#   C1b SIGKILL, ONLY the anchor commit + uncommitted diff (the addendum's poorer, real
#       incident shape: zero non-anchor commits) -> still dead_with_unlanded_work, rescued
#   C2  clean tree, no artifacts                       -> no_work, zero rescue commits
#   C3  cap slot freed by reap; original sig8 stays blocked (write-once) but a FRESH
#       sig8 (the resume's own mission text) is never refused by the terminal ledger
#   C4  liveness=alive                                 -> reap writes nothing
#   C5  `--all` reservation-ledger anti-join            -> barrier=spawned_then_died
#   C6  no lane_writes CSV info at all                  -> still rescued (unscoped probe)
#   C7  rescue commit is unmistakable (author/trailer/marker) — asserted against C1's commit
#   C8  _dl_derive_lane_state called DIRECTLY (D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01):
#       C8a dirty tree + no path-scoped commit + dead -> dead_with_unlanded_work,
#       never landed; C8b real path-scoped commit -> landed with that exact sha
#   C9  git itself FAILS during derive (PATH shim, DERIVE-COERCES-GIT-FAILURE-TO-NO-
#       COMMIT-01): C9a commit-lookup failure, C9b dirty-probe failure -> unknown,
#       never dead/no_work/landed (a failed measurement is not "no commit"/"clean tree")
#
# Fixture discipline (fix round 2): every fixture construction step verifies its own
# result and aborts the run via setup_error (exit 2, wording distinct from an assertion
# FAIL). A fixture that silently missed its target must never surface as an assertion
# red (looks like a product bug) or, worse, hand an unwarranted green.
#
# Run: bash plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
# Negative control (proof pasted in the deliverable, not part of normal CI runs):
#   LEADV2_TEST_REAP_LEDGER_BIN=<mutated-copy> bash plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LEDGER_BIN="${LEADV2_TEST_REAP_LEDGER_BIN:-${SCRIPTS_DIR}/leadv2-dispatch-ledger.sh}"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }
setup_error() {  # <case> <reason>: the FIXTURE missed its target -- not an assertion
  # verdict about the product. Loud abort, distinct wording, exit 2 (never 1), so a
  # broken fixture can neither masquerade as a product red nor enable a fake green.
  printf '[TEST] SETUP-ERROR: %s: %s\n' "$1" "$2"
  printf '\n[TEST] aborted: %d passed, %d failed, setup error\n' "${PASS}" "${FAIL}"
  exit 2
}

RUN_ID="reap-funnel-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"
trap 'rm -rf "${TMPDIR_ROOT}"' EXIT

# ── fake liveness binary — verdict controlled per-call via LEADV2_TEST_LIVENESS_VERDICT ──
LIVENESS_BIN="${TMPDIR_ROOT}/fake-liveness.sh"
cat > "${LIVENESS_BIN}" <<'EOF'
#!/usr/bin/env bash
# Fake leadv2-lane-liveness.sh for the reap-funnel suite. Real CLI shape
# (--project-root R --lane <id>), fake answer only.
printf '%s\n' "${LEADV2_TEST_LIVENESS_VERDICT:-dead:test}"
EOF
chmod +x "${LIVENESS_BIN}"
[[ -x "${LIVENESS_BIN}" ]] || setup_error "harness" "fake liveness bin not executable"

# ── fixture helpers ──────────────────────────────────────────────────────────────────
_new_repo() {  # -> prints repo root (a fresh, isolated main checkout); rc!=0 on any
  # construction miss (whole seed chain guarded -- a discarded-status subshell here
  # once let 8 of 9 cases silently re-use one shared repo, every seed commit after
  # the first failing unreported). Index comes from the DIRECTORY, never a counter:
  # callers run this inside $( ), where an incremented counter dies in the subshell
  # and hands every case the same path.
  local root="" n=0
  while [[ -d "${TMPDIR_ROOT}/repo-$((n + 1))" ]]; do n=$((n + 1)); done
  root="${TMPDIR_ROOT}/repo-$((n + 1))"
  # active.yaml resolves through leadv2-state-path.sh to a control-plane root OUTSIDE
  # the repo (LEAD-CONTROL-PLANE-01) -- LEADV2_STATE_ROOT overrides that resolution to a
  # tmpdir-scoped path so the fixture never touches the real ~/.claude/leadv2-state.
  if ! ( mkdir -p "${root}" && cd "${root}" \
    && git init -q -b main >/dev/null 2>&1 \
    && git config user.email t@example.com && git config user.name t \
    && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed >/dev/null \
    && mkdir -p "${root}/.state-root" \
    && printf 'sessions: []\n' > "${root}/.state-root/active.yaml" \
    && : > "${root}/.state-root/active.yaml.lock" ); then
    # stderr, not stdout: callers run this in $( ) and stdout is the root-path channel.
    printf '[TEST] SETUP-ERROR: repo-%s: seed repo/state-root construction failed\n' "${_seq}" >&2
    return 1
  fi
  printf '%s' "${root}"
}

_make_lane_worktree() {  # <root> <lane_id> -- anchor-only worktree on branch worktree-<lane_id>
  local root="$1" lane="$2"
  git -C "${root}" worktree add -q "${root}/.claude/worktrees/${lane}" -b "worktree-${lane}" >/dev/null 2>&1
}

_register_session() {  # <root> <task_id> [<attempt>]
  python3 - "${1}/.state-root/active.yaml" "$2" "${3:-${2}-epoch-99999}" <<'PYEOF'
import sys, yaml
path, tid, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    d = yaml.safe_load(f) or {}
# Realistic row shape: a live dispatch stamps a real, non-empty attempt token
# (_dl_attempt_token: <sig8>-<epoch>-<pid>) via the registry's set_attempt op --
# an empty-attempt fixture would trivially match _dl_reap_active_attempt's
# lookup and hide a token-mismatch bug (see _dl_reap_active_attempt's doc).
d.setdefault("sessions", []).append({"task_id": tid, "attempt": attempt})
with open(path, "w") as f:
    yaml.safe_dump(d, f, default_flow_style=False, sort_keys=False)
PYEOF
}

_session_present() {  # <root> <task_id> -> rc0 if still registered
  python3 - "${1}/.state-root/active.yaml" "$2" <<'PYEOF'
import sys, yaml
path, tid = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = yaml.safe_load(f) or {}
sys.exit(0 if any(s.get("task_id") == tid for s in (d.get("sessions") or [])) else 1)
PYEOF
}

_reap() {  # <root> <term_ledger_file> [reap-args...]
  local root="$1" term="$2"; shift 2
  ( PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
    LEADV2_STATE_ROOT="${root}/.state-root" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${term}" \
    LEADV2_REAP_LIVENESS_BIN="${LIVENESS_BIN}" \
    LEADV2_JOURNAL_BIN=/bin/true \
    bash "${LEDGER_BIN}" reap "$@" )
}

_term_exists() {  # <root> <term_ledger_file> <sig8> -> rc0 if a TRUE terminal is recorded
  ( PROJECT_ROOT="$1" LEADV2_PROJECT_ROOT="$1" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$2" \
    bash "${LEDGER_BIN}" exists "$3" 2>/dev/null )
}

# ============================================================================ C1
run_c1() {
  local root term out lane sig8 wt
  root="$(_new_repo)" || setup_error "C1" "repo fixture construction failed"
  lane="dispatch-c1c1c1c1"; sig8="c1c1c1c1"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C1" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && printf 'a\n' > work.txt && git add work.txt && git commit -qm "lane work" >/dev/null \
    && printf 'b\n' >> work.txt ) || setup_error "C1" "prior-commit fixture construction failed"
  # real prior commit + a real uncommitted diff on top -- verify BOTH halves exist:
  [[ -n "$(git -C "${wt}" log -n1 --pretty=%H -- work.txt 2>/dev/null)" \
    && -n "$(git -C "${wt}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C1" "work.txt commit and/or uncommitted diff missing after construction"

  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _reap "${root}" "${term}" --lane "${lane}")"
  if [[ "${out}" == *"terminal=dead_with_unlanded_work"* && "${out}" == *"rescued=1"* ]]; then
    pass "C1: SIGKILL+diff (with prior commit) -> dead_with_unlanded_work, rescued=1"
  else
    fail "C1: expected dead_with_unlanded_work/rescued=1, got: ${out}"
  fi
  grep -q '"task_sig":"'"${sig8}"'".*"terminal":"dead_with_unlanded_work"' "${term}" \
    && pass "C1: terminal ledger row recorded" \
    || fail "C1: no dead_with_unlanded_work row in ${term}"
  grep -q '"task_sig":"'"${sig8}"'".*"terminal":"no_work"' "${term}" \
    && fail "C1: a no_work row also exists for this sig (must not)" \
    || pass "C1: no no_work row for this sig"
  if [[ -z "$(git -C "${wt}" diff --diff-filter=D --name-only main...HEAD 2>/dev/null)" ]]; then
    pass "C1: rescue commit carries no deletions (R7 n/a here)"
  else
    fail "C1: rescue commit unexpectedly deletes files"
  fi
  C1_WT="${wt}"
}

# ============================================================================ C1b (addendum)
run_c1b() {
  local root term out lane sig8 wt
  root="$(_new_repo)" || setup_error "C1b" "repo fixture construction failed"
  lane="dispatch-c1b1c1b1"; sig8="c1b1c1b1"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C1b" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  # The real 2026-09-03 incident shape: ZERO non-anchor commits, only a dirty tree.
  ( cd "${wt}" && printf 'only uncommitted work\n' > work.txt ) \
    || setup_error "C1b" "dirty-tree write failed"
  [[ -f "${wt}/work.txt" && -n "$(git -C "${wt}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C1b" "work.txt not present as an uncommitted change"

  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _reap "${root}" "${term}" --lane "${lane}")"
  if [[ "${out}" == *"terminal=dead_with_unlanded_work"* && "${out}" == *"rescued=1"* ]]; then
    pass "C1b: zero non-anchor commits + dirty tree -> dead_with_unlanded_work, rescued=1"
  else
    fail "C1b: expected dead_with_unlanded_work/rescued=1, got: ${out}"
  fi
  # This lane had exactly ONE commit (the rescue) beyond the anchor -- prove the rescue
  # is reachable with commit-count==0-before-rescue, the exact case a commit-having
  # fixture (C1) does not exercise.
  local n_commits_ahead
  n_commits_ahead="$(git -C "${wt}" rev-list --count main..HEAD 2>/dev/null || echo -1)"
  [[ "${n_commits_ahead}" == "1" ]] \
    && pass "C1b: exactly one (rescue) commit ahead of main -- worker itself made zero" \
    || fail "C1b: expected 1 commit ahead of main, got ${n_commits_ahead}"
}

# ============================================================================ C2
run_c2() {
  local root term out lane sig8
  root="$(_new_repo)" || setup_error "C2" "repo fixture construction failed"
  lane="dispatch-c2c2c2c2"; sig8="c2c2c2c2"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C2" "worktree add failed for ${lane}"

  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _reap "${root}" "${term}" --lane "${lane}")"
  if [[ "${out}" == *"terminal=no_work"* && "${out}" == *"rescued=0"* ]]; then
    pass "C2: clean dead tree -> no_work, rescued=0"
  else
    fail "C2: expected no_work/rescued=0, got: ${out}"
  fi
  local rescue_commits
  rescue_commits="$(git -C "${root}/.claude/worktrees/${lane}" log --grep='Leadv2-Rescue: true' --oneline 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${rescue_commits}" == "0" ]] \
    && pass "C2: zero rescue commits on a clean lane" \
    || fail "C2: expected 0 rescue commits, found ${rescue_commits}"
}

# ============================================================================ C3
run_c3() {
  local root term out lane sig8 other_lane
  root="$(_new_repo)" || setup_error "C3" "repo fixture construction failed"
  lane="dispatch-c3c3c3c3"; sig8="c3c3c3c3"; other_lane="dispatch-99999999"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C3" "worktree add failed for ${lane}"
  ( cd "${root}/.claude/worktrees/${lane}" && printf 'dirty\n' > work.txt ) \
    || setup_error "C3" "dirty-tree write failed"
  [[ -n "$(git -C "${root}/.claude/worktrees/${lane}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C3" "lane worktree not dirty after construction"
  _register_session "${root}" "${lane}" || setup_error "C3" "active.yaml register failed for ${lane}"
  _register_session "${root}" "${other_lane}" || setup_error "C3" "active.yaml register failed for ${other_lane}"

  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _reap "${root}" "${term}" --lane "${lane}")"
  [[ "${out}" == *"terminal=dead_with_unlanded_work"* ]] || fail "C3: setup reap failed: ${out}"

  if _session_present "${root}" "${lane}"; then
    fail "C3: active.yaml row for reaped lane still present -- cap slot NOT freed"
  else
    pass "C3: cap slot freed -- reaped lane's active.yaml row is gone"
  fi
  if _session_present "${root}" "${other_lane}"; then
    pass "C3: unrelated lane's active.yaml row untouched"
  else
    fail "C3: unrelated lane's row was wrongly removed"
  fi

  # R1: the ORIGINAL sig8 is write-once-final (correct -- a plain re-dispatch of the SAME
  # mission text must never overwrite a recorded terminal).
  if _term_exists "${root}" "${term}" "${sig8}" >/dev/null 2>&1; then
    pass "R1/C3: original sig8 stays write-once-blocked (by design)"
  else
    fail "R1/C3: original sig8 unexpectedly not recorded as terminal"
  fi
  # R1/C3: a RESUME must use a fresh sig (brief §4: barrier duplicate_task_signature,
  # resumable=no unless the resume dispatch carries --task-id/--resume-lane on a fresh
  # sig). Prove the terminal ledger's write-once gate keys per-sig8, not per-lane: a
  # different sig8 (what a resume's edited mission text hashes to) is never blocked by
  # this lane's reap.
  local fresh_sig8="deadbeef"
  if _term_exists "${root}" "${term}" "${fresh_sig8}" >/dev/null 2>&1; then
    fail "R1/C3: a fresh, unrelated sig8 is wrongly reported as already-terminal"
  else
    pass "R1/C3: a fresh sig8 (resume's own mission text) is never refused by the terminal ledger"
  fi
}

# ============================================================================ C4
run_c4() {
  local root term out lane sig8
  root="$(_new_repo)" || setup_error "C4" "repo fixture construction failed"
  lane="dispatch-c4c4c4c4"; sig8="c4c4c4c4"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C4" "worktree add failed for ${lane}"
  ( cd "${root}/.claude/worktrees/${lane}" && printf 'still working\n' > work.txt ) \
    || setup_error "C4" "dirty-tree write failed"
  [[ -n "$(git -C "${root}/.claude/worktrees/${lane}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C4" "lane worktree not dirty after construction"

  out="$(LEADV2_TEST_LIVENESS_VERDICT=alive _reap "${root}" "${term}" --lane "${lane}")"
  [[ -z "${out}" ]] \
    && pass "C4: liveness=alive -- reap prints nothing" \
    || fail "C4: expected empty stdout for an alive lane, got: ${out}"
  if [[ -f "${term}" ]] && grep -q "\"task_sig\":\"${sig8}\"" "${term}"; then
    fail "C4: a terminal row was written for a lane liveness reports alive"
  else
    pass "C4: no terminal row written for an alive lane"
  fi
}

# ============================================================================ C5
run_c5() {
  local root term out lane sig8 res_file
  root="$(_new_repo)" || setup_error "C5" "repo fixture construction failed"
  lane="dispatch-c5c5c5c5"; sig8="c5c5c5c5"
  term="${root}/term-ledger.jsonl"
  res_file="${root}/reservation-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C5" "worktree add failed for ${lane}"
  ( cd "${root}/.claude/worktrees/${lane}" && printf 'died after spawn\n' > work.txt ) \
    || setup_error "C5" "dirty-tree write failed"
  [[ -n "$(git -C "${root}/.claude/worktrees/${lane}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C5" "lane worktree not dirty after construction"
  printf '{"task_sig":"%s","state":"confirmed","lane_label":"%s","handle":"PID=999999"}\n' \
    "${sig8}" "${lane}" > "${res_file}"
  [[ -s "${res_file}" ]] || setup_error "C5" "reservation-ledger row not written"

  out="$(
    LEADV2_TEST_LIVENESS_VERDICT=dead:test \
    LEADV2_DISPATCH_RESERVATION_LEDGER_FILE="${res_file}" \
    _reap "${root}" "${term}" --all
  )"
  if [[ "${out}" == *"barrier=spawned_then_died"* && "${out}" == *"terminal=dead_with_unlanded_work"* ]]; then
    pass "C5: --all reservation anti-join -> barrier=spawned_then_died, reported dead"
  else
    fail "C5: expected barrier=spawned_then_died/dead_with_unlanded_work, got: ${out}"
  fi
}

# ============================================================================ C6
run_c6() {
  local root term out lane sig8 wt
  root="$(_new_repo)" || setup_error "C6" "repo fixture construction failed"
  lane="dispatch-c6c6c6c6"; sig8="c6c6c6c6"
  term="${root}/term-ledger.jsonl"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C6" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && mkdir -p src/nested && printf 'x\n' > src/nested/untracked_by_any_write_set.txt ) \
    || setup_error "C6" "untracked-file construction failed"
  [[ -f "${wt}/src/nested/untracked_by_any_write_set.txt" ]] \
    || setup_error "C6" "untracked fixture file missing after construction"

  # Deliberately NO lane_writes / LEADV2_DISPATCH_LANE_WRITES of any kind -- the funnel's
  # own dirty probe (git status --porcelain -uall, unscoped) must not depend on it.
  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test LEADV2_DISPATCH_LANE_WRITES="" \
    _reap "${root}" "${term}" --lane "${lane}")"
  if [[ "${out}" == *"terminal=dead_with_unlanded_work"* && "${out}" == *"rescued=1"* ]]; then
    pass "C6: empty/absent lane_writes CSV -- still rescued (unscoped probe, LANE-WRITES-IS-EMPTY-98-PERCENT-01 not reproduced)"
  else
    fail "C6: expected rescue despite no lane_writes info, got: ${out}"
  fi
}

# ============================================================================ C7 (against C1's rescue commit)
run_c7() {
  local wt="$1"
  [[ -n "${wt}" && -d "${wt}" ]] || { fail "C7: no worktree handed from C1"; return; }
  local author; author="$(git -C "${wt}" log -1 --pretty='%ae')"
  [[ "${author}" == "rescue@leadv2.invalid" ]] \
    && pass "C7: rescue commit author is rescue@leadv2.invalid" \
    || fail "C7: unexpected author '${author}'"
  git -C "${wt}" log -1 --pretty='%B' | grep -q '^Leadv2-Rescue: true$' \
    && pass "C7: Leadv2-Rescue: true trailer present" \
    || fail "C7: Leadv2-Rescue trailer missing"
  git -C "${wt}" show --stat -1 2>/dev/null | grep -q 'RESCUE-UNREVIEWED' \
    && pass "C7: RESCUE-UNREVIEWED marker is tracked in the rescue commit" \
    || fail "C7: RESCUE-UNREVIEWED marker not found in commit"
}

# ============================================================================ C8 (D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01)
# Direct unit coverage for _dl_derive_lane_state. C1..C7 drive the reap funnel
# end-to-end, but the derive function itself had ZERO assertions: the one-line
# regression that ORs a dirty tree back into the `landed` branch (the 2026-08-04
# incident shape -- 573 uncommitted lines stamped `landed`, worktree one sweep
# from deletion) kept this whole suite green. The ledger script is SOURCED (its
# main dispatch is guarded behind BASH_SOURCE==$0) so the REAL shipped function
# runs, with liveness faked one level lower exactly like the reap runs above.
_derive() {  # <repo> <spawn_epoch> <writes_csv> <deliverable> <lane_id> -> _dl_derive_lane_state's stdout
  local repo="$1" epoch="$2" csv="$3" deliverable="$4" lane="$5"
  PROJECT_ROOT="${repo}" LEADV2_PROJECT_ROOT="${repo}" \
    LEADV2_DISPATCH_LANE_LIVENESS_BIN="${LIVENESS_BIN}" \
    bash -c '
      source "${1}"
      _dl_derive_lane_state "${2}" "${3}" "${4}" "${5}" "${6}"
    ' _derive_sub "${LEDGER_BIN}" "${repo}" "${epoch}" "${csv}" "${deliverable}" "${lane}"
}

run_c8() {
  local root wt out lane sha f1
  # -- C8a: THE assertion that must kill the mutant. No path-scoped commit, DIRTY
  #    tree in the lane's write-set, liveness dead => dead_with_unlanded_work,
  #    NEVER landed. spawn_epoch=0 = lane spawned before any of its work.
  root="$(_new_repo)" || setup_error "C8a" "repo fixture construction failed"
  lane="dispatch-c8a8a8a8"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C8a" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && printf 'uncommitted incident work\n' > work.txt ) \
    || setup_error "C8a" "dirty-tree write failed"
  # A silently-failed printf would make C8a pass for the wrong reason -- prove the
  # dirty tree actually exists before deriving.
  [[ -f "${wt}/work.txt" && -n "$(git -C "${wt}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C8a" "dirty-tree fixture not constructed (work.txt uncommitted)"
  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _derive "${wt}" "0" "work.txt" "" "${lane}")"
  f1="${out%%$'\x1f'*}"
  if [[ "${f1}" == "dead_with_unlanded_work" && "${out}" != "landed"$'\x1f'* ]]; then
    pass "C8a: derive(dirty tree, no path-scoped commit, dead) -> dead_with_unlanded_work, never landed"
  else
    fail "C8a: expected dead_with_unlanded_work (never landed), got: ${out}"
  fi
  # -- C8b: the mirror. A real path-scoped commit must still derive `landed` with
  #    that exact sha -- without this, C8a would also pass against a function
  #    that NEVER returns landed at all (formally green, operationally dead).
  root="$(_new_repo)" || setup_error "C8b" "repo fixture construction failed"
  lane="dispatch-c8b8b8b8"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C8b" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && printf 'a\n' > work.txt && git add work.txt && git commit -qm "lane work" >/dev/null ) \
    || setup_error "C8b" "path-scoped commit construction failed"
  # Expected sha from the SAME path-scoped lookup the function under test performs --
  # never bare `rev-parse HEAD`, which silently hands back the SEED commit when the
  # construction above failed (the 1-in-4 false red this guard exists for).
  sha="$(git -C "${wt}" log -n1 --pretty=%H -- work.txt 2>/dev/null)"
  [[ -n "${sha}" ]] || setup_error "C8b" "no path-scoped commit for work.txt after construction"
  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test _derive "${wt}" "0" "work.txt" "" "${lane}")"
  if [[ "${out}" == "landed"$'\x1f'"${sha}"$'\x1f'* ]]; then
    pass "C8b: derive(real path-scoped commit) -> landed with that exact sha"
  else
    fail "C8b: expected landed with sha ${sha}, got: ${out}"
  fi
}

# ============================================================================ C9 (DERIVE-COERCES-GIT-FAILURE-TO-NO-COMMIT-01)
# A git that FAILS during derivation is not evidence of anything. Before the fix,
# both probes in _dl_derive_lane_state ended in `2>/dev/null || true`, so a transient
# git failure (fork failure under load, a held index.lock) read as "no commit" AND
# "clean tree" -- liveness then supplied a TERMINAL verdict (dead/no_work) derived
# from a measurement that never happened (live: C8b red 2/13 runs with a
# fixture-proven path-scoped commit derived as dead:none:unknown). git is made to
# fail via a PATH shim (no privileges, no timing); the verdict must come back the
# unknown shape -- never dead, dead_with_unlanded_work, no_work, or landed.
GIT_SHIM_DIR="${TMPDIR_ROOT}/git-shim"
mkdir -p "${GIT_SHIM_DIR}"
cat > "${GIT_SHIM_DIR}/git" <<'SHIMEOF'
#!/usr/bin/env bash
# Fails ONLY the subcommand named by SHIM_FAIL_ON (exit 128 + stderr, like a real
# transient git failure); delegates every other invocation to the real git.
for a in "$@"; do
  [[ "${a}" == "${SHIM_FAIL_ON:-}" ]] || continue
  printf 'shim: simulated git %s failure: fatal: unable to fork (Resource temporarily unavailable)\n' "${SHIM_FAIL_ON}" >&2
  exit 128
done
exec "${SHIM_REAL_GIT:?SHIM_REAL_GIT not supplied}" "$@"
SHIMEOF
chmod +x "${GIT_SHIM_DIR}/git"
REAL_GIT_BIN="$(command -v git)"
[[ -n "${REAL_GIT_BIN}" && "${REAL_GIT_BIN}" != "${GIT_SHIM_DIR}/git" ]] \
  || setup_error "C9" "could not resolve a real git binary to delegate to"

run_c9() {
  local root wt out lane f1
  # -- C9a: the COMMIT LOOKUP fails. Fixture has a real path-scoped commit (so a
  #    mutant that swallows the failure has everything it needs to say dead:none).
  root="$(_new_repo)" || setup_error "C9a" "repo fixture construction failed"
  lane="dispatch-c9a9a9a9"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C9a" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && printf 'a\n' > work.txt && git add work.txt && git commit -qm "lane work" >/dev/null ) \
    || setup_error "C9a" "path-scoped commit construction failed"
  [[ -n "$(git -C "${wt}" log -n1 --pretty=%H -- work.txt 2>/dev/null)" ]] \
    || setup_error "C9a" "no path-scoped commit for work.txt after construction"
  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test SHIM_FAIL_ON=log SHIM_REAL_GIT="${REAL_GIT_BIN}" \
    PATH="${GIT_SHIM_DIR}:${PATH}" _derive "${wt}" "0" "work.txt" "" "${lane}")"
  f1="${out%%$'\x1f'*}"
  if [[ "${f1}" == "unknown" ]]; then
    pass "C9a: derive(git log fails) -> unknown, never a terminal verdict from a failed measurement"
  else
    fail "C9a: expected unknown when the commit lookup fails, got: ${out}"
  fi
  # -- C9b: the DIRTY PROBE fails. Fixture is the C1b incident shape (dirty tree,
  #    no commit) -- exactly what a swallowed status failure would mis-read as a
  #    clean tree and stamp no_work, discarding the worker's bytes.
  root="$(_new_repo)" || setup_error "C9b" "repo fixture construction failed"
  lane="dispatch-c9b9b9b9"
  _make_lane_worktree "${root}" "${lane}" || setup_error "C9b" "worktree add failed for ${lane}"
  wt="${root}/.claude/worktrees/${lane}"
  ( cd "${wt}" && printf 'uncommitted rescue-worthy work\n' > work.txt ) \
    || setup_error "C9b" "dirty-tree write failed"
  [[ -n "$(git -C "${wt}" status --porcelain 2>/dev/null)" ]] \
    || setup_error "C9b" "dirty-tree fixture not constructed (work.txt uncommitted)"
  out="$(LEADV2_TEST_LIVENESS_VERDICT=dead:test SHIM_FAIL_ON=status SHIM_REAL_GIT="${REAL_GIT_BIN}" \
    PATH="${GIT_SHIM_DIR}:${PATH}" _derive "${wt}" "0" "work.txt" "" "${lane}")"
  f1="${out%%$'\x1f'*}"
  if [[ "${f1}" == "unknown" ]]; then
    pass "C9b: derive(git status fails) -> unknown, a failed dirty probe must not read as a clean tree"
  else
    fail "C9b: expected unknown when the dirty probe fails, got: ${out}"
  fi
}

C1_WT=""
run_c1
run_c1b
run_c2
run_c3
run_c4
run_c5
run_c6
run_c7 "${C1_WT}"
run_c8
run_c9

printf '\n[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf '[TEST] failures:\n'
  for e in "${ERRORS[@]}"; do printf '  - %s\n' "${e}"; done
  exit 1
fi
exit 0
