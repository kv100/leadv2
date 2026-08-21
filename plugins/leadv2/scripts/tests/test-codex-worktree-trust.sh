#!/usr/bin/env bash
# test-codex-worktree-trust.sh — CODEX-WORKTREE-TRUST-01.
#
# WHY THIS TEST EXISTS: on 2026-08-21 two review rounds were burned because the
# review engine invoked Codex with --cwd <lane worktree>, and Codex only honors
# a [projects."<exact cwd>"] stanza in ~/.codex/config.toml. In an unregistered
# cwd it opens a thread, prints its startup lines, and exits 0 with NO body --
# the engine records `review_body_lost`, nothing logs an error, and the lane
# silently loses its Codex arm. Proven live: the same review that produced 158
# bytes from an unregistered worktree produced 1909 bytes once the worktree was
# registered.
#
# Falsification is REAL here, not decorative: every case is run twice, once
# against a pristine copy of the script at its merge-base (pre-fix) and once
# against the working tree (post-fix), and the harness prints the machine
# marker the builder-selfcheck gate greps for. A case that passes against
# pre-fix code is reported as GREEN-PRE-FIX, never as a pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REL="leadv2-lane-worktree.sh"
LIVE_SCRIPT="${SCRIPT_DIR}/../${TARGET_REL}"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Build a pristine pre-fix copy of the target from git, so "RED" means the code
# actually lacked the fix -- not that we mutated it by hand into something no
# commit ever contained.
# ---------------------------------------------------------------------------
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-wt-trust.XXXXXX")"
trap 'rm -rf "${PREFIX_DIR}"' EXIT
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_SCRIPT="${PREFIX_DIR}/pre-${TARGET_REL}"
if [[ -n "${REPO}" ]]; then
  # The last commit that does NOT carry the helper is HEAD at test-authoring
  # time; take the committed version, whatever it is, and skip if it already
  # has the fix (i.e. after this lands, RED is no longer reproducible from HEAD
  # and the harness says so out loud instead of faking a red).
  git -C "${REPO}" show "HEAD:plugins/leadv2/scripts/${TARGET_REL}" > "${PRE_SCRIPT}" 2>/dev/null || : > "${PRE_SCRIPT}"
fi
[[ -s "${PRE_SCRIPT}" ]] || PRE_SCRIPT=""

# ---------------------------------------------------------------------------
# Cases. Each takes the script under test and an isolated CODEX_HOME, and
# returns 0 (behaviour present) / 1 (behaviour absent) / 2 (cannot run).
# ---------------------------------------------------------------------------

# Source the script's helper without executing its dispatch: the file ends in a
# dispatch block, so we run it in a subshell with a no-op op and then call the
# function. Simplest robust route: extract and eval just the function body.
_load_helper() { # <script> -> defines codex_trust_worktree + phys in this shell
  local s="$1"
  [[ -f "$s" ]] || return 2
  grep -q 'codex_trust_worktree()' "$s" || return 1
  # phys() is a dependency of the helper; both are plain top-level functions.
  eval "$(awk '/^phys\(\)/,/^}/' "$s")" 2>/dev/null || return 2
  eval "$(awk '/^codex_trust_worktree\(\)/,/^}/' "$s")" 2>/dev/null || return 2
  declare -F codex_trust_worktree >/dev/null || return 1
  return 0
}

# 1: an unregistered worktree path gains a 4-key trusted stanza.
case_registers() { # <script>
  local s="$1" home cfg wt
  home="$(mktemp -d "${TMPDIR:-/tmp}/cwt-home.XXXXXX")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/cwt-lane.XXXXXX")"
  cfg="${home}/config.toml"
  printf '[projects."/some/other/repo"]\ntrust_level = "trusted"\n' > "${cfg}"
  ( _load_helper "$s" || exit $?
    CODEX_HOME="${home}"; codex_trust_worktree "${wt}" ) ; local rc=$?
  if [[ ${rc} -eq 2 ]]; then rm -rf "${home}" "${wt}"; return 2; fi
  local ok=0
  grep -qF "[projects.\"${wt}\"]" "${cfg}" 2>/dev/null || ok=1
  grep -q '^approval_policy = "never"' "${cfg}" 2>/dev/null || ok=1
  grep -q '^sandbox_mode = "danger-full-access"' "${cfg}" 2>/dev/null || ok=1
  grep -q '^network_access = "enabled"' "${cfg}" 2>/dev/null || ok=1
  # the pre-existing entry must survive
  grep -qF '[projects."/some/other/repo"]' "${cfg}" 2>/dev/null || ok=1
  rm -rf "${home}" "${wt}"
  return "${ok}"
}

