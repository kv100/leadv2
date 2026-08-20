#!/usr/bin/env bash
# tests/test-builder-selfcheck-gate.sh — BUILDER-SELFCHECK-GATE-01 (round 2).
#
# Part A (unchanged from round 1): full leadv2-dispatch-product-close.sh lane runs,
# red-first against the pinned pre-fix baseline (the lib file does not exist at that
# ref, so this is the only part of the suite that can be scored red->green).
#
# Part B (new, round 2 / H3): the lib file itself (lib/leadv2-builder-selfcheck.sh) does
# not exist at the pinned baseline ref, so a case that sources it directly has no
# pre-fix counterpart to diff against -- it would score COULD_NOT_RUN on every such
# case, which is not useful signal. These cases are direct-only (same convention as
# case 5 below), asserted against the CURRENT (fixed) lib only, and cover exactly the
# suite-resolution/depth-guard/timeout/baseline-attribution branches the round-2 design
# calls out (C1, C2, H1, H3, M1, M3). Every case pins
# LEADV2_BUILDER_SELFCHECK_TIMEOUT_S=3 and uses trivial fixtures to keep the wall clock
# under ~25s.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"
LIB_SH="${SCRIPT_DIR}/lib/leadv2-builder-selfcheck.sh"

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
if [[ -f "${LIB_SH}" ]] && bash -n "${LIB_SH}" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: bash -n lib/leadv2-builder-selfcheck.sh"
else
  FAIL=$((FAIL + 1)); ERRORS+=("bash -n lib/leadv2-builder-selfcheck.sh"); log "FAIL: bash -n lib/leadv2-builder-selfcheck.sh"
fi
if [[ -f "${LIB_SH}" ]] && /bin/bash -n "${LIB_SH}" 2>/dev/null; then
  PASS=$((PASS + 1)); log "PASS: /bin/bash -n lib/leadv2-builder-selfcheck.sh (bash 3.2 syntax)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("bash -n lib/leadv2-builder-selfcheck.sh (3.2)"); log "FAIL: /bin/bash -n lib/leadv2-builder-selfcheck.sh (bash 3.2)"
fi

# ── shared fixtures (same idiom as test-review-gate-scope-evidence.sh) ──────────────
new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg.XXXXXX")"
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

make_resolver_stub() { # <path> <reviewer-arm>
  cat > "$1" <<PYEOF
#!/usr/bin/env python3
print("reviewer=$2")
print("pool=$2")
print("refusal=")
PYEOF
  chmod +x "$1"
}

make_review_pass_stub() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
exit 0
EOF
  chmod +x "$1"
}

make_review_sentinel_stub() { # <path> <sentinel-file>
  cat > "$1" <<EOF
#!/usr/bin/env bash
touch "$2"
exit 0
EOF
  chmod +x "$1"
}

# ── Case 1: a lane whose only changed *.sh has a syntax error ──────────────────────
case_broken_sh_blocks() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="bsh-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'if true; then\n  echo "missing fi"\n' > "${wt}/agent/broken.sh"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/broken.sh" LEADV2_LANE_WORK_ROOT="${wt}" \
  bash "${pc}" "${root}" bshsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-bshsig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^status: blocked$' "${gate}" \
     && grep -q '^reason: selfcheck_failed$' "${gate}" \
     && grep -q 'broken.sh' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case 2: same broken lane must never reach the review arm (sentinel absent) ─────
case_broken_sh_no_review_arm() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d sentinel
  root="$(new_repo)"
  tid="bshr-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'if true; then\n  echo "missing fi"\n' > "${wt}/agent/broken.sh"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  d="$(mktemp -d)"
  sentinel="${d}/review-arm-ran"
  make_review_sentinel_stub "${d}/engine.sh" "${sentinel}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/broken.sh" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_REVIEW_ENGINE=1 LEADV2_REVIEW_RUN_BIN="${d}/engine.sh" \
  bash "${pc}" "${root}" bshrsig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-bshrsig001/review-gate.md"
  local ok=1
  if [[ ! -f "${sentinel}" ]] && [[ -f "${gate}" ]] && grep -q '^reason: selfcheck_failed$' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Case 3: a clean lane (valid .sh + .py) gets a GREEN selfcheck.md ────────────────
