#!/usr/bin/env bash
# tests/test-stop-gate.sh — V3-STOP-GATE-01.
#
# Disease this closes (live, 2026-08-19/20): 6+ worker exits left real work
# UNCOMMITTED in the lane worktree -- invisible to every downstream phase and
# one parallel session away from being clobbered (SUPDEL 47 files, V3-GLM 24,
# ENV-GUARDS 6, T2 twice -- the lead had to checkpoint-commit by hand each
# time). pc_stop_gate_autocommit (leadv2-dispatch-product-close.sh) fires right
# after the worker's exit is confirmed and BEFORE any downstream phase reads
# the tree: auto-commits declared-write-set changes, leaves everything else
# alone.
#
# Red-first against the pinned pre-fix baseline (the function does not exist
# there, same harness idiom as test-builder-selfcheck-gate.sh).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"

PASS=0
FAIL=0
GREEN_PRE_FIX=0
COULD_NOT_RUN=0
ERRORS=()

log() { printf -- '[TEST] %s\n' "$*"; }

if bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: bash -n leadv2-dispatch-product-close.sh"
else
  FAIL=$((FAIL + 1)); ERRORS+=("bash -n leadv2-dispatch-product-close.sh"); log "FAIL: bash -n leadv2-dispatch-product-close.sh"
fi
if /bin/bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("/bin/bash -n product-close.sh (3.2)"); log "FAIL: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2)"
fi
if bash -n "${SCRIPT_DIR}/leadv2-dispatch-code.sh" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: bash -n leadv2-dispatch-code.sh"
else
  FAIL=$((FAIL + 1)); ERRORS+=("bash -n leadv2-dispatch-code.sh"); log "FAIL: bash -n leadv2-dispatch-code.sh"
fi

# ── shared fixtures (same idiom as test-builder-selfcheck-gate.sh) ────────────────
new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-sg.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}

worktree_path() { printf '%s/.claude/worktrees/%s' "$1" "$2"; }

ensure_worktree() {
  LEADV2_PROJECT_ROOT="$1" bash "${LANE_WT_BIN}" ensure "$2" standard >/dev/null 2>&1
  worktree_path "$1" "$2"
}

