#!/usr/bin/env bash
# test-leadv2-orphan-checkpoint.sh — D4-NO-PATH-LOSES-WORK-01
#
# Exercises the EXTERNAL orphan-checkpoint sweeper (leadv2-orphan-checkpoint.sh)
# and its liveness authority (lib/leadv2-lane-worker-alive.sh). Only `lsof` is
# stubbed (one level lower, via PATH injection) — the checkpoint function and
# the liveness functions under claim run for REAL against real scratch git
# worktrees.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-lane-worker-alive.sh"
CKPT="${SCRIPT_DIR}/../leadv2-orphan-checkpoint.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/orphan-ckpt-test.XXXXXX")"
cleanup() { [[ "${KEEP_TMP:-0}" == "1" ]] || rm -rf "${TMP}"; }
trap cleanup EXIT

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

# ---- 0. syntax under both interpreters (D5) --------------------------------
if bash -n "${LIB}" && bash -n "${CKPT}"; then pass "bash -n syntax"; else fail "bash -n syntax"; fi
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "${LIB}" && zsh -n "${CKPT}"; then pass "zsh -n syntax"; else fail "zsh -n syntax"; fi
else
  pass "zsh -n syntax (zsh not installed on this host -- skipped, not a hidden fail)"
fi

# =============================================================================
# Section A: lib/leadv2-lane-worker-alive.sh unit tests (direct source, no
# subprocess) -- the four named false-answer cases plus D4/D5.
# =============================================================================
BIN_DIR="${TMP}/bin"
mkdir -p "${BIN_DIR}"

set_fake_lsof() {  # <script body, uses $BIN_DIR/lsof>
  cat > "${BIN_DIR}/lsof" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "${BIN_DIR}/lsof"
}

WT_A="${TMP}/wt/abc"
WT_B="${TMP}/wt/abc-def"
mkdir -p "${WT_A}" "${WT_B}"
# Canonicalize once, up front: lv2_lane_worker_alive now realpath-normalizes
# its wt_path argument to match what a real lsof always reports (resolved,
# symlink-free -- macOS /tmp is /private/tmp, $TMPDIR is under
# /private/var/...). If WT_A/WT_B stayed non-canonical here, every stub
# below that embeds them verbatim as the fake cwd would be comparing a
# canonical wt_path against a non-canonical cwd and never match, testing a
# shape real lsof never produces.
WT_A="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "${WT_A}")"
WT_B="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "${WT_B}")"

run_lib_case() {  # <PATH override> <shell> <expr> -> stdout: expr's stdout, rc preserved
  local path_override="$1" shell="$2" expr="$3"
  PATH="${path_override}" "${shell}" -c "source '${LIB}'; ${expr}"
}

# --- alive / dead basic prefix match ---
set_fake_lsof "printf 'p111\nn${WT_A}\n'"
if run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "lib: alive -- cwd exactly equals worktree path"
else
  fail "lib: alive -- cwd exactly equals worktree path"
fi

set_fake_lsof "printf 'p111\nn/somewhere/unrelated\n'"
if ! run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "lib: dead -- no recorded cwd matches worktree"
else
  fail "lib: dead -- no recorded cwd matches worktree"
fi

# --- false-zero: rc=0, empty output must fail-closed to ALIVE ---
set_fake_lsof "exit 0"
if run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "false-zero: rc=0 empty lsof output fails closed to ALIVE"
else
  fail "false-zero: rc=0 empty lsof output fails closed to ALIVE"
fi

# --- lsof error (nonzero + empty) must also fail-closed to ALIVE ---
set_fake_lsof "exit 1"
if run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "lsof error: rc!=0 empty output fails closed to ALIVE"
else
  fail "lsof error: rc!=0 empty output fails closed to ALIVE"
fi

# --- lsof missing entirely from PATH must fail-closed to ALIVE ---
MISSING_BIN="${TMP}/missing-bin"
mkdir -p "${MISSING_BIN}"
for c in bash mktemp cat printf rm mkdir basename dirname sed grep cut sort head tail tr; do
  p="$(command -v "${c}" 2>/dev/null || true)"
  [[ -n "${p}" ]] && ln -sf "${p}" "${MISSING_BIN}/${c}"
