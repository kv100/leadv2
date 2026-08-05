#!/usr/bin/env bash
# tests/test-lane-diff-single-repo.sh — GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01.
#
# Falsifying harness for the single-repo close-gate fix: with
# LEADV2_REVIEW_DIFF_CROSS_REPO unset/0, a lane worktree holding uncommitted work must
# still be scoped (not discarded as no_work), while a genuinely clean/empty lane worktree
# must still terminate as no_work/empty_diff — the anti-rescue case.
#
#   C1 — lane worktree with an uncommitted TRACKED modification -> non-empty diff, no
#        no_work terminal.
#   C2 — lane worktree with a new UNTRACKED file matching LANE_WRITES -> non-empty diff,
#        no no_work terminal.
#   C3 — lane worktree clean (worker did nothing) -> terminal=no_work cause=empty_diff.
#        (negative half of the ARM-PRODUCES-NOTHING-02 minimal pair: no arm registered)
#   C4 — lane dirty ONLY under docs/handoff/ -> terminal=no_work (exclusion-set case).
#   C5 — same clean lane as C3 but WITH an arm-registered file -> terminal=no_work
#        cause=arm_produced_nothing. (positive half of the ARM-PRODUCES-NOTHING-02
#        minimal pair: C3 and C5 differ ONLY in the arm-registered file's presence.)
#
# Red-first: every case also runs against a `git archive HEAD` extraction (pre-fix). A
# case that is GREEN against pre-fix is reported as GREEN-PRE-FIX, never silently counted
# as evidence. C1/C2 MUST be red pre-fix (that is the defect this suite exists to catch).
#
# Safety: sandboxed HOME/TMPDIR, mtime tripwire over ~/Projects/leadv2/plugins and
# ~/.claude, never git stash/reset --hard/clean. Mirrors test-landing-diff-scoping.sh.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEADV2_REPO="$(cd "${SELF_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"

ORIG_HOME="${HOME}"
if [[ -z "${LDS1_SANDBOXED:-}" ]]; then
  SANDBOX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lds1-home.XXXXXX")"
  mkdir -p "${SANDBOX_HOME}/tmp"
  export HOME="${SANDBOX_HOME}" TMPDIR="${SANDBOX_HOME}/tmp" LDS1_SANDBOXED=1
fi

PASS_LABEL="${PASS_LABEL:-unlabelled}"
log() { printf -- '[TEST][%s] %s\n' "${PASS_LABEL}" "$*"; }