case_clean_lane_green() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="cln-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf '#!/usr/bin/env bash\necho ok\n' > "${wt}/agent/good.sh"
  printf 'def ok():\n    return 1\n' > "${wt}/agent/good.py"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/good.sh,agent/good.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK_TESTS=never \
  bash "${pc}" "${root}" clnsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local sc="${root}/docs/handoff/dispatch-clnsig001/selfcheck.md"
  local ok=1
  if [[ -f "${sc}" ]] && grep -q '^verdict: GREEN$' "${sc}"; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case 4: a changed *.py failing py_compile blocks the lane ──────────────────────
case_broken_py_blocks() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt
  root="$(new_repo)"
  tid="bpy-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'def broken(\n    pass\n' > "${wt}/agent/broken.py"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/broken.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  bash "${pc}" "${root}" bpysig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-bpysig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^reason: selfcheck_failed$' "${gate}" \
     && grep -q 'broken.py' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# ── Case 6: no downstream arm will run (both kill-switches off) AND a live worker
# already completed (HANDLE non-empty) -- selfcheck must SKIP (reason=no_arm), not
# block, even though the appended content is syntactically broken. Round-2 finding
# C3 / ask-lead escalation option (a): nothing downstream would be protected by
# running it here. ─────────────────────────────────────────────────────────────────
case_no_arm_skip_selfcheck() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d handle run_dir errf
  root="$(new_repo)"
  tid="nas-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'def broken(\n    pass\n' > "${wt}/agent/broken.py"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  d="$(mktemp -d)"; handle="nas-handle-$$"; errf="$(mktemp)"
  run_dir="${d}/glm-runs/${handle}"; mkdir -p "${run_dir}"
  printf 'status: complete\npid: 999999\n' > "${run_dir}/meta.yaml"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/broken.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  GLM_RUNS_DIR="${d}/glm-runs" \
  bash "${pc}" "${root}" nasig001 glm "${handle}" 0 0 "${tid}" >/dev/null 2>"${errf}"
  local ok=1
  grep -q 'selfcheck task=nasig001 status=skipped reason=no_arm' "${errf}" && ok=0
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Case 7: a report-declared lane must SKIP selfcheck (reason=report_lane) --
# bash -n/py_compile is a category error against a prose deliverable, per the
# REPORT-ONLY-GATE-01 lane-kind convention this gate now honors explicitly. ────────
case_report_lane_skip_selfcheck() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt errf
  root="$(new_repo)"
  tid="rls-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/analysis"
  {
    printf '# Report\n\n'
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
      printf 'Line %s of a report long enough to clear the report_too_thin floor.\n' "${_i}"
    done
  } > "${wt}/analysis/report.md"
  errf="$(mktemp)"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="analysis/report.md" \
  LEADV2_DISPATCH_LANE_DELIVERABLE="report:analysis/report.md" LEADV2_LANE_WORK_ROOT="${wt}" \
  bash "${pc}" "${root}" rlsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>"${errf}"
  local ok=1
  grep -q 'selfcheck task=rlsig001 status=skipped reason=report_lane' "${errf}" && ok=0
  rm -rf "${root}"; rm -f "${errf}"
  return "${ok}"
}

# ── harness runner (falsifiable red-first baseline, same F6 lesson as 85ae886) ─────
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-bscg.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  # pinned pre-fix floor: merge-base self-nullifies once this fix reaches origin/main,
  # so if the baseline tree already contains the fix marker, fall back to the pinned
  # pre-fix SHA (same lesson as 85ae886 for test-review-gate-scope-evidence.sh).
  if git -C "${LEADV2_REPO}" grep -q lv2_selfcheck_run "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="85ae886"
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

run_case "broken-sh-blocks-with-reason"     case_broken_sh_blocks
run_case "broken-sh-review-arm-never-spent" case_broken_sh_no_review_arm
run_case "clean-lane-selfcheck-green"       case_clean_lane_green
run_case "broken-py-blocks-with-reason"     case_broken_py_blocks
run_case "no-arm-skips-selfcheck"           case_no_arm_skip_selfcheck
run_case "report-lane-skips-selfcheck"      case_report_lane_skip_selfcheck