done
if run_lib_case "${MISSING_BIN}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "lsof missing from PATH fails closed to ALIVE"
else
  fail "lsof missing from PATH fails closed to ALIVE"
fi

# --- mirror-dead: a sibling worktree whose name is a string-prefix collision
# must never cross-match a live process that belongs to the OTHER worktree.
set_fake_lsof "printf 'p222\nn${WT_B}/sub\n'"
if ! run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'"; then
  pass "mirror-dead: abc-def's live process does not falsely mark abc ALIVE"
else
  fail "mirror-dead: abc-def's live process does not falsely mark abc ALIVE"
fi
if run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_B}'"; then
  pass "mirror-dead: abc-def itself is correctly seen ALIVE"
else
  fail "mirror-dead: abc-def itself is correctly seen ALIVE"
fi

# --- false-life: a recorded PID handle is alive (kill -0 succeeds, using
# this test process's own pid) but its REAL cwd (per the same lsof pass) is
# NOT inside the worktree -- a reused pid must not fool the combined check.
REAL_PID=$$
set_fake_lsof "printf 'p${REAL_PID}\nn/somewhere/unrelated-reused\n'"
if ! run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_pid_alive_for '${REAL_PID}' '${WT_A}'"; then
  pass "false-life: kill -0 alive but cwd elsewhere -- pid rejected as this lane's worker"
else
  fail "false-life: kill -0 alive but cwd elsewhere -- pid rejected as this lane's worker"
fi
if ! run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_alive_combined '${WT_A}' '${REAL_PID}'"; then
  pass "false-life: combined verdict is DEAD despite a live-but-reused pid handle"
else
  fail "false-life: combined verdict is DEAD despite a live-but-reused pid handle"
fi

# --- several-handles-one-alive: D4 -- ANY alive wins, ALL dead is required for DEAD ---
set_fake_lsof "printf 'p${REAL_PID}\nn${WT_A}\n'"
PID_LIST=$'99999991\n'"${REAL_PID}"$'\n99999992'
if run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_any_alive '${PID_LIST}' '${WT_A}'"; then
  pass "several-handles-one-alive: ANY alive pid wins"
else
  fail "several-handles-one-alive: ANY alive pid wins"
fi
ALL_DEAD_LIST=$'99999991\n99999992\n99999993'
if ! run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_any_alive '${ALL_DEAD_LIST}' '${WT_A}'"; then
  pass "several-handles-one-alive: ALL dead -> DEAD"
else
  fail "several-handles-one-alive: ALL dead -> DEAD"
fi

# --- D5: bash vs zsh must agree on every one of the above outcomes ---
if command -v zsh >/dev/null 2>&1; then
  set_fake_lsof "printf 'p111\nn${WT_A}\n'"
  bash_rc=0; run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_worker_alive '${WT_A}'" || bash_rc=$?
  zsh_rc=0; run_lib_case "${BIN_DIR}:${PATH}" zsh "lv2_lane_worker_alive '${WT_A}'" || zsh_rc=$?
  if [[ "${bash_rc}" == "${zsh_rc}" ]]; then
    pass "bash/zsh agree: alive case (rc=${bash_rc})"
  else
    fail "bash/zsh agree: alive case" "bash rc=${bash_rc} zsh rc=${zsh_rc}"
  fi

  set_fake_lsof "printf 'p${REAL_PID}\nn${WT_A}\n'"
  bash_rc=0; run_lib_case "${BIN_DIR}:${PATH}" bash "lv2_lane_any_alive '${PID_LIST}' '${WT_A}'" || bash_rc=$?
  zsh_rc=0; run_lib_case "${BIN_DIR}:${PATH}" zsh "lv2_lane_any_alive '${PID_LIST}' '${WT_A}'" || zsh_rc=$?
  if [[ "${bash_rc}" == "${zsh_rc}" ]]; then
    pass "bash/zsh agree: several-handles-one-alive (rc=${bash_rc})"
  else
    fail "bash/zsh agree: several-handles-one-alive" "bash rc=${bash_rc} zsh rc=${zsh_rc}"
  fi
else
  pass "bash/zsh agreement (zsh not installed -- skipped, not a hidden fail)"
fi