new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lds1.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}
worktree_path() { printf '%s/.claude/worktrees/%s' "$1" "$2"; }
ensure_worktree() {
  LEADV2_PROJECT_ROOT="$1" bash "${SELF_DIR}/leadv2-lane-worktree.sh" ensure "$2" standard >/dev/null 2>&1
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
# Direct call into the gate, cross=0 fixed (this suite is exclusively single-repo mode).
# Captures stderr (emit's target) so the caller can grep the terminal=/cause= line.
run_gate() { # <scripts_dir> <root> <task_sig8> <lane_work_root> <resolver_dir> <err_out> <writes_csv>
  local sd="$1" root="$2" sig="$3" lane="$4" d="$5" errf="$6" writes="${7:-agent/seed.py}"
  LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_LANE_WORK_ROOT="${lane}" LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${sd}/leadv2-dispatch-product-close.sh" "${root}" "${sig}" sonnet "" 0 1 "${sig}-founder" \
    >/dev/null 2>"${errf}"
}
gate_bytes() { local root="$1" sig="$2"; wc -c < "${root}/docs/handoff/dispatch-${sig}/review.diff" 2>/dev/null | tr -d ' '; }
gate_terminal_line() { local errf="$1"; grep 'review_gate ' "${errf}" 2>/dev/null | tail -1; }

# ── C1 — tracked modification in the lane worktree ─────────────────────────────────
case_c1_tracked_mod() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf
  root="$(new_repo)"; tid="c1-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  printf 'seed\nedited-in-worktree\n' > "${wt}/agent/seed.py"
  d="$(mktemp -d)"; errf="$(mktemp)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" c1sig001 "${wt}" "${d}" "${errf}"
  local n; n="$(gate_bytes "${root}" c1sig001)"
  local line; line="$(gate_terminal_line "${errf}")"
  local ok=1
  if [[ -n "${n}" && "${n}" -gt 0 ]] && ! grep -q 'terminal=no_work' <<<"${line}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── C2 — new untracked file matching LANE_WRITES in the lane worktree ──────────────
case_c2_untracked_new() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf
  root="$(new_repo)"; tid="c2-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/agent"
  printf 'brand new, never git add-ed\n' > "${wt}/agent/newmod.py"
  d="$(mktemp -d)"; errf="$(mktemp)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" c2sig001 "${wt}" "${d}" "${errf}" "agent/newmod.py"
  local n; n="$(gate_bytes "${root}" c2sig001)"
  local line; line="$(gate_terminal_line "${errf}")"
  local ok=1
  if [[ -n "${n}" && "${n}" -gt 0 ]] && ! grep -q 'terminal=no_work' <<<"${line}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── C3 — clean lane worktree (worker did nothing): must still be no_work/empty_diff ──
case_c3_clean_anti_rescue() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf
  root="$(new_repo)"; tid="c3-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d)"; errf="$(mktemp)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" c3sig001 "${wt}" "${d}" "${errf}"
  local line; line="$(gate_terminal_line "${errf}")"
  local ok=1
  if grep -q 'terminal=no_work' <<<"${line}" && grep -q 'cause=empty_diff' <<<"${line}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── C4 — lane dirty ONLY under docs/handoff/: exclusion set must still say no_work ──
case_c4_handoff_only_dirt() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf
  root="$(new_repo)"; tid="c4-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/docs/handoff/dispatch-c4sig001"
  printf 'stray handoff artifact\n' > "${wt}/docs/handoff/dispatch-c4sig001/scratch.md"
  d="$(mktemp -d)"; errf="$(mktemp)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" c4sig001 "${wt}" "${d}" "${errf}"
  local line; line="$(gate_terminal_line "${errf}")"
  local ok=1
  if grep -q 'terminal=no_work' <<<"${line}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── C5 — ARM-PRODUCES-NOTHING-02 positive twin: same clean lane as C3 but WITH an
#   arm-registered file naming the AUTHOR (sonnet). The probe MUST fire and produce
#   cause=arm_produced_nothing. C3 and C5 are a minimal pair — identical clean worktree,
#   identical absent stream, differing ONLY in the arm-registered file. ───────────────
case_c5_registered_arm_silent() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf
  root="$(new_repo)"; tid="c5-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  # ARM-PRODUCES-NOTHING-02: write the registration file the gate checks.
  # AUTHOR is sonnet (run_gate's 3rd positional).
  mkdir -p "${root}/docs/handoff/dispatch-c5sig001"
  printf 'arm=sonnet handle=PID=0 epoch=0\n' > "${root}/docs/handoff/dispatch-c5sig001/arm-registered"
  d="$(mktemp -d)"; errf="$(mktemp)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" c5sig001 "${wt}" "${d}" "${errf}"
  local line; line="$(gate_terminal_line "${errf}")"
  local ok=1
  if grep -q 'terminal=no_work' <<<"${line}" && grep -q 'cause=arm_produced_nothing' <<<"${line}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}
CASE_NAMES=(); CASE_RCS=()

run_case() { # <name> <fn>
  local name="$1" fn="$2"
  local rc
  "${fn}" "${TARGET}" >/dev/null 2>&1; rc=$?
  CASE_NAMES+=("${name}"); CASE_RCS+=("${rc}")
  if [[ ${rc} -eq 2 ]]; then
    log "SKIPPED-CANNOT-RUN: ${name}"
  elif [[ ${rc} -eq 0 ]]; then
    log "PASS ${name}"
  elif [[ "${PASS_LABEL}" == "pre-fix" ]] && [[ "${POST_RCS[${#CASE_NAMES[@]}-1]:-2}" == "0" ]]; then
    # pre-fix block: this case passed post-fix, so red here is evidence, not regression
    log "RED-AS-EXPECTED ${name}"
  else
    log "FAIL ${name}"
  fi
}

run_all_cases() {
  CASE_NAMES=(); CASE_RCS=()
  run_case "C1-tracked-mod"        case_c1_tracked_mod
  run_case "C2-untracked-new"      case_c2_untracked_new
  run_case "C3-clean-anti-rescue"  case_c3_clean_anti_rescue
  run_case "C4-handoff-only-dirt"  case_c4_handoff_only_dirt
  run_case "C5-registered-arm-silent" case_c5_registered_arm_silent
}

report_single_pass() {
  local p=0 f=0 s=0 errs=()
  local i
  for i in "${!CASE_RCS[@]}"; do
    case "${CASE_RCS[$i]}" in
      0) p=$((p+1)) ;;
      2) s=$((s+1)) ;;
      *) f=$((f+1)); errs+=("${CASE_NAMES[$i]}") ;;
    esac
  done
  echo ""
  echo "Results (single-pass against ${TARGET}): ${p} passed, ${f} failed, ${s} skipped"
  [[ ${f} -gt 0 ]] && printf -- 'FAIL: %s\n' "${errs[@]}"
  return "${f}"
}

