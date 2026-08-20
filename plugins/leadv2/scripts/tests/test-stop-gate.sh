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

# ── harness runner (falsifiable red-first baseline, same idiom as
# test-builder-selfcheck-gate.sh) ───────────────────────────────────────────────────
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-sg.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if git -C "${LEADV2_REPO}" grep -q pc_stop_gate_autocommit "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="HEAD~1"
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

rm -rf "${PREFIX_DIR}"

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