rm -rf "${PREFIX_DIR}"

# ── Case 5 (direct-only, NOT red-first): the kill switch restores today's path
# byte-for-byte in EITHER tree -- by definition pre-fix and post-fix are identical
# here, so this cannot be scored via the red/green diff harness above without
# permanently tripping the GREEN_PRE_FIX vacuity gate. Checked only against the
# fixed tree (SCRIPT_DIR): no selfcheck.md, no selfcheck_failed reason. ────────────
case_kill_switch_restores_old_path() {
  local root tid wt
  root="$(new_repo)"
  tid="ksw-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'if true; then\n  echo "missing fi"\n' > "${wt}/agent/broken.sh"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_LANE_WRITES="agent/broken.sh" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_BUILDER_SELFCHECK=0 \
  bash "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" "${root}" kswsig001 sonnet "" 0 0 "${tid}" >/dev/null 2>&1
  local sc="${root}/docs/handoff/dispatch-kswsig001/selfcheck.md"
  local gate="${root}/docs/handoff/dispatch-kswsig001/review-gate.md"
  local ok=1
  if [[ ! -f "${sc}" ]] && { [[ ! -f "${gate}" ]] || ! grep -q 'selfcheck_failed' "${gate}"; }; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}
if case_kill_switch_restores_old_path; then
  PASS=$((PASS + 1)); log "PASS: kill-switch LEADV2_BUILDER_SELFCHECK=0 restores old path (no selfcheck.md, no selfcheck_failed)"
else
  FAIL=$((FAIL + 1)); ERRORS+=("kill-switch did not restore old path"); log "FAIL: kill-switch LEADV2_BUILDER_SELFCHECK=0"
fi

# ═══════════════════════════════════════════════════════════════════════════════════
# Part B: direct lv2_selfcheck_run / _lv2_selfcheck_timeout_run coverage (H3).
# Direct-only (not red-first): lib/leadv2-builder-selfcheck.sh does not exist at the
# pinned baseline ref at all, so there is no pre-fix counterpart to diff against --
# every such case would score COULD_NOT_RUN via run_case, which is not useful signal.
# Same convention as case 5 above: asserted only against the current (fixed) lib.
# ═══════════════════════════════════════════════════════════════════════════════════

write_diff() { # <diff_file> <path...>
  local out="$1"; shift
  : > "${out}"
  local p
  for p in "$@"; do printf '+++ b/%s\n' "${p}" >> "${out}"; done
}

# Runs lv2_selfcheck_run in an isolated bash -c so each case can source a fresh lib
# copy (the delegate case stages its own scratch lib+e2e-entrypoint) without any two
# cases' function/global state leaking into each other.
run_selfcheck() { # <lib_sh> <diff_file> <diff_root> <project_root> <out_md> <resfile> [ENV=val ...]
  local lib_sh="$1" diff_file="$2" diff_root="$3" project_root="$4" out_md="$5" resfile="$6"; shift 6
  # LEADV2_E2E_GATE=0 by default: without it, `auto` mode calls the REAL
  # leadv2-e2e-entrypoint.sh (this test sources the live lib in place, not a scratch
  # copy) against a throwaway fixture root, which is both slow and can spuriously
  # delegate away the suite check these cases exist to exercise. Case 11 overrides it.
  env LEADV2_E2E_GATE=0 "$@" LEADV2_BUILDER_SELFCHECK_TIMEOUT_S="${LEADV2_BUILDER_SELFCHECK_TIMEOUT_S:-3}" bash -c '
    source "$1"
    # must not be `_fn_out="$(lv2_selfcheck_run ...)"` -- that runs the function in a
    # subshell, so the LV2_SELFCHECK_* globals it sets never reach this scope.
    _fn_tmp="$(mktemp)"
    lv2_selfcheck_run "$2" "$3" "$4" "$5" "${LV2_TEST_WRITE_SET:-}" > "${_fn_tmp}"
    _rc=$?
    _fn_out="$(cat "${_fn_tmp}")"
    rm -f "${_fn_tmp}"
    {
      printf "FAILED_NAMES=%s\n" "${_fn_out}"
      printf "RC=%s\n" "${_rc}"
      printf "CHECKS=%s\n" "${LV2_SELFCHECK_CHECKS:-}"
      printf "SKIPPED=%s\n" "${LV2_SELFCHECK_SKIPPED:-}"
      printf "FAILEDCNT=%s\n" "${LV2_SELFCHECK_FAILED:-}"
      printf "DEPTH_SKIP=%s\n" "${LV2_SELFCHECK_DEPTH_SKIP:-}"
    } > "$6"
  ' _ "${lib_sh}" "${diff_file}" "${diff_root}" "${project_root}" "${out_md}" "${resfile}"
}

