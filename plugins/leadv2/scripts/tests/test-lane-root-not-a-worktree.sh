#!/usr/bin/env bash
# REVIEW-GATE-LANEROOT-01 regression: an unregistered lane directory is never
# allowed to make the close gate grade its parent repository.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE_WT_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"
PASS=0
FAIL=0
GREEN_PRE_FIX=0
ERRORS=()

log() { printf '[TEST] %s\n' "$*"; }

new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lrnaw.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com &&
    git config user.name test && mkdir -p agent && printf '.claude/worktrees/\n' > .gitignore &&
    printf 'seed\n' > agent/seed.py && git add .gitignore agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}

worktree_path() { printf '%s/.claude/worktrees/%s' "$1" "$2"; }
ensure_worktree() {
  LEADV2_PROJECT_ROOT="$1" bash "${LANE_WT_BIN}" ensure "$2" standard >/dev/null 2>&1
  worktree_path "$1" "$2"
}

make_resolver_stub() {
  printf '#!/usr/bin/env python3\nprint("reviewer=codex")\nprint("pool=codex")\nprint("refusal=")\n' > "$1"
  chmod +x "$1"
}
make_review_pass_stub() {
  printf '#!/usr/bin/env bash\nprintf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\n"\n' > "$1"
  chmod +x "$1"
}

run_gate() { # <scripts-dir> <root> <sig> <tid> <lane> <cache>
  local scripts_dir="$1" root="$2" sig="$3" tid="$4" lane="$5" cache="$6"
  make_resolver_stub "${cache}/resolver.py"
  make_review_pass_stub "${cache}/codex.sh"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${cache}/cache" \
  LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_LANE_WORK_ROOT="${lane}" \
  LEADV2_GLM_POLICY_RESOLVER="${cache}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${cache}/codex.sh" \
  bash "${scripts_dir}/leadv2-dispatch-product-close.sh" "${root}" "${sig}" sonnet '' 0 1 "${tid}" >/dev/null 2>&1
}

case_unregistered_parent_dirt() { # <scripts-dir>
  local scripts_dir="$1" root tid lane d gate top
  root="$(new_repo)"; tid="lrna-dirty-$$"; lane="${root}/.claude/worktrees/${tid}"; d="$(mktemp -d)"
  mkdir -p "${lane}/plugins/lib"
  printf 'lane product\n' > "${lane}/plugins/lib/produced.sh"
  printf 'parent dirt one\n' > "${root}/parent-one.txt"
  printf 'parent dirt two\n' > "${root}/parent-two.txt"
  run_gate "${scripts_dir}" "${root}" lrnadrty01 "${tid}" "${lane}" "${d}"
  gate="${root}/docs/handoff/dispatch-lrnadrty01/review-gate.md"; top="$(cd "${root}" && pwd -P)"
  if [[ -f "${gate}" ]] && grep -qx 'reason: lane_root_not_a_worktree' "${gate}" &&
     ! grep -q '^offending:' "${gate}" && grep -qx "resolved_toplevel: ${top}" "${gate}" &&
     grep -qx "expected_lane_root: ${lane}" "${gate}" && grep -q '^produced: plugins/lib/produced.sh' "${gate}"; then
    rm -rf "${root}" "${d}"; return 0
  fi
  rm -rf "${root}" "${d}"; return 1
}

case_registered_unscoped() { # <scripts-dir>
  local scripts_dir="$1" root tid wt d gate
  root="$(new_repo)"; tid="lrna-good-$$"; wt="$(ensure_worktree "${root}" "${tid}")"; d="$(mktemp -d)"
  [[ -d "${wt}" ]] || { rm -rf "${root}" "${d}"; return 1; }
  printf 'undeclared\n' > "${wt}/agent/undeclared.py"
  run_gate "${scripts_dir}" "${root}" lrnagood01 "${tid}" "${wt}" "${d}"
  gate="${root}/docs/handoff/dispatch-lrnagood01/review-gate.md"
  if [[ -f "${gate}" ]] && grep -qx 'reason: unscoped_lane_work' "${gate}" &&
     grep -q '^offending: agent/undeclared.py' "${gate}"; then
    rm -rf "${root}" "${d}"; return 0
  fi
  rm -rf "${root}" "${d}"; return 1
}