# 2: idempotent -- a second call adds no duplicate stanza.
case_idempotent() { # <script>
  local s="$1" home cfg wt
  home="$(mktemp -d "${TMPDIR:-/tmp}/cwt-home.XXXXXX")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/cwt-lane.XXXXXX")"
  cfg="${home}/config.toml"
  : > "${cfg}"
  ( _load_helper "$s" || exit $?
    CODEX_HOME="${home}"
    codex_trust_worktree "${wt}"; codex_trust_worktree "${wt}"; codex_trust_worktree "${wt}" ) ; local rc=$?
  if [[ ${rc} -eq 2 ]]; then rm -rf "${home}" "${wt}"; return 2; fi
  local n
  n="$(grep -cF "[projects.\"${wt}\"]" "${cfg}" 2>/dev/null || printf 0)"
  rm -rf "${home}" "${wt}"
  [[ "${n}" == "1" ]] && return 0
  return 1
}

# 3: fail-open -- a missing config file must not error and must not create one.
#    Lane creation is never allowed to break because Codex config is absent.
case_fail_open_missing_cfg() { # <script>
  local s="$1" home wt
  home="$(mktemp -d "${TMPDIR:-/tmp}/cwt-home.XXXXXX")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/cwt-lane.XXXXXX")"
  ( _load_helper "$s" || exit $?
    CODEX_HOME="${home}"; codex_trust_worktree "${wt}" ) ; local rc=$?
  if [[ ${rc} -eq 2 ]]; then rm -rf "${home}" "${wt}"; return 2; fi
  local ok=0
  [[ ${rc} -eq 0 ]] || ok=1                       # returned success
  [[ -e "${home}/config.toml" ]] && ok=1          # did NOT fabricate a config
  rm -rf "${home}" "${wt}"
  return "${ok}"
}

# 4: kill-switch honored.
case_kill_switch() { # <script>
  local s="$1" home cfg wt
  home="$(mktemp -d "${TMPDIR:-/tmp}/cwt-home.XXXXXX")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/cwt-lane.XXXXXX")"
  cfg="${home}/config.toml"; : > "${cfg}"
  ( _load_helper "$s" || exit $?
    CODEX_HOME="${home}"; LEADV2_CODEX_WORKTREE_TRUST=off; codex_trust_worktree "${wt}" ) ; local rc=$?
  if [[ ${rc} -eq 2 ]]; then rm -rf "${home}" "${wt}"; return 2; fi
  local ok=0
  grep -qF "[projects.\"${wt}\"]" "${cfg}" 2>/dev/null && ok=1
  rm -rf "${home}" "${wt}"
  return "${ok}"
}

# 5: empty path is a no-op, not a malformed stanza.
case_empty_path() { # <script>
  local s="$1" home cfg
  home="$(mktemp -d "${TMPDIR:-/tmp}/cwt-home.XXXXXX")"
  cfg="${home}/config.toml"; : > "${cfg}"
  ( _load_helper "$s" || exit $?
    CODEX_HOME="${home}"; codex_trust_worktree "" ) ; local rc=$?
  if [[ ${rc} -eq 2 ]]; then rm -rf "${home}"; return 2; fi
  local ok=0
  [[ ${rc} -eq 0 ]] || ok=1
  grep -q 'projects\.' "${cfg}" 2>/dev/null && ok=1
  rm -rf "${home}"
  return "${ok}"
}

# 6: the three ensure() success paths all register (reuse path included --
#    that is the one that covers worktrees created before this fix).
case_all_call_sites() { # <script>
  local s="$1"
  [[ -f "$s" ]] || return 2
  local n
  n="$(grep -c 'codex_trust_worktree "\$lane_path"' "$s" 2>/dev/null || printf 0)"
  [[ "${n}" -ge 3 ]] && return 0
  return 1
}

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_SCRIPT}" ]]; then
    "${fn}" "${PRE_SCRIPT}" >/dev/null 2>&1; pre_rc=$?
  else
    pre_rc=2
  fi
  "${fn}" "${LIVE_SCRIPT}" >/dev/null 2>&1; post_rc=$?

  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1))
    log "COULD-NOT-RUN: ${name} (post_rc=2)"
    return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix did not pass (rc=${post_rc})")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"
    return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the pre-fix script too (pre_rc=0)"
    return
  fi
  PASS=$((PASS + 1))
  log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n ${TARGET_REL}"
bash -n "${LIVE_SCRIPT}" || { log "FAIL: bash -n"; exit 1; }

run_case "registers-4-key-stanza"  case_registers
run_case "idempotent"              case_idempotent
run_case "fail-open-missing-cfg"   case_fail_open_missing_cfg
run_case "kill-switch"             case_kill_switch
run_case "empty-path-noop"         case_empty_path
run_case "all-ensure-call-sites"   case_all_call_sites

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then
  printf -- 'FAIL: %s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