resfield() { grep -m1 "^$2=" "$1" | cut -d= -f2-; } # <resfile> <KEY>

pb_case() { # <name> <fn>
  local name="$1" fn="$2"
  if "${fn}"; then
    PASS=$((PASS + 1)); log "PASS: ${name}"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("${name}"); log "FAIL: ${name}"
  fi
}

# -- 1: stem suite resolved from ${diff_root}/tests -- M3 --------------------------
case_stem_from_lane_tests_dir() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  local sentinel="${root}/ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel}" > "${root}/tests/test-probe1.sh"
  chmod +x "${root}/tests/test-probe1.sh"
  printf 'x\n' > "${root}/agent/probe1.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe1.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local rc; rc="$(resfield "${res}" RC)"
  local ok=1
  [[ -f "${sentinel}" && "${rc}" == "0" ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 2: plugins/leadv2/scripts/tests/ under diff_root takes priority over tests/ ----
case_stem_priority_plugin_tests_dir() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/plugins/leadv2/scripts/tests" "${root}/agent"
  local sentinel_a="${root}/ran_a" sentinel_b="${root}/ran_b"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel_a}" > "${root}/tests/test-probe2.sh"
  chmod +x "${root}/tests/test-probe2.sh"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel_b}" > "${root}/plugins/leadv2/scripts/tests/test-probe2.sh"
  chmod +x "${root}/plugins/leadv2/scripts/tests/test-probe2.sh"
  printf 'x\n' > "${root}/agent/probe2.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe2.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local ok=1
  [[ -f "${sentinel_b}" && ! -f "${sentinel_a}" ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 3: suite green -> checks>=1, verdict GREEN, rc 0 -------------------------------
case_suite_green() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/tests/test-probe3.sh"
  chmod +x "${root}/tests/test-probe3.sh"
  printf 'x\n' > "${root}/agent/probe3.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe3.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local rc checks ok=1
  rc="$(resfield "${res}" RC)"; checks="$(resfield "${res}" CHECKS)"
  [[ "${rc}" == "0" && "${checks}" -ge 1 ]] && grep -q '^verdict: GREEN$' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 4: suite red, baseline (merge-base main) green -> rc 1, failed_names has it ----
case_suite_red_baseline_green() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t ) >/dev/null 2>&1
  mkdir -p "${root}/tests" "${root}/agent"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/tests/test-probe4.sh"
  chmod +x "${root}/tests/test-probe4.sh"
  printf 'x\n' > "${root}/agent/probe4.txt"
  ( cd "${root}" && git add -A && git commit -qm base ) >/dev/null 2>&1
  ( cd "${root}" && git checkout -qb lane ) >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nexit 1\n' > "${root}/tests/test-probe4.sh"
  ( cd "${root}" && git add -A && git commit -qm red ) >/dev/null 2>&1
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe4.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" == "1" ]] && [[ "${names}" == *"suites:test-probe4"* ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 5: suite red, baseline (main == HEAD) also red -> not blocked, SKIP baseline_red
case_suite_red_baseline_red() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t ) >/dev/null 2>&1
  mkdir -p "${root}/tests" "${root}/agent"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/tests/test-probe5.sh"
  chmod +x "${root}/tests/test-probe5.sh"
  printf 'x\n' > "${root}/agent/probe5.txt"
  ( cd "${root}" && git add -A && git commit -qm base ) >/dev/null 2>&1
  ( cd "${root}" && git checkout -qb lane ) >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nexit 1\n' > "${root}/tests/test-probe5.sh"
  ( cd "${root}" && git add -A && git commit -qm red ) >/dev/null 2>&1
  ( cd "${root}" && git branch -f main lane ) >/dev/null 2>&1
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe5.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  # checks decision E: this suite is the only check attempted and it fully skips, so
  # checks nets to 0 -> DEGRADED (rc 2), not GREEN -- never RED (rc 1, blocked).
  local rc failedcnt ok=1
  rc="$(resfield "${res}" RC)"; failedcnt="$(resfield "${res}" FAILEDCNT)"
  [[ "${rc}" != "1" && "${failedcnt}" == "0" ]] && grep -q 'SKIP (baseline_red)' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 6: baseline unresolvable (diff_root is not a git repo) -> SKIP baseline_unresolved