# =============================================================================
# Section B: full-script acceptance A1-A6 (real scratch git worktrees)
# =============================================================================
mk_repo() {  # -> stdout: repo path
  local repo="${TMP}/repo-$$-${RANDOM}"
  mkdir -p "${repo}"
  git -C "${repo}" init -q -b main
  git -C "${repo}" config user.email test@example.com
  git -C "${repo}" config user.name test
  printf 'baseline\n' > "${repo}/README.md"
  git -C "${repo}" add README.md
  git -C "${repo}" commit -qm baseline
  printf '%s\n' "${repo}"
}

mk_lane() {  # <repo> <lane> -> stdout: worktree path
  # NOTE: word expansion for an entire `local a=.. b=.. c=$a` command line
  # happens BEFORE any of the local bindings are created, so `wt="${repo}/.."`
  # on the SAME local statement as `repo="$1"` reads the OLD (unset) global
  # `repo`, not the just-declared local -- unbound under `set -u`. Split into
  # separate statements.
  local repo="$1" lane="$2"
  local wt="${repo}/.claude/worktrees/${lane}"
  git -C "${repo}" worktree add -q "${wt}" -b "worktree-${lane}" >/dev/null 2>&1
  printf '%s\n' "${wt}"
}

dead_lsof() { set_fake_lsof "printf 'p1\nn/nowhere/at/all\n'"; }
# Real lsof always reports a resolved (symlink-free) cwd -- macOS /tmp is
# /private/tmp, $TMPDIR is under /private/var/... -- so the stub must
# canonicalize too, or it is testing a cwd shape lsof never actually
# produces. Matches the same realpath fix in lv2_lane_worker_alive.
alive_lsof() { local wt; wt="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1")"; set_fake_lsof "printf 'p1\nn${wt}\n'"; }

run_ckpt() {  # <repo> [--dry-run]
  PATH="${BIN_DIR}:${PATH}" bash "${CKPT}" --project-root "$1" "${2:-}" 2>"${TMP}/last-stderr.log"
}

# --- A1: dirty tracked + untracked files, worker dead -> single commit, no manual git command ---
REPO_A1="$(mk_repo)"
WT_A1="$(mk_lane "${REPO_A1}" "lane-a1")"
printf 'tracked-change\n' >> "${WT_A1}/README.md"
printf 'new-untracked\n' > "${WT_A1}/scratch-untracked.txt"
before_head="$(git -C "${WT_A1}" rev-parse HEAD)"
dead_lsof
run_ckpt "${REPO_A1}"
after_head="$(git -C "${WT_A1}" rev-parse HEAD)"
dirty_after="$(git -C "${WT_A1}" status --porcelain --untracked-files=all)"
if [[ "${before_head}" != "${after_head}" && -z "${dirty_after}" ]]; then
  pass "A1: SIGKILL worker -> checkpoint commits tracked+untracked, tree clean after"
else
  fail "A1: SIGKILL worker -> checkpoint commits tracked+untracked, tree clean after" "before=${before_head} after=${after_head} dirty=[${dirty_after}]"
fi

# --- A2: many dirty files (the 7-lane / 11-20-files case), worker dead -> one commit ---
REPO_A2="$(mk_repo)"
WT_A2="$(mk_lane "${REPO_A2}" "lane-a2")"
for i in $(seq 1 14); do printf 'file-%d\n' "${i}" > "${WT_A2}/many-${i}.txt"; done
before_commits="$(git -C "${WT_A2}" rev-list --count HEAD)"
dead_lsof
run_ckpt "${REPO_A2}"
after_commits="$(git -C "${WT_A2}" rev-list --count HEAD)"
dirty_after="$(git -C "${WT_A2}" status --porcelain --untracked-files=all)"
added=$((after_commits - before_commits))
if [[ "${added}" -eq 1 && -z "${dirty_after}" ]]; then
  pass "A2: process-group-kill scale (14 dirty files) -> exactly ONE commit"
else
  fail "A2: process-group-kill scale (14 dirty files) -> exactly ONE commit" "added=${added} dirty=[${dirty_after}]"
fi