# ── Case A: a tracked file inside the declared write-set, modified but never
# committed by the worker -- pc_stop_gate_autocommit must commit it. ───────────────
case_tracked_writeset_gets_committed() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="sga-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'a\n' > "${wt}/agent/inscope.py"
  git -C "${wt}" add agent/inscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/agent/inscope.py"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${pc}" "${root}" sgasig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1
  local status
  status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  local msg
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  if [[ -z "${status}" ]] && [[ "${msg}" == *"STOP-GATE"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case B: an untracked file OUTSIDE the declared write-set must NOT be
# committed, even while an in-scope file is checkpointed. ──────────────────────────
case_out_of_scope_junk_not_committed() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="sgb-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'inscope\n' > "${wt}/agent/inscope.py"
  printf 'junk\n' > "${wt}/agent/outofscope.tmp"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${pc}" "${root}" sgbsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1
  local in_status out_status
  in_status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  out_status="$(git -C "${wt}" status --porcelain -- agent/outofscope.tmp 2>/dev/null || true)"
  if [[ -z "${in_status}" ]] && [[ "${out_status}" == '??'* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case B2: an already STAGED out-of-scope file must remain staged after an
# in-scope checkpoint. A normal `git commit` would silently launder it. ──────────
case_staged_out_of_scope_not_laundered() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="sgb2-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'in\n' > "${wt}/agent/inscope.py"
  printf 'out\n' > "${wt}/agent/outofscope.py"
  git -C "${wt}" add agent/inscope.py agent/outofscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'in changed\n' > "${wt}/agent/inscope.py"
  printf 'out changed\n' > "${wt}/agent/outofscope.py"
  git -C "${wt}" add agent/outofscope.py >/dev/null 2>&1
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${pc}" "${root}" sgb2sig01 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1 in_status out_staged committed
  in_status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  out_staged="$(git -C "${wt}" diff --cached --name-only -- agent/outofscope.py 2>/dev/null || true)"
  committed="$(git -C "${wt}" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true)"
  if [[ -z "${in_status}" && "${out_staged}" == "agent/outofscope.py" && "${committed}" == "agent/inscope.py" ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case D: a forward-looking write-set commonly includes paths the worker
# never created. The real modified path must still be committed, the journal
# must report the checkpoint, and unrelated junk must remain uncommitted. ─────
case_missing_declared_path_still_commits() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt journal_bin journal_log
  root="$(new_repo)"
  tid="sgd-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  journal_bin="${root}/journal.sh"
  journal_log="${root}/journal.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$4" >> "${LEADV2_TEST_JOURNAL}"\n' > "${journal_bin}"
  chmod +x "${journal_bin}"
  printf 'a\n' > "${wt}/agent/inscope.py"
  git -C "${wt}" add agent/inscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/agent/inscope.py"
  printf 'junk\n' > "${wt}/agent/outofscope.tmp"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py,tests/never-created.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 LEADV2_JOURNAL_BIN="${journal_bin}" LEADV2_TEST_JOURNAL="${journal_log}" \
  bash "${pc}" "${root}" sgdsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1 in_status out_status msg journal
  in_status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  out_status="$(git -C "${wt}" status --porcelain -- agent/outofscope.tmp 2>/dev/null || true)"
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  journal="$(cat "${journal_log}" 2>/dev/null || true)"
  if [[ -z "${in_status}" && "${out_status}" == '??'* && "${msg}" == *"STOP-GATE"* && "${journal}" == *"stop_gate_autocommit task=sgdsig001"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case E: porcelain -z represents a rename as the destination followed by
# a second NUL-delimited source path. The destination is what must be staged. ─
case_rename_stages_new_path() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="sge-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  local old_name=$'agent/old\tname.py' new_name=$'agent/new\tname.py'
  printf 'old\n' > "${wt}/${old_name}"
  git -C "${wt}" add "${old_name}" >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  git -C "${wt}" mv "${old_name}" "${new_name}" >/dev/null 2>&1
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${pc}" "${root}" sgesig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1 status msg
  status="$(git -C "${wt}" status --porcelain -- agent 2>/dev/null || true)"
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  if [[ -z "${status}" && -f "${wt}/${new_name}" && ! -e "${wt}/${old_name}" && "${msg}" == *"STOP-GATE"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case G: a declared write with a space in its name is exactly the shape
# `git status --porcelain=v1` (no -z) C-quotes; -z NUL-parsing must stage it
# without mangling. ──────────────────────────────────────────────────────────
case_space_in_name_gets_committed() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="sgg-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  local name="agent/in scope.py"
  printf 'a\n' > "${wt}/${name}"
  git -C "${wt}" add "${name}" >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/${name}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  bash "${pc}" "${root}" sggsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1 status msg
  status="$(git -C "${wt}" status --porcelain -- "${name}" 2>/dev/null || true)"
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  if [[ -z "${status}" && "${msg}" == *"STOP-GATE"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case F: a timed-out worker exits through the early `exit 5` path. The
# STOP-GATE must checkpoint before that terminal exit, not only after a clean
# worker exit. ───────────────────────────────────────────────────────────────
case_timeout_checkpoints_before_exit() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt worker_pid rc ok=1 status msg review_diff
  root="$(new_repo)"
  tid="sgf-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'a\n' > "${wt}/agent/inscope.py"
  git -C "${wt}" add agent/inscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/agent/inscope.py"
  sleep 30 & worker_pid=$!
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 LEADV2_PC_WORKER_MAX_WAIT_S=1 LEADV2_PC_WORKER_POLL_S=1 \
  bash "${pc}" "${root}" sgfsig001 sonnet "${worker_pid}" 0 0 "${tid}" >/dev/null 2>&1
  rc=$?
  kill "${worker_pid}" 2>/dev/null || true
  wait "${worker_pid}" 2>/dev/null || true
  status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  review_diff="$(cat "${root}/docs/handoff/dispatch-sgfsig001/review.diff" 2>/dev/null || true)"
  if [[ ${rc} -eq 5 && -z "${status}" && "${msg}" == *"STOP-GATE"* && "${review_diff}" == *"+b"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case H: a write-set path resolving into a SIBLING git repository (not the
# lane repo) must not be silently checkpointed from this repo -- it must be
# journaled as a loud skip so the missing checkpoint is diagnosable. ────────
case_foreign_repo_journaled() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt other journal_bin journal_log
  root="$(new_repo)"
  tid="sgh-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  other="$(new_repo)"
  printf 'foreign\n' > "${other}/agent/foreign.py"
  git -C "${other}" add agent/foreign.py >/dev/null 2>&1
  git -C "${other}" commit -qm foreign >/dev/null 2>&1
  printf 'a\n' > "${wt}/agent/inscope.py"
  git -C "${wt}" add agent/inscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/agent/inscope.py"
  printf 'foreign\nchanged\n' > "${other}/agent/foreign.py"
  journal_bin="${root}/journal.sh"
  journal_log="${root}/journal.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$4" >> "${LEADV2_TEST_JOURNAL}"\n' > "${journal_bin}"
  chmod +x "${journal_bin}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py,../../../../$(basename "${other}")/agent/foreign.py" \
  LEADV2_LANE_WORK_ROOT="${wt}" LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 \
  LEADV2_JOURNAL_BIN="${journal_bin}" LEADV2_TEST_JOURNAL="${journal_log}" \
  bash "${pc}" "${root}" sghsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1 in_status journal
  in_status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  journal="$(cat "${journal_log}" 2>/dev/null || true)"
  if [[ -z "${in_status}" && "${journal}" == *"stop_gate_skipped_foreign_repo task=sghsig001"* ]]; then
    ok=0
  fi
  rm -rf "${root}" "${other}"
  return "${ok}"
}

# ── harness runner (falsifiable red-first baseline, same idiom as
# test-builder-selfcheck-gate.sh) ───────────────────────────────────────────────────
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-sg.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if git -C "${LEADV2_REPO}" grep -q pc_stop_gate_autocommit "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh 2>/dev/null; then
    # STOP-GATE-BASELINE-DRIFT-01: the feature has been in origin/main since
    # 747f453 -- a fixed HEAD~1 fallback only walks back one commit and never
    # reaches a pre-feature tree once the feature is permanently upstream (every
    # commit in a lane's history, however far back, still has it, so every case
    # scores GREEN-PRE-FIX and the vacuity gate trips on every run). Find the
    # commit that actually introduced the marker via -S pickaxe and use its
    # parent as the true pre-feature baseline, independent of how long ago it
    # merged or how many commits this lane has stacked on top.
    _sg_intro_commit="$(git -C "${LEADV2_REPO}" log --reverse --format=%H -S'pc_stop_gate_autocommit' -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh 2>/dev/null | head -1)"
    if [[ -n "${_sg_intro_commit}" ]]; then
      LEADV2_TEST_BASELINE_REF="${_sg_intro_commit}^"
    else
      LEADV2_TEST_BASELINE_REF="HEAD~1"
    fi
  fi
fi
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="HEAD"
git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-dispatch-product-close.sh" ]]; then
  log "FATAL: git archive ${LEADV2_TEST_BASELINE_REF} extraction failed -- cannot run red-first harness"
  exit 1
fi

run_case() { # <name> <fn>
  local name="$1" fn="$2"
  local pre_rc post_rc
  "${fn}" "${PREFIX_SCRIPTS}" >/dev/null 2>&1; pre_rc=$?
  "${fn}" "${SCRIPT_DIR}" >/dev/null 2>&1; post_rc=$?

  if [[ ${pre_rc} -eq 2 || ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    log "COULD-NOT-RUN: ${name} (pre_rc=${pre_rc} post_rc=${post_rc})"
    return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix did not pass (rc=${post_rc})")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"
    return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against baseline too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

run_case "tracked-writeset-gets-committed" case_tracked_writeset_gets_committed
run_case "out-of-scope-junk-not-committed" case_out_of_scope_junk_not_committed
run_case "staged-out-of-scope-not-laundered" case_staged_out_of_scope_not_laundered
run_case "missing-declared-path-still-commits" case_missing_declared_path_still_commits
run_case "rename-stages-new-path" case_rename_stages_new_path
run_case "space-in-name-gets-committed" case_space_in_name_gets_committed
run_case "timeout-checkpoints-before-exit" case_timeout_checkpoints_before_exit
run_case "foreign-repo-journaled" case_foreign_repo_journaled

rm -rf "${PREFIX_DIR}"

# ── Case I (codex r3 ask): a worker timeout with an UNTRACKED declared file --
# review.diff must contain it AND the checkpoint commit must include it. No historic
# pre-fix ref applies here (pc_stop_gate_capture_diff already handles untracked paths
# on HEAD via add -N, same idiom as pc_scope_diff's _pc_git_diff), so the red leg is a
# SYNTHETIC mutant that reverts pc_stop_gate_capture_diff to plain `git diff HEAD`
# (same "pinned pre-fix mutant" idiom as test-builder-selfcheck-gate.sh's
# BUGGY_C0_LIB_SH, constructed mechanically instead of pinned to a SHA since this leg
# has no history to pin against). Plain `git diff HEAD` never shows an untracked path
# at all, so review.diff must go red on the mutant while the commit-side assertion
# (independent of capture_diff -- pc_stop_gate_autocommit computes its own git-status
# view) stays green on both trees. ──────────────────────────────────────────────────
MUTANT_DIR_I="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-mutant-sgi.XXXXXX")"
cp -R "${SCRIPT_DIR}/." "${MUTANT_DIR_I}/"
if ! python3 -c "
import re, sys
path = sys.argv[1]
src = open(path).read()
pattern = re.compile(r'^pc_stop_gate_capture_diff\(\) \{\n.*?\n\}\n', re.S | re.M)
mutant = '''pc_stop_gate_capture_diff() {
  local _ct_lane=\"\${LEADV2_LANE_WORK_ROOT:-}\"
  [[ -z \"\${_ct_lane}\" ]] && _ct_lane=\"\$(LEADV2_PROJECT_ROOT=\"\${ROOT}\" bash \"\${SCRIPT_DIR}/leadv2-lane-worktree.sh\" path-of \"\${FOUNDER_TASK_ID:-\${TASK}}\" 2>/dev/null || true)\"
  [[ -n \"\${_ct_lane}\" && -d \"\${_ct_lane}\" ]] || return 0
  mkdir -p \"\${HANDOFF}\" 2>/dev/null || true
  git -C \"\${_ct_lane}\" diff HEAD > \"\${HANDOFF}/review.diff\" 2>/dev/null || true
}
'''
new_src, n = pattern.subn(mutant, src, count=1)
if n != 1:
    sys.exit('mutation failed: expected 1 match, got %d' % n)
open(path, 'w').write(new_src)
" "${MUTANT_DIR_I}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  log "FATAL: could not build capture-diff mutant -- cannot run red-first Case I"
  exit 1
fi

case_untracked_timeout_capture_and_commit() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt worker_pid rc ok=1 status msg review_diff
  root="$(new_repo)"
  tid="sgi-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'brand new untracked content\n' > "${wt}/agent/untracked_new.py"
  sleep 30 & worker_pid=$!
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/untracked_new.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 LEADV2_PC_WORKER_MAX_WAIT_S=1 LEADV2_PC_WORKER_POLL_S=1 \
  bash "${pc}" "${root}" sgisig001 sonnet "${worker_pid}" 0 0 "${tid}" >/dev/null 2>&1
  rc=$?
  kill "${worker_pid}" 2>/dev/null || true
  wait "${worker_pid}" 2>/dev/null || true
  status="$(git -C "${wt}" status --porcelain -- agent/untracked_new.py 2>/dev/null || true)"
  msg="$(git -C "${wt}" log -1 --format=%s 2>/dev/null || true)"
  review_diff="$(cat "${root}/docs/handoff/dispatch-sgisig001/review.diff" 2>/dev/null || true)"
  if [[ ${rc} -eq 5 && -z "${status}" && "${msg}" == *"STOP-GATE"* && "${review_diff}" == *"brand new untracked content"* ]]; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

run_case_i() { # <name> <fn>
  local name="$1" fn="$2"
  local pre_rc post_rc
  "${fn}" "${MUTANT_DIR_I}" >/dev/null 2>&1; pre_rc=$?
  "${fn}" "${SCRIPT_DIR}" >/dev/null 2>&1; post_rc=$?
  if [[ ${pre_rc} -eq 2 || ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    log "COULD-NOT-RUN: ${name} (pre_rc=${pre_rc} post_rc=${post_rc})"
    return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix did not pass (rc=${post_rc})")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"
    return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the capture-diff mutant too"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}
run_case_i "untracked-timeout-capture-and-commit" case_untracked_timeout_capture_and_commit

rm -rf "${MUTANT_DIR_I}"

# ── Case C (direct-only, NOT red-first): the kill switch restores today's path
# byte-for-byte in EITHER tree -- pre-fix and post-fix are identical here
# (nothing ever commits), so scoring it via the red/green harness above would
# permanently trip the GREEN_PRE_FIX vacuity gate (same lesson as the
# BUILDER-SELFCHECK-GATE-01 kill-switch case). Checked only against the fixed
# tree (SCRIPT_DIR): the file must remain uncommitted. ─────────────────────────────
case_kill_switch_restores_old_path() {
  local root tid wt
  root="$(new_repo)"
  tid="sgc-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'a\n' > "${wt}/agent/inscope.py"
  git -C "${wt}" add agent/inscope.py >/dev/null 2>&1
  git -C "${wt}" commit -qm seed2 >/dev/null 2>&1
  printf 'a\nb\n' > "${wt}/agent/inscope.py"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/inscope.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_REVIEW_ENGINE=0 LEADV2_STOP_GATE=0 \
  bash "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" "${root}" sgcsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local ok=1
  local status
  status="$(git -C "${wt}" status --porcelain -- agent/inscope.py 2>/dev/null || true)"
  [[ -n "${status}" ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}
if case_kill_switch_restores_old_path; then
  PASS=$((PASS + 1)); log "PASS: kill-switch LEADV2_STOP_GATE=0 restores old path (file stays uncommitted)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("kill-switch did not restore old path"); log "FAIL: kill-switch LEADV2_STOP_GATE=0"
fi

echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf 'FAILURES:\n'
  printf ' - %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