case_baseline_unresolved() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${root}/tests/test-probe6.sh"
  chmod +x "${root}/tests/test-probe6.sh"
  printf 'x\n' > "${root}/agent/probe6.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe6.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local rc ok=1
  rc="$(resfield "${res}" RC)"
  [[ "${rc}" != "1" ]] && grep -q 'SKIP (baseline_unresolved)' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 7: child suite observes LEADV2_BUILDER_SELFCHECK=0 and _DEPTH=1 ---------------
case_child_env_flag_and_depth() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  local probe="${root}/probe.env"
  cat > "${root}/tests/test-probe7.sh" <<EOF
#!/usr/bin/env bash
printf 'FLAG=%s\n' "\${LEADV2_BUILDER_SELFCHECK:-unset}" > "${probe}"
printf 'DEPTH=%s\n' "\${LEADV2_BUILDER_SELFCHECK_DEPTH:-unset}" >> "${probe}"
exit 0
EOF
  chmod +x "${root}/tests/test-probe7.sh"
  printf 'x\n' > "${root}/agent/probe7.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe7.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local ok=1
  if [[ -f "${probe}" ]] && grep -q '^FLAG=0$' "${probe}" && grep -q '^DEPTH=1$' "${probe}"; then
    ok=0
  fi
  rm -rf "${root}"
  return "${ok}"
}

# -- 8: LEADV2_BUILDER_SELFCHECK_DEPTH=1 on entry -> SKIP depth_guard, no spawn -----
case_depth_guard_skips() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  local sentinel="${root}/ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel}" > "${root}/tests/test-probe8.sh"
  chmod +x "${root}/tests/test-probe8.sh"
  printf 'x\n' > "${root}/agent/probe8.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe8.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" LEADV2_BUILDER_SELFCHECK_DEPTH=1
  local depth_skip ok=1
  depth_skip="$(resfield "${res}" DEPTH_SKIP)"
  [[ ! -f "${sentinel}" ]] && [[ "${depth_skip}" == "1" ]] && grep -q 'SKIP (depth_guard:1)' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 9: the repo-level runner is NEVER invoked (decision A / C1) -------------------
case_no_repo_runner_invoked() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  local sentinel="${root}/run-all-ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel}" > "${root}/tests/run-all.sh"
  chmod +x "${root}/tests/run-all.sh"
  printf 'x\n' > "${root}/agent/nomatch.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/nomatch.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}"
  local ok=1
  [[ ! -f "${sentinel}" ]] && grep -q 'SKIP (no_matching_suite)' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 10: tests_mode=never -> SKIP suite_disabled -----------------------------------
