#!/usr/bin/env bash
# tests/test-review-gate-scope-evidence.sh — REVIEW-GATE-INFRA-01 D-A regression.
#
# Three defects fixed in leadv2-dispatch-product-close.sh's empty-scoped-diff path:
#  (1) a declared write under docs/leadv2/ or docs/handoff/ is EXCLUDED by construction
#      (_pc_git_diff's own exclusion pathspec) -- pc_precheck_writes must bounce EARLY
#      with reason=undiffable_write_set naming the offending path, instead of burning a
#      worker wait and then blaming the lane.
#  (2) unscoped_lane_work must still fire for a genuine undeclared out-of-scope write,
#      and now names the offending path (offending: line in review-gate.md) instead of
#      only a bare dirty: <count>.
#  (3) a declared write that resolves outside any git work tree (the lane legitimately
#      targets another repo the diff-scoping code cannot see) must classify as
#      cross_repo_elsewhere, not fold into unscoped_lane_work.
#
# Red-first harness (same convention as test-lane-writes-scoping.sh): every case runs
# TWICE, once against a `git archive HEAD` extraction (PREFIX_SCRIPTS -- committed
# baseline, pre-fix) and once against this working tree (SCRIPT_DIR -- fix applied).
# A case must FAIL against PREFIX_SCRIPTS and PASS against SCRIPT_DIR. NEVER git
# stash/reset/clean -- the fix is deliberately left uncommitted so HEAD stays pre-fix.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"

PASS=0
FAIL=0
GREEN_PRE_FIX=0
COULD_NOT_RUN=0
ERRORS=()

log() { printf -- '[TEST] %s\n' "$*"; }

# F12 (SC2043): a single fixed target, no loop needed.
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

# ── shared fixtures ─────────────────────────────────────────────────────────────
new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rgse.XXXXXX")"
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

# ── Case 1 (D-A-i): a write-set that is ENTIRELY under docs/handoff/ (zero surviving
# paths) is inevitably excluded -- pc_precheck_writes must bounce EARLY, naming the
# path, before any worker wait. A MIXED write-set (some paths survive) must NOT bounce
# here -- see case 1b. ───────────────────────────────────────────────────────────────
case_undiffable_write_set() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="uws-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="docs/handoff/dispatch-${tid}/scratch.md" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" uwssig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-uwssig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^reason: undiffable_write_set$' "${gate}" \
     && grep -q '^paths: docs/handoff' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Case 1b (F1): a MIXED write-set (one path survives the docs/handoff exclusion,
# one does not) must NOT bounce early -- the surviving path proceeds to the scope
# diff and the voided path is recorded as an additive `undiffable:` key, never as
# `undiffable_write_set`. The surviving path (agent/seed.py) is left untouched, so
# the lane still blocks overall (no bytes) -- the assertion is keyed on the PRESENCE
# of the new `undiffable:` key, which merge-base code cannot emit at all. ───────────
case_mixed_write_set_not_bounced() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="mws-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py,docs/handoff/dispatch-${tid}/scratch.md" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" mwssig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-mwssig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^undiffable: docs/handoff/' "${gate}" \
     && ! grep -q 'undiffable_write_set' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Case 2 (D-A-ii): genuine undeclared write still blocks unscoped_lane_work, and
# the offending path is now named in review-gate.md instead of a bare dirty count. ──
case_unscoped_names_offending() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d
  root="$(new_repo)"
  tid="uno-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  # declared write untouched (0 bytes) -- the ONLY real edit is to an undeclared path.
  printf 'undeclared out-of-scope edit\n' >> "${wt}/agent/undeclared.py"
  git -C "${wt}" add -A >/dev/null 2>&1 || true
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" unosig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-unosig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^reason: unscoped_lane_work$' "${gate}" \
     && grep -q '^offending: agent/undeclared.py' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# NOTE (R3): a prior case_cross_repo_write_not_bounced here (a single write path that
# legitimately resolves to a separate real git repo via symlink) is DROPPED, not
# re-keyed. It duplicates case_h5 in test-lane-writes-scoping.sh, and produces the
# identical `status: pass` verdict both before and after this round's fix -- the
# resolved-repo attribution path it exercises predates round 1 and is untouched by
# it (confirmed via `git diff <merge-base> -- leadv2-dispatch-product-close.sh`).
# Keeping it under the new green-pre-fix vacuity gate (F6) would be a permanent
# false failure, not a regression guard.

# ── Case 4 (F2 / D-A-iv real regression): a declared write that resolves OUTSIDE any
# git work tree, where the ONLY dirty evidence in the lane is that same declared path
# (a symlink named identically to its own declared entry), must classify as
# cross_repo_elsewhere -- never unscoped_lane_work. Pre-fix (no partition logic at
# all) any dirty lane collapsed straight to unscoped_lane_work; that is the exact
# false verdict this round's D-A(ii)/D-A(iv) partition fixes. ──────────────────────
case_cross_repo_elsewhere_terminal() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${pc}" ]] || return 2
  local root tid wt d outside
  root="$(new_repo)"
  tid="cre-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d)"
  outside="${d}/outside-non-git"
  mkdir -p "${outside}"
  printf 'not in any git tree\n' > "${outside}/thing.py"
  ln -s "${outside}" "${wt}/ext"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="ext" LEADV2_LANE_WORK_ROOT="${wt}" LEADV2_REVIEW_DIFF_CROSS_REPO=1 \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${pc}" "${root}" cresig001 sonnet "" 0 1 "${tid}" >/dev/null 2>&1
  local gate="${root}/docs/handoff/dispatch-cresig001/review-gate.md"
  local ok=1
  if [[ -f "${gate}" ]] && grep -q '^reason: cross_repo_elsewhere$' "${gate}" \
     && ! grep -q 'unscoped_lane_work' "${gate}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── harness runner (falsifiable red-first baseline, F6) ─────────────────────────────
# `git archive HEAD` stopped being a valid pre-fix baseline the moment this suite's own
# fix landed on HEAD (the lane commit) -- every case would then run identically pre-
# and post-fix and silently report green-pre-fix forever. Baseline against the merge-
# base with origin/main instead (or an explicit override), falling back to HEAD only
# when neither resolves (e.g. no network / no origin remote in this checkout).
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-rgse.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  # pinned pre-fix floor: merge-base self-nullifies once the fix reaches origin/main,
  # so if the baseline tree already contains the fix marker, fall back to the pinned pre-fix SHA
  if git -C "${LEADV2_REPO}" grep -q _pc_norm_write "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="9e03dc0"
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
    log "GREEN-PRE-FIX: ${name} -- passed against HEAD too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

run_case "undiffable-write-set-bounces-early"     case_undiffable_write_set
run_case "mixed-write-set-not-bounced"             case_mixed_write_set_not_bounced
run_case "unscoped-lane-work-names-offending"      case_unscoped_names_offending
run_case "cross-repo-elsewhere-terminal"           case_cross_repo_elsewhere_terminal

rm -rf "${PREFIX_DIR}"

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