# --- A3: idempotent -- exactly ONE (ORPHAN) commit across 2 runs, 2nd run skipped_clean ---
REPO_A3="$(mk_repo)"
WT_A3="$(mk_lane "${REPO_A3}" "lane-a3")"
printf 'idempotent-check\n' > "${WT_A3}/idempotent.txt"
dead_lsof
run_ckpt "${REPO_A3}"
orphan_commits_run1="$(git -C "${WT_A3}" log --oneline --grep='(ORPHAN)' | wc -l | tr -d ' ')"
head_after_run1="$(git -C "${WT_A3}" rev-parse HEAD)"
dead_lsof
run_ckpt "${REPO_A3}"
head_after_run2="$(git -C "${WT_A3}" rev-parse HEAD)"
orphan_commits_run2="$(git -C "${WT_A3}" log --oneline --grep='(ORPHAN)' | wc -l | tr -d ' ')"
if [[ "${orphan_commits_run1}" == "1" && "${orphan_commits_run2}" == "1" && "${head_after_run1}" == "${head_after_run2}" ]] \
  && grep -q "skipped_clean" "${TMP}/last-stderr.log"; then
  pass "A3: idempotent -- exactly ONE (ORPHAN) commit across 2 runs, 2nd run skipped_clean"
else
  fail "A3: idempotent -- exactly ONE (ORPHAN) commit across 2 runs, 2nd run skipped_clean" \
    "run1=${orphan_commits_run1} run2=${orphan_commits_run2} head1=${head_after_run1} head2=${head_after_run2}"
fi

# --- A4: clean lane -> HEAD unchanged, no empty commit ---
REPO_A4="$(mk_repo)"
WT_A4="$(mk_lane "${REPO_A4}" "lane-a4")"
before_head="$(git -C "${WT_A4}" rev-parse HEAD)"
dead_lsof
run_ckpt "${REPO_A4}"
after_head="$(git -C "${WT_A4}" rev-parse HEAD)"
if [[ "${before_head}" == "${after_head}" ]]; then
  pass "A4: clean lane -> HEAD unchanged, no empty commit"
else
  fail "A4: clean lane -> HEAD unchanged, no empty commit" "before=${before_head} after=${after_head}"
fi

# --- A5: live worker (cwd inside worktree) -> skipped_alive, nothing committed ---
REPO_A5="$(mk_repo)"
WT_A5="$(mk_lane "${REPO_A5}" "lane-a5")"
printf 'still-being-edited\n' > "${WT_A5}/inflight.txt"
before_head="$(git -C "${WT_A5}" rev-parse HEAD)"
alive_lsof "${WT_A5}"
run_ckpt "${REPO_A5}"
after_head="$(git -C "${WT_A5}" rev-parse HEAD)"
if [[ "${before_head}" == "${after_head}" ]] && grep -q "skipped_alive" "${TMP}/last-stderr.log"; then
  pass "A5: live worker (cwd inside worktree) -> skipped_alive, nothing committed"
else
  fail "A5: live worker (cwd inside worktree) -> skipped_alive, nothing committed" \
    "before=${before_head} after=${after_head} log=$(cat "${TMP}/last-stderr.log")"
fi

# --- A6: out-of-scope dirty file -> orphan-quarantine/<lane>, NOT the lane branch ---
REPO_A6="$(mk_repo)"
LANE_A6="lane-a6"
WT_A6="$(mk_lane "${REPO_A6}" "${LANE_A6}")"
# Canonicalize: the checkpointer enumerates worktrees via `git worktree list
# --porcelain`, which always returns a resolved path, so meta.yaml's `cwd:`
# line must match that resolved form or _lv2_orphan_find_run_meta's exact
# grep never matches (same class as the A5 lsof-cwd fix above).
WT_A6="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "${WT_A6}")"
mkdir -p "${WT_A6}/src" "${WT_A6}/scratch"
printf 'in-scope\n' > "${WT_A6}/src/feature.txt"
printf 'out-of-scope\n' > "${WT_A6}/scratch/notes.txt"
RUN_CACHE="${TMP}/cache-a6"
RUN_DIR="${RUN_CACHE}/glm-runs/run-a6"
mkdir -p "${RUN_DIR}"
printf 'cwd: %s\nprompt_file: %s/prompt.txt\n' "${WT_A6}" "${RUN_DIR}" > "${RUN_DIR}/meta.yaml"
printf 'LANE_WRITES: src/\nDo the feature.\n' > "${RUN_DIR}/prompt.txt"
dead_lsof
LEADV2_ORPHAN_RUN_CACHE_ROOT="${RUN_CACHE}" PATH="${BIN_DIR}:${PATH}" \
  bash "${CKPT}" --project-root "${REPO_A6}" 2>"${TMP}/last-stderr.log"