case_tests_mode_never() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  local sentinel="${root}/always-ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "${sentinel}" > "${root}/tests/test-probe10.sh"
  chmod +x "${root}/tests/test-probe10.sh"
  printf 'x\n' > "${root}/agent/probe10.txt"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe10.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" LEADV2_BUILDER_SELFCHECK_TESTS=never
  local ok=1
  grep -q 'SKIP (suite_disabled)' "${out_md}" || { rm -rf "${root}"; return 1; }
  # `always` deliberately bypasses an available e2e delegate and runs only the
  # matched lane suite. This keeps the broad runner owned by the e2e stage while
  # preserving an explicit way to force the diff-scoped check.
  rm -f "${sentinel}"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=always LEADV2_E2E_GATE=1
  [[ -f "${sentinel}" ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 11: tests_mode=auto + e2e delegate available -> SKIP delegated_to_e2e ---------
case_auto_delegates_to_e2e() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/tests" "${root}/agent"
  printf 'x\n' > "${root}/agent/probe11.txt"
  local scratch; scratch="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-scratch.XXXXXX")"
  mkdir -p "${scratch}/lib"
  cp "${LIB_SH}" "${scratch}/lib/leadv2-builder-selfcheck.sh"
  cat > "${scratch}/leadv2-e2e-entrypoint.sh" <<'EOF'
#!/usr/bin/env bash
echo "bash tests/run-all.sh --scope changed"
exit 0
EOF
  chmod +x "${scratch}/leadv2-e2e-entrypoint.sh"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/probe11.txt"
  run_selfcheck "${scratch}/lib/leadv2-builder-selfcheck.sh" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" LEADV2_E2E_GATE=1
  local ok=1
  grep -q 'SKIP (delegated_to_e2e)' "${out_md}" && ok=0
  rm -rf "${root}" "${scratch}"
  return "${ok}"
}

# -- 12/13: portable timeout wrapper, gtimeout/timeout masked out of PATH ----------
mask_timeout_path() {
  local out="" d
  local IFS=':'
  local -a dirs=(${PATH})
  for d in "${dirs[@]}"; do
    [[ -x "${d}/timeout" || -x "${d}/gtimeout" ]] && continue
    out="${out:+${out}:}${d}"
  done
  printf '%s' "${out}"
}

case_timeout_wrapper_kills_hung_command() {
  local masked; masked="$(mask_timeout_path)"
  local log; log="$(mktemp)"
  local rc
  SECONDS=0
  PATH="${masked}" bash -c 'source "$1"; _lv2_selfcheck_timeout_run 2 "$2" -- sleep 30' _ "${LIB_SH}" "${log}"
  rc=$?
  local elapsed=${SECONDS}
  rm -f "${log}"
  [[ "${rc}" == "124" && "${elapsed}" -lt 8 ]]
}

case_timeout_wrapper_fast_command_no_hang() {
  local masked; masked="$(mask_timeout_path)"
  local log; log="$(mktemp)"
  local out
  SECONDS=0
  out="$(PATH="${masked}" bash -c 'source "$1"; _lv2_selfcheck_timeout_run 5 "$2" -- /bin/echo hi; echo "RC=$?"' _ "${LIB_SH}" "${log}")"
  local elapsed=${SECONDS}
  rm -f "${log}"
  [[ "${out}" == *"RC=0"* && "${elapsed}" -lt 3 ]]
}

# -- 14: checks=0 (diff touches only unresolvable paths) -> rc 2, DEGRADED ---------
case_checks_zero_degraded() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/agent"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/does-not-exist.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" LEADV2_BUILDER_SELFCHECK_TESTS=never
  local rc ok=1
  rc="$(resfield "${res}" RC)"
  [[ "${rc}" == "2" ]] && grep -q '^verdict: DEGRADED$' "${out_md}" && grep -q '^reason: no_check_ran$' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 15: bash -n failure -> rc 1 regardless of baseline (no baseline arm on syntax) -
case_bash_n_failure_no_baseline_arm() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-b.XXXXXX")"
  mkdir -p "${root}/agent"
  printf 'if true; then\n  echo "missing fi"\n' > "${root}/agent/broken.sh"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/broken.sh"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" LEADV2_BUILDER_SELFCHECK_TESTS=never
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" == "1" ]] && [[ "${names}" == *"bash-n:broken.sh"* ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# ═══════════════════════════════════════════════════════════════════════════════════
# Part C: SCOPE-DISCIPLINE-01 (C0) + TEST-FALSIFICATION-GATE-01 (C4). Direct-only
# (same convention as Part B): both checks are brand new in this lib, so there is no
# prior committed ref that lacks them where a pinned-SHA fallback would still make
# sense once this lands on main (the Part A/85ae886 self-nullification problem, but
# with no historical SHA to pin to since the feature never existed before). Asserted
# only against the current (fixed) LIB_SH. Red-first-ness for these two checks is
# demonstrated manually in the deliverable (pre-edit lib via `git show HEAD:...`
# does not have C0/C4 at all -> both scenarios below pass through as DEGRADED/GREEN
# there, never RED) rather than baked into this always-green-post-fix harness.
# ═══════════════════════════════════════════════════════════════════════════════════