if [[ "${1:-}" == "--pre-fix" ]]; then
  TARGET="${2:?scratchdir required}"
  PASS_LABEL="single"
  run_all_cases
  report_single_pass; frc=$?
  [[ ${frc} -gt 0 ]] && exit 1
  exit 0
fi

STAMP="$(mktemp "${TMPDIR}/leadv2-lds1-stamp.XXXXXX")"

TARGET="${SELF_DIR}"
PASS_LABEL="post-fix"
echo "=== pass 1/2: post-fix (live tree: ${TARGET}) ==="
run_all_cases
POST_NAMES=("${CASE_NAMES[@]}"); POST_RCS=("${CASE_RCS[@]}")
POST_FAIL_COUNT=0; POST_ERRORS=()
for i in "${!POST_RCS[@]}"; do
  [[ "${POST_RCS[$i]}" -ne 0 && "${POST_RCS[$i]}" -ne 2 ]] && { POST_FAIL_COUNT=$((POST_FAIL_COUNT+1)); POST_ERRORS+=("${POST_NAMES[$i]}"); }
done

RF_RED=0; RF_GREEN_PRE_FIX=0; RF_COULD_NOT_RUN_PRE=0; RF_TOTAL_POST_PASS=0
GREEN_PRE_FIX_NAMES=()
if [[ -n "${LEADV2_REPO}" ]]; then
  PREFIX_DIR="$(mktemp -d "${TMPDIR}/leadv2-lds1-prefix.XXXXXX")"
  git -C "${LEADV2_REPO}" archive HEAD plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
  PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
  if [[ -f "${PREFIX_SCRIPTS}/leadv2-dispatch-product-close.sh" ]]; then
    TARGET="${PREFIX_SCRIPTS}"
    PASS_LABEL="pre-fix"
    echo ""
    echo "=== pass 2/2: red-first pre-fix (git archive HEAD) — reds here are EVIDENCE ==="
    run_all_cases
    PRE_RCS=("${CASE_RCS[@]}")
    for i in "${!POST_RCS[@]}"; do
      [[ "${POST_RCS[$i]}" -eq 0 ]] || continue
      RF_TOTAL_POST_PASS=$((RF_TOTAL_POST_PASS+1))
      case "${PRE_RCS[$i]:-2}" in
        0) RF_GREEN_PRE_FIX=$((RF_GREEN_PRE_FIX+1)); GREEN_PRE_FIX_NAMES+=("${POST_NAMES[$i]}") ;;
        2) RF_COULD_NOT_RUN_PRE=$((RF_COULD_NOT_RUN_PRE+1)) ;;
        *) RF_RED=$((RF_RED+1)) ;;
      esac
    done
  else
    log "pre-fix reconstruction: dispatch-product-close.sh absent from HEAD archive -- red-first not runnable"
    RF_COULD_NOT_RUN_PRE=${#POST_RCS[@]}
  fi
  rm -rf "${PREFIX_DIR}"
fi

TRIPWIRE_HITS="$(
  find "${LEADV2_REPO}/plugins" -newer "${STAMP}" 2>/dev/null
  find "${ORIG_HOME}/.claude" -maxdepth 2 -newer "${STAMP}" \
    \! -path '*/.claude/cache/*' \
    \! -name '.claude.json' \
    \! -path '*/.claude/todos/*' \
    2>/dev/null
)"

echo ""
echo "Results (post-fix, live tree): $(( ${#POST_RCS[@]} - POST_FAIL_COUNT )) passed, ${POST_FAIL_COUNT} failed"
[[ ${POST_FAIL_COUNT} -gt 0 ]] && printf -- 'FAIL: %s\n' "${POST_ERRORS[@]}"
echo "red-first: ${RF_RED}/${RF_TOTAL_POST_PASS} post-fix-passing cases RED against pre-fix"
[[ ${RF_GREEN_PRE_FIX} -gt 0 ]] && printf -- 'GREEN-PRE-FIX (not evidence): %s\n' "${GREEN_PRE_FIX_NAMES[@]}"
echo "pre-fix-could-not-run: ${RF_COULD_NOT_RUN_PRE}"
if [[ -n "${TRIPWIRE_HITS}" ]]; then
  echo "TRIPWIRE: paths changed under \${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):"
  printf '%s\n' "${TRIPWIRE_HITS}"
fi
rm -f "${STAMP}"

[[ ${POST_FAIL_COUNT} -gt 0 ]] && exit 1
exit 0