inscope_on_lane="$(git -C "${WT_A6}" log --oneline -- src/feature.txt 2>/dev/null)"
outscope_on_lane="$(git -C "${WT_A6}" log --oneline -- scratch/notes.txt 2>/dev/null)"
outscope_on_quarantine="$(git -C "${WT_A6}" log --oneline "refs/heads/orphan-quarantine/${LANE_A6}" -- scratch/notes.txt 2>/dev/null)"
if [[ -n "${inscope_on_lane}" && -z "${outscope_on_lane}" && -n "${outscope_on_quarantine}" ]]; then
  pass "A6: out-of-scope dirty file lands on orphan-quarantine/<lane>, not the lane branch"
else
  fail "A6: out-of-scope dirty file lands on orphan-quarantine/<lane>, not the lane branch" \
    "inscope_on_lane=[${inscope_on_lane}] outscope_on_lane=[${outscope_on_lane}] outscope_on_quarantine=[${outscope_on_quarantine}]"
fi

# --- D12: --dry-run and LEADV2_ORPHAN_CHECKPOINT=0 both make no commits ---
REPO_D12A="$(mk_repo)"
WT_D12A="$(mk_lane "${REPO_D12A}" "lane-d12a")"
printf 'dry-run-check\n' > "${WT_D12A}/dry.txt"
before_head="$(git -C "${WT_D12A}" rev-parse HEAD)"
dead_lsof
run_ckpt "${REPO_D12A}" --dry-run
after_head="$(git -C "${WT_D12A}" rev-parse HEAD)"
if [[ "${before_head}" == "${after_head}" ]]; then
  pass "D12: --dry-run makes no commits"
else
  fail "D12: --dry-run makes no commits" "before=${before_head} after=${after_head}"
fi

REPO_D12B="$(mk_repo)"
WT_D12B="$(mk_lane "${REPO_D12B}" "lane-d12b")"
printf 'flag-off-check\n' > "${WT_D12B}/off.txt"
before_head="$(git -C "${WT_D12B}" rev-parse HEAD)"
dead_lsof
LEADV2_ORPHAN_CHECKPOINT=0 PATH="${BIN_DIR}:${PATH}" bash "${CKPT}" --project-root "${REPO_D12B}" >/dev/null 2>&1
after_head="$(git -C "${WT_D12B}" rev-parse HEAD)"
if [[ "${before_head}" == "${after_head}" ]]; then
  pass "D12: LEADV2_ORPHAN_CHECKPOINT=0 makes no commits"
else
  fail "D12: LEADV2_ORPHAN_CHECKPOINT=0 makes no commits" "before=${before_head} after=${after_head}"
fi

# =============================================================================
# Section C: negative control (D10) -- mutation INSIDE lv2_orphan_checkpoint_lane()'s
# body must turn A1 RED; revert must turn it GREEN again. Run for real, both ways.
# =============================================================================
run_a1_only() {  # -> rc0 pass, rc1 fail
  local repo wt before after dirty
  repo="$(mk_repo)"
  wt="$(mk_lane "${repo}" "lane-negctl")"
  printf 'tracked-change\n' >> "${wt}/README.md"
  printf 'new-untracked\n' > "${wt}/scratch-untracked.txt"
  before="$(git -C "${wt}" rev-parse HEAD)"
  dead_lsof
  PATH="${BIN_DIR}:${PATH}" bash "${CKPT}" --project-root "${repo}" >/dev/null 2>&1
  after="$(git -C "${wt}" rev-parse HEAD)"
  dirty="$(git -C "${wt}" status --porcelain --untracked-files=all)"
  [[ "${before}" != "${after}" && -z "${dirty}" ]]
}