case_unregistered_silent_not_advanced() { # <scripts-dir>
  local scripts_dir="$1" root tid lane d handoff gate
  root="$(new_repo)"; tid="lrna-silent-$$"; lane="${root}/.claude/worktrees/${tid}"; d="$(mktemp -d)"
  mkdir -p "${lane}/plugins/lib"
  printf 'lane product\n' > "${lane}/plugins/lib/produced.sh"
  handoff="${root}/docs/handoff/dispatch-lrnaslnt01"; mkdir -p "${handoff}"
  printf 'arm=sonnet\n' > "${handoff}/arm-registered"
  run_gate "${scripts_dir}" "${root}" lrnaslnt01 "${tid}" "${lane}" "${d}"
  gate="${handoff}/review-gate.md"
  if [[ -f "${gate}" ]] && ! grep -qx 'reason: arm_produced_nothing' "${gate}" &&
     ! [[ -e "${handoff}/.arm-advanced-sonnet" ]]; then
    rm -rf "${root}" "${d}"; return 0
  fi
  rm -rf "${root}" "${d}"; return 1
}

PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-prefix-lrnaw.XXXXXX")"
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel)"
SKIP=0
# RED-FIRST-SELF-INVALIDATES-01: a floating `merge-base origin/main HEAD` is
# armed, not yet fired -- it detonates the moment REVIEW-GATE-LANEROOT-01's fix
# reaches origin/main, at which point every merge-base in this branch's future
# also contains the fix and pre==post forever. Pin to the fix's intro commit.
source "${SCRIPT_DIR}/lib/leadv2-red-first-baseline.sh"
LEADV2_REPO="${REPO}"
BASE="$(lv2_rf_baseline_ref 'REVIEW-GATE-LANEROOT-01' plugins/leadv2/scripts '8f0e0668ba80b856feea6e5efc0971ec400c7c35^')"; rf_rc=$?
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
if [[ ${rf_rc} -eq 0 ]]; then
  lv2_rf_extract "${BASE}" "${PREFIX_DIR}" plugins/leadv2/scripts >/dev/null 2>&1 || rf_rc=3
fi

run_case() {
  local name="$1" fn="$2" pre post
  "${fn}" "${SCRIPT_DIR}" >/dev/null 2>&1; post=$?
  if [[ ${post} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post}"); log "FAIL: ${name}"; return
  fi
  if [[ ${rf_rc} -ne 0 ]]; then
    SKIP=$((SKIP + 1)); log "SKIP: red-first baseline unresolvable — ${name}"; return
  fi
  "${fn}" "${PREFIX_SCRIPTS}" >/dev/null 2>&1; pre=$?
  if [[ ${pre} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1)); ERRORS+=("${name}: green pre-fix"); log "GREEN-PRE-FIX: ${name}"; return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre} -> post_rc=0)"
}

# This is deliberately an invariance control. The scoped design requires this
# registered-worktree behaviour to be unchanged, so both archive and working-tree
# implementations must pass it; treating its expected pre-fix pass as a red/green
# failure would make the regression suite reject the stated non-goal.
run_control() {
  local name="$1" fn="$2" pre post
  "${fn}" "${SCRIPT_DIR}" >/dev/null 2>&1; post=$?
  if [[ ${rf_rc} -ne 0 ]]; then
    if [[ ${post} -eq 0 ]]; then
      SKIP=$((SKIP + 1)); log "SKIP: red-first baseline unresolvable — ${name}"
    else
      FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post}"); log "FAIL: ${name}"
    fi
    return
  fi
  "${fn}" "${PREFIX_SCRIPTS}" >/dev/null 2>&1; pre=$?
  if [[ ${pre} -eq 0 && ${post} -eq 0 ]]; then
    PASS=$((PASS + 1)); log "CONTROL-PASSES: ${name} (pre_rc=0, post_rc=0)"; return
  fi
  FAIL=$((FAIL + 1)); ERRORS+=("${name}: expected pre/post rc=0, got ${pre}/${post}"); log "FAIL: ${name}"
}

if bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" && /bin/bash -n "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"; then
  PASS=$((PASS + 1)); log 'PASS: bash and /bin/bash syntax'
else
  FAIL=$((FAIL + 1)); ERRORS+=('product-close shell syntax'); log 'FAIL: product-close shell syntax'
fi
run_case unregistered-parent-dirt case_unregistered_parent_dirt
run_control registered-unscoped-positive-control case_registered_unscoped
run_case unregistered-silent-not-advanced case_unregistered_silent_not_advanced
rm -rf "${PREFIX_DIR}"

printf '\nResults: %s passed(red->green), %s failed, %s green-pre-fix, %s skipped\n' "${PASS}" "${FAIL}" "${GREEN_PRE_FIX}" "${SKIP}"
if [[ ${FAIL} -gt 0 || ${GREEN_PRE_FIX} -gt 0 ]]; then
  printf 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