# -- 16: SCOPE-DISCIPLINE-01 -- a changed path outside the declared write-set blocks
case_scope_off_write_set_blocks() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  mkdir -p "${root}/agent"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/off.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LV2_TEST_WRITE_SET="agent/allowed.txt"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" == "1" ]] && [[ "${names}" == *"scope:off_write_set"* ]] \
    && grep -q 'off.txt' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 17: a changed path INSIDE the declared write-set is not blocked by scope -------
case_scope_in_write_set_passes() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  mkdir -p "${root}/agent"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/off.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LV2_TEST_WRITE_SET="agent/off.txt,agent/other.txt"
  local names ok=1
  names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${names}" != *"scope:"* ]] && grep -q 'write-set honored' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 18: SCOPE-DISCIPLINE-01 -- more changed files than the max blocks as oversized -
case_scope_oversized_diff_blocks() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  mkdir -p "${root}/agent"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  local -a many=()
  local i
  for ((i = 0; i < 45; i++)); do many+=("agent/file${i}.txt"); done
  write_diff "${diff_file}" "${many[@]}"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LEADV2_SCOPE_DISCIPLINE_MAX_FILES=40 LV2_TEST_WRITE_SET="agent"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" == "1" ]] && [[ "${names}" == *"scope:oversized_diff"* ]] && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 19: SCOPE-DISCIPLINE-01 -- kill switch LEADV2_SCOPE_DISCIPLINE=0 restores old path
case_scope_kill_switch_restores_old_path() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  mkdir -p "${root}/agent"
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/off.txt"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LEADV2_SCOPE_DISCIPLINE=0 LV2_TEST_WRITE_SET="agent/allowed.txt"
  local names ok=1
  names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${names}" != *"scope:"* ]] && grep -q 'scope_discipline_disabled' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 20: TEST-FALSIFICATION-GATE-01 -- a lying-green test (passes even pre-fix, i.e.
# unconditionally exits 0 regardless of the code it's meant to guard) is refused ----
case_falsification_lying_green_blocks() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && mkdir -p tests agent && printf 'seed\n' > agent/seed.py \
    && git add -A && git commit -qm base ) >/dev/null 2>&1
  ( cd "${root}" && git checkout -qb lane ) >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/tests/test-lying.sh"
  chmod +x "${root}/tests/test-lying.sh"
  ( cd "${root}" && git add -A && git commit -qm 'add lying-green test' ) >/dev/null 2>&1
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "tests/test-lying.sh"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LV2_TEST_WRITE_SET="tests/test-lying.sh"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" == "1" ]] && [[ "${names}" == *"falsification:green_pre_fix"* ]] \
    && grep -q 'GREEN against pre-fix baseline' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 21: TEST-FALSIFICATION-GATE-01 -- a test that genuinely fails against the
# pre-fix baseline (real falsification proof) is NOT blocked, and the raw RED
# evidence is captured in selfcheck.md -------------------------------------------
case_falsification_real_proof_passes() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && mkdir -p tests agent && printf 'bug\n' > agent/target.txt \
    && git add -A && git commit -qm base ) >/dev/null 2>&1
  ( cd "${root}" && git checkout -qb lane ) >/dev/null 2>&1
  printf 'fixed\n' > "${root}/agent/target.txt"
  printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/.."\n[[ "$(cat agent/target.txt)" == "fixed" ]]\n' > "${root}/tests/test-realproof.sh"
  chmod +x "${root}/tests/test-realproof.sh"
  ( cd "${root}" && git add -A && git commit -qm 'fix + real test' ) >/dev/null 2>&1
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "agent/target.txt" "tests/test-realproof.sh"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LV2_TEST_WRITE_SET="tests/test-realproof.sh,agent/target.txt"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" != "1" ]] && [[ "${names}" != *"falsification:green_pre_fix"* ]] \
    && grep -q 'RED against pre-fix baseline' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