if [[ "${SKIP_NEGATIVE_CONTROL:-0}" != "1" ]]; then
  cp "${CKPT}" "${CKPT}.negctl.bak"
  # D10 mutation #1 (required): --untracked-files=all -> --untracked-files=no,
  # inside lv2_orphan_checkpoint_lane()'s own body (the (b) dirty-detection line).
  sed -i.tmp 's/git -C "\${wt_path}" status --porcelain --untracked-files=all/git -C "${wt_path}" status --porcelain --untracked-files=no/' "${CKPT}"
  rm -f "${CKPT}.tmp"
  if grep -q -- '--untracked-files=no' "${CKPT}"; then
    if run_a1_only; then
      echo "NEGATIVE CONTROL FAILED TO REDDEN: mutation #1 (untracked-files=no) -- A1 still passed" >&2
      neg1_rc=0
    else
      neg1_rc=1
    fi
  else
    echo "NEGATIVE CONTROL SETUP FAILED: sed did not apply mutation #1" >&2
    neg1_rc=2
  fi
  echo "NEGATIVE CONTROL #1 (mutated, untracked-files=no) A1 exit observation: RED=${neg1_rc} (1=correctly RED, 0=FAILED TO REDDEN)"
  cp "${CKPT}.negctl.bak" "${CKPT}"
  if run_a1_only; then
    neg1_revert_rc=0
  else
    neg1_revert_rc=1
  fi
  echo "NEGATIVE CONTROL #1 (reverted) A1 exit observation: rc=${neg1_revert_rc} (0=correctly GREEN, 1=still failing)"
  if [[ "${neg1_rc}" == "1" && "${neg1_revert_rc}" == "0" ]]; then
    pass "D10 negative control #1: untracked-files mutation turns A1 RED, revert turns it GREEN"
  else
    fail "D10 negative control #1: untracked-files mutation turns A1 RED, revert turns it GREEN" \
      "mutated_rc=${neg1_rc} reverted_rc=${neg1_revert_rc}"
  fi

  # D10 mutation #2 (optional): delete the `diff --cached --quiet` guard inside
  # _lv2_orphan_inscope_commit() -- must turn A4 (clean lane, no empty commit) RED.
  python3 - "${CKPT}" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
needle = '''  if GIT_INDEX_FILE="${idx}" git -C "${lane_root}" diff --cached --quiet 2>/dev/null; then
    rm -f "${idx}"
    return 2
  fi
'''
assert needle in text, "guard block not found verbatim -- refusing to mutate blindly"
text = text.replace(needle, "", 1)
with open(path, 'w') as f:
    f.write(text)
PY
  py_rc=$?
  run_a4_only() {
    local repo wt before after
    repo="$(mk_repo)"
    wt="$(mk_lane "${repo}" "lane-negctl2")"
    before="$(git -C "${wt}" rev-parse HEAD)"
    dead_lsof
    PATH="${BIN_DIR}:${PATH}" bash "${CKPT}" --project-root "${repo}" >/dev/null 2>&1
    after="$(git -C "${wt}" rev-parse HEAD)"
    [[ "${before}" == "${after}" ]]
  }
  if [[ "${py_rc}" == "0" ]]; then
    if run_a4_only; then
      neg2_rc=0
    else
      neg2_rc=1
    fi
  else
    echo "NEGATIVE CONTROL SETUP FAILED: python3 did not apply mutation #2" >&2
    neg2_rc=2
  fi
  echo "NEGATIVE CONTROL #2 (mutated, no diff --cached --quiet guard) A4 exit observation: RED=${neg2_rc} (1=correctly RED, 0=FAILED TO REDDEN)"
  cp "${CKPT}.negctl.bak" "${CKPT}"
  if run_a4_only; then
    neg2_revert_rc=0
  else
    neg2_revert_rc=1
  fi
  echo "NEGATIVE CONTROL #2 (reverted) A4 exit observation: rc=${neg2_revert_rc} (0=correctly GREEN, 1=still failing)"
  if [[ "${neg2_rc}" == "1" && "${neg2_revert_rc}" == "0" ]]; then
    pass "D10 negative control #2 (optional): missing diff --cached --quiet guard turns A4 RED, revert turns it GREEN"
  else
    fail "D10 negative control #2 (optional): missing diff --cached --quiet guard turns A4 RED, revert turns it GREEN" \
      "mutated_rc=${neg2_rc} reverted_rc=${neg2_revert_rc}"
  fi

  rm -f "${CKPT}.negctl.bak"
else
  pass "D10 negative control (SKIP_NEGATIVE_CONTROL=1 -- explicitly skipped)"
fi

# =============================================================================
printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