# -- 22: TEST-FALSIFICATION-GATE-01 -- kill switch restores old path ---------------
case_falsification_kill_switch_restores_old_path() {
  local root; root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-bscg-c.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && mkdir -p tests agent && printf 'seed\n' > agent/seed.py \
    && git add -A && git commit -qm base ) >/dev/null 2>&1
  ( cd "${root}" && git checkout -qb lane ) >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/tests/test-lying2.sh"
  chmod +x "${root}/tests/test-lying2.sh"
  ( cd "${root}" && git add -A && git commit -qm 'add lying-green test' ) >/dev/null 2>&1
  local diff_file="${root}/diff.patch" out_md="${root}/out.md" res="${root}/res"
  write_diff "${diff_file}" "tests/test-lying2.sh"
  run_selfcheck "${LIB_SH}" "${diff_file}" "${root}" "${root}" "${out_md}" "${res}" \
    LEADV2_BUILDER_SELFCHECK_TESTS=never LEADV2_TEST_FALSIFICATION_GATE=0 LV2_TEST_WRITE_SET="tests/test-lying2.sh"
  local rc names ok=1
  rc="$(resfield "${res}" RC)"; names="$(resfield "${res}" FAILED_NAMES)"
  [[ "${rc}" != "1" ]] && [[ "${names}" != *"falsification:"* ]] \
    && grep -q 'falsification_gate_disabled' "${out_md}" && ok=0
  rm -rf "${root}"
  return "${ok}"
}

pb_case "stem-resolved-from-lane-tests-dir (M3)"          case_stem_from_lane_tests_dir
pb_case "stem-priority-plugins-tests-over-tests (M3)"     case_stem_priority_plugin_tests_dir
pb_case "suite-green-checks-verdict"                      case_suite_green
pb_case "suite-red-baseline-green-fails"                  case_suite_red_baseline_green
pb_case "suite-red-baseline-red-skips (H1)"                case_suite_red_baseline_red
pb_case "baseline-unresolved-fails-open (H1)"              case_baseline_unresolved
pb_case "child-suite-observes-flag-and-depth (C1)"         case_child_env_flag_and_depth
pb_case "depth-guard-skips-no-spawn (C1)"                  case_depth_guard_skips
pb_case "repo-level-runner-never-invoked (C1/decision-A)"  case_no_repo_runner_invoked
pb_case "tests-mode-never-skips"                           case_tests_mode_never
pb_case "auto-mode-delegates-to-e2e"                       case_auto_delegates_to_e2e
pb_case "timeout-wrapper-kills-hung-command (C2)"          case_timeout_wrapper_kills_hung_command
pb_case "timeout-wrapper-fast-command-no-hang (C2)"        case_timeout_wrapper_fast_command_no_hang
pb_case "checks-zero-yields-degraded (M1)"                 case_checks_zero_degraded
pb_case "bash-n-failure-ignores-baseline-arm"              case_bash_n_failure_no_baseline_arm
pb_case "scope-off-write-set-blocks (SCOPE-DISCIPLINE-01)"        case_scope_off_write_set_blocks
pb_case "scope-in-write-set-passes (SCOPE-DISCIPLINE-01)"         case_scope_in_write_set_passes
pb_case "scope-oversized-diff-blocks (SCOPE-DISCIPLINE-01)"       case_scope_oversized_diff_blocks
pb_case "scope-kill-switch-restores-old-path (SCOPE-DISCIPLINE-01)" case_scope_kill_switch_restores_old_path
pb_case "falsification-lying-green-blocks (TEST-FALSIFICATION-GATE-01)" case_falsification_lying_green_blocks
pb_case "falsification-real-proof-passes (TEST-FALSIFICATION-GATE-01)" case_falsification_real_proof_passes
pb_case "falsification-kill-switch-restores-old-path (TEST-FALSIFICATION-GATE-01)" case_falsification_kill_switch_restores_old_path

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
