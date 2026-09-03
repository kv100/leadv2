#!/usr/bin/env bash
# test-scope-gate-orchestration-dirt.sh — SCOPE-GATE-ORCHESTRATION-DIRT-01.
#
# WHY THIS TEST EXISTS: pc_scope_diff refuses a lane as `unscoped_lane_work` when a
# dirty path is not in the declared write-set. On 2026-08-21 that refused two lanes
# whose deliverables were finished and correct, because the "undeclared" paths were
# written by the orchestration itself, not by the worker:
#   * list-form  -> docs/LEAD_V2_STATE.md + scripts/lib/__pycache__/*.pyc
#   * Door A r3b -> scripts/lib/__pycache__/pe_flag_scan.cpython-314.pyc
# docs/leadv2/ and docs/handoff/ were already excluded; these two were not.
#
# The regex is READ OUT OF THE LIVE SCRIPT rather than duplicated here, so the test
# cannot pass against a script whose filter has drifted. Each case runs against the
# committed (pre-fix) script and the working-tree (post-fix) script, and prints the
# machine marker the builder-selfcheck gate greps for.
#
# The asymmetry matters as much as the exclusion: a path the worker actually wrote
# and did not declare MUST still be refused. Case 5 is that direction, and it is the
# one that fails if someone later widens the filter into uselessness.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REL="lib/leadv2-lane-guard.sh"
LIVE_SCRIPT="${LEADV2_SCOPE_GATE_LIVE_SCRIPT:-${SCRIPT_DIR}/../${TARGET_REL}}"
CLOSE_SCRIPT="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scope-dirt.XXXXXX")"
trap 'rm -rf "${PREFIX_DIR}"' EXIT
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_SCRIPT="${PREFIX_DIR}/pre-${TARGET_REL}"
mkdir -p "$(dirname "${PRE_SCRIPT}")"
if [[ -n "${REPO}" ]]; then
  # N7 fix (review-r5.md): a bare "HEAD^" pre-image is only correct on the exact
  # commit that landed the guard fix -- the very next unrelated commit on this
  # lane makes HEAD^ == HEAD:TARGET_REL again (both post-fix), and the whole
  # GREEN-PRE-FIX/RED-PRE-FIX labelling below silently goes vacuous with no
  # signal that it did. Anchor instead to the parent of the LAST commit that
  # actually touched TARGET_REL, which stays correct no matter how many
  # unrelated commits land on top. An explicit override still wins, for
  # bisecting a one-commit repo or reproducing a specific historical pairing.
  #
  # H-4 (DISPATCH-PIN-CLUSTER-01 round 7): the "differs from live by definition"
  # claim this comment used to make was false -- round 6's LAST touching commit
  # (d45d792) turned out to be a comment-only edit, so its parent's content was
  # byte-identical to live, and every case (including both-sites-use-constant,
  # the one this file exists to catch) silently reported GREEN-PRE-FIX against a
  # pre-image that was actually the post-image. "Re-anchor to the merge base" is
  # not viable here -- TARGET_REL did not exist yet at this branch's merge base
  # (5d1a5d7), so `git show` for it fails there and PRE_SCRIPT falls back to
  # empty (every case then honestly reports could-not-run instead of a fabricated
  # verdict). The general fix, robust to WHICHEVER commit ends up as the anchor:
  # refuse to run at all when the resolved pre-image is byte-identical to live.
  _last_touch="$(git -C "${REPO}" log -1 --format=%H -- "plugins/leadv2/scripts/${TARGET_REL}" 2>/dev/null)"
  PRE_REF="${LEADV2_SCOPE_GATE_PRE_REF:-${_last_touch:+${_last_touch}^}}"
  PRE_REF="${PRE_REF:-HEAD^}"
  git -C "${REPO}" show "${PRE_REF}:plugins/leadv2/scripts/${TARGET_REL}" > "${PRE_SCRIPT}" 2>/dev/null || : > "${PRE_SCRIPT}"
fi
[[ -s "${PRE_SCRIPT}" ]] || PRE_SCRIPT=""
if [[ -n "${PRE_SCRIPT}" ]] && cmp -s "${PRE_SCRIPT}" "${LIVE_SCRIPT}"; then
  echo "[TEST] FAIL: resolved pre-image (${PRE_REF}) is byte-identical to ${LIVE_SCRIPT} -- the gate would compare the fix to itself; set LEADV2_SCOPE_GATE_PRE_REF to a real pre-fix commit" >&2
  exit 1
fi

# Extract the exclusion regex from the script's own single definition. Returns rc 2
# (cannot run) if the constant is absent or its shape changed, so a refactor is
# reported honestly instead of silently passing on a stale pattern.
#
# This reads the CONSTANT, not a filter line: the original version of this test read
# a `grep -vE '...'` line and picked the FIRST of the two porcelain sites, which was
# still the un-widened copy. It reported three real failures — the copies had already
# drifted — and that is exactly what pushed the fix from "widen one line" to "define
# the set once". Reading the constant makes the drift unrepresentable.
_extract_filter() { # <script> -> prints regex
  local s="$1"
  [[ -f "$s" ]] || return 2
  local line
  line="$(grep -m1 "^_PC_PORCELAIN_EXCLUDE_RE=" "$s" 2>/dev/null)"
  if [[ -n "${line}" ]]; then
    line="${line#*=\'}"
    line="${line%\'}"
    [[ -n "${line}" ]] || return 2
    printf '%s' "${line}"
    return 0
  fi
  # Pre-fix shape: no constant, an inline regex at each porcelain site. Falling back
  # to it is what makes the RED run REAL — without this the pre-fix pass returns
  # "cannot run" (rc 2) and the harness would credit an unrunnable case as a red,
  # inflating the falsification count with cases that were never actually exercised
  # against the old code.
  line="$(grep -m1 -A1 "status --porcelain --untracked-files=all" "$s" 2>/dev/null | grep -m1 "grep -vE '")"
  [[ -n "${line}" ]] || return 2
  line="${line#*grep -vE \'}"
  line="${line%%\'*}"
  [[ -n "${line}" ]] || return 2
  printf '%s' "${line}"
}

# Both porcelain call sites must reference the constant — never an inline regex. This
# is the guard that keeps a future edit from reintroducing a second copy.
# H-3 (DISPATCH-PIN-CLUSTER-01 round 7): restored the COUNTING form. A bare -Fq
# presence check (dropped at some earlier round) passes as soon as ONE site uses the
# constant, so a second site that still carries its own inline regex -- the exact
# 2026-08-21 divergence this test exists to catch -- goes undetected. Counting sites
# vs. constant-uses and requiring them equal (and >=2, so a single-site script still
# fails honestly rather than vacuously passing) is what makes the check load-bearing.
_both_sites_use_constant() { # <script>
  local s="$1" n_sites n_const
  [[ -f "$s" ]] || return 2
  n_sites="$(grep -c "status --porcelain --untracked-files=all" "$s" 2>/dev/null || printf 0)"
  n_const="$(grep -c 'grep -vE "\${_PC_PORCELAIN_EXCLUDE_RE}"' "$s" 2>/dev/null || printf 0)"
  [[ "${n_sites}" -ge 2 && "${n_const}" -eq "${n_sites}" ]] && return 0
  return 1
}

# CTX-COST-GUARDS-01: same drift guard for the SECOND filter stage
# (_pc_drop_bootstrap_dirt), which handles the plugin-bootstrap-symlink exclusion that
# a text-only regex cannot express (needs a filesystem [-L] check). Count of
# `| _pc_drop_bootstrap_dirt ` pipeline appends must equal the count of porcelain sites,
# same shape as _both_sites_use_constant above -- so the two-stage filter cannot drift
# the way the single-stage one did on 2026-08-21.
_bootstrap_filter_controls_runtime() { # <script>
  # Behavioural control: a symlink-only bootstrap lane must be clean.  This
  # fails when lv2_lane_dirty stops invoking _pc_drop_bootstrap_dirt, while a
  # match on the helper's own definition would keep passing.
  local s="$1" lane rc
  lane="$(_scratch_lane_setup)" || return 2
  _pc_source_lane_dirty_funcs "$s" || { rm -rf "${lane}"; return 2; }
  lv2_lane_dirty "${lane}" >/dev/null 2>&1; rc=$?
  rm -rf "${lane}"
  [[ ${rc} -eq 1 ]]
}

# Extracts _PC_PORCELAIN_EXCLUDE_RE, _PC_BOOTSTRAP_PREFIX_RE, _pc_drop_bootstrap_dirt
# and lv2_lane_dirty verbatim out of the live script and sources them into the caller's
# shell -- NOT the whole script, which is a top-level executor with no
# source-safe/functions-only guard. rc2 if the expected function boundaries are gone
# (reported honestly, same convention as _extract_filter above).
_pc_source_lane_dirty_funcs() { # <script>
  local s="$1"
  # Functions/vars defined via eval below are GLOBAL and persist across calls in this
  # process -- without this unset, a pre-fix run right after a post-fix run would keep
  # seeing the post-fix _pc_drop_bootstrap_dirt (run_case always runs PRE then LIVE, so
  # case N+1's PRE_SCRIPT pass silently inherits case N's LIVE_SCRIPT functions).
  unset -f _pc_drop_bootstrap_dirt lv2_lane_dirty 2>/dev/null
  unset _PC_BOOTSTRAP_PREFIX_RE 2>/dev/null
  [[ -f "$s" ]] || return 2
  source "$s" 2>/dev/null || return 2
  declare -F lv2_lane_dirty >/dev/null 2>&1 || return 2
  return 0
}

# Real-filesystem cases (8-11): the string harness above (_survives) cannot express
# `[ -L ]`, so these build an actual scratch git worktree.
_scratch_lane_setup() { # -> prints scratch dir path on stdout
  local dir target
  dir="$(mktemp -d "${TMPDIR:-/tmp}/scope-dirt-lane.XXXXXX")" || return 1
  ( cd "${dir}" && git init -q && git config user.email t@t.test && \
    git config user.name t && git commit -q --allow-empty -m init ) >/dev/null 2>&1 || return 1
  mkdir -p "${dir}/.claude/commands" || return 1
  target="$(mktemp "${TMPDIR:-/tmp}/scope-dirt-target.XXXXXX")" || return 1
  printf '' > "${target}"
  ln -s "${target}" "${dir}/.claude/commands/leadv2.md" || return 1
  printf '%s' "${dir}"
}

# 8: symlink-only bootstrap dirt -> lane must NOT be graded dirty (rc1).
case_bootstrap_symlink_only() { # <script>
  local s="$1" lane
  lane="$(_scratch_lane_setup)" || return 2
  _pc_source_lane_dirty_funcs "$s" || { rm -rf "${lane}"; return 2; }
  if lv2_lane_dirty "${lane}"; then rm -rf "${lane}"; return 1; fi
  rm -rf "${lane}"
  return 0
}

# 9: symlink bootstrap dirt PLUS a real undeclared file -> lane must still be graded
# dirty (rc0), and the survivor set must name the real file, not the symlink.
case_bootstrap_symlink_plus_real_file() { # <script>
  local s="$1" lane
  lane="$(_scratch_lane_setup)" || return 2
  _pc_source_lane_dirty_funcs "$s" || { rm -rf "${lane}"; return 2; }
  printf 'x' > "${lane}/undeclared.txt"
  if ! lv2_lane_dirty "${lane}"; then rm -rf "${lane}"; return 1; fi
  local survivors
  survivors="$(git -C "${lane}" status --porcelain --untracked-files=all 2>/dev/null | \
    grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "${lane}")"
  rm -rf "${lane}"
  printf '%s\n' "${survivors}" | grep -q 'undeclared.txt' || return 1
  printf '%s\n' "${survivors}" | grep -q 'commands/leadv2.md' && return 1
  return 0
}

# 10: a REAL regular file (not a symlink) at the bootstrap prefix -> the -L predicate
# must not be bypassed by prefix match alone; lane still graded dirty.
case_real_file_at_bootstrap_prefix() { # <script>
  local s="$1" lane
  lane="$(mktemp -d "${TMPDIR:-/tmp}/scope-dirt-lane.XXXXXX")" || return 2
  ( cd "${lane}" && git init -q && git config user.email t@t.test && \
    git config user.name t && git commit -q --allow-empty -m init ) >/dev/null 2>&1 || { rm -rf "${lane}"; return 2; }
  mkdir -p "${lane}/.claude/commands"
  printf 'real file, not a symlink' > "${lane}/.claude/commands/leadv2.md"
  _pc_source_lane_dirty_funcs "$s" || { rm -rf "${lane}"; return 2; }
  local rc=1
  lv2_lane_dirty "${lane}" && rc=0
  rm -rf "${lane}"
  [[ ${rc} -eq 0 ]] && return 0
  return 1
}

# 11: a TRACKED-modified path under a bootstrap prefix (the `??` predicate) -> must
# still count as dirty even though the prefix matches.
case_tracked_modified_at_bootstrap_prefix() { # <script>
  local s="$1" lane
  lane="$(mktemp -d "${TMPDIR:-/tmp}/scope-dirt-lane.XXXXXX")" || return 2
  ( cd "${lane}" && git init -q && git config user.email t@t.test && git config user.name t && \
    mkdir -p .claude/agents && printf 'orig' > .claude/agents/critic.md && \
    git add .claude/agents/critic.md && git commit -q -m init && \
    printf 'edited' > .claude/agents/critic.md ) >/dev/null 2>&1 || { rm -rf "${lane}"; return 2; }
  _pc_source_lane_dirty_funcs "$s" || { rm -rf "${lane}"; return 2; }
  local rc=1
  lv2_lane_dirty "${lane}" && rc=0
  rm -rf "${lane}"
  [[ ${rc} -eq 0 ]] && return 0
  return 1
}

# survives <script> <porcelain-line> -> 0 if the line PASSES the filter (i.e. it is
# still treated as candidate dirt), 1 if the filter drops it, 2 if unusable.
_survives() { # <script> <line>
  local s="$1" line="$2" re
  re="$(_extract_filter "$s")" || return 2
  [[ -n "${re}" ]] || return 2
  if printf '%s\n' "${line}" | grep -vE "${re}" | grep -q .; then
    return 0
  fi
  return 1
}

# 1-4: orchestration-owned paths must be DROPPED (filter excludes them).
case_state_file()    { _survives "$1" ' M docs/LEAD_V2_STATE.md'                             ; local r=$?; [[ $r -eq 2 ]] && return 2; [[ $r -eq 1 ]] && return 0; return 1; }
case_pycache_dir()   { _survives "$1" ' M scripts/lib/__pycache__/pe_flag_scan.cpython-314.pyc'; local r=$?; [[ $r -eq 2 ]] && return 2; [[ $r -eq 1 ]] && return 0; return 1; }
case_pyc_untracked() { _survives "$1" '?? scripts/pw/__pycache__/session.cpython-314.pyc'    ; local r=$?; [[ $r -eq 2 ]] && return 2; [[ $r -eq 1 ]] && return 0; return 1; }
case_handoff_still() { _survives "$1" ' M docs/handoff/.lifecycle-sync-last-run'             ; local r=$?; [[ $r -eq 2 ]] && return 2; [[ $r -eq 1 ]] && return 0; return 1; }

# 5: a real undeclared worker file must SURVIVE the filter -- the gate must still be
#    able to refuse genuine scope violations. This is the anti-overreach direction.
case_real_work_survives() { _survives "$1" ' M agent/post-cycle/run-all.sh'; }

# 6: a declared test file also survives the filter (declaredness is decided later, by
#    the write-set partition, not by this filter -- proving the filter is not doing
#    the write-set's job).
case_declared_survives() { _survives "$1" ' M tests/unit/test-post-form-instruction-flag.sh'; }

# 7: a path merely CONTAINING the word pycache, but not a __pycache__ dir or .pyc
#    file, must survive -- the exclusion must not be a loose substring match.
case_no_loose_match() { _survives "$1" ' M scripts/pycache-cleanup.sh'; }

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_SCRIPT}" ]]; then "${fn}" "${PRE_SCRIPT}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${LIVE_SCRIPT}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1)); FAIL=$((FAIL + 1)); ERRORS+=("${name}: could-not-run")
    log "FAIL: COULD-NOT-RUN: ${name} (post_rc=2)"; return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the pre-fix script too (pre_rc=0)"; return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n ${TARGET_REL}"
bash -n "${LIVE_SCRIPT}" || { log "FAIL: bash -n"; exit 1; }
# C-1 (DISPATCH-PIN-CLUSTER-01 round 7): the source line is no longer a bare
# one-liner -- it is guarded + canonical-fallback (SCRIPT_DIR copy first, else
# LEADV2_CANONICAL_ROOT) so a consumer-repo symlink farm with no lib/ copy of this
# new file does not error every dispatch entry point. An exact-line match on the old
# unguarded form would fail forever against the fix; assert the three load-bearing
# facts instead: it resolves the SCRIPT_DIR-local path, falls back to canonical root
# when that path is absent, and actually sources whichever one exists.
if grep -Fq '_LANE_GUARD_SH="${SCRIPT_DIR}/lib/leadv2-lane-guard.sh"' "${CLOSE_SCRIPT}" && \
   grep -Fq '${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-lane-guard.sh' "${CLOSE_SCRIPT}" && \
   grep -Fq 'source "${_LANE_GUARD_SH}"' "${CLOSE_SCRIPT}"; then
  log "PASS: product-close sources the lane guard with a consumer-repo-safe fallback"
else
  log "FAIL: product-close does not source the lane guard (or lost its fallback)"; exit 1
fi

run_case "state-file-excluded"       case_state_file
run_case "pycache-dir-excluded"      case_pycache_dir
run_case "pyc-untracked-excluded"    case_pyc_untracked
run_case "handoff-still-excluded"    case_handoff_still
run_case "real-work-still-refusable" case_real_work_survives
run_case "declared-file-survives"    case_declared_survives
run_case "no-loose-pycache-match"    case_no_loose_match
run_case "both-sites-use-constant"   _both_sites_use_constant
run_case "bootstrap-symlink-only-not-dirty"        case_bootstrap_symlink_only
run_case "bootstrap-symlink-plus-real-file-dirty"  case_bootstrap_symlink_plus_real_file
run_case "real-file-at-bootstrap-prefix-dirty"     case_real_file_at_bootstrap_prefix
run_case "tracked-modified-at-bootstrap-prefix-dirty" case_tracked_modified_at_bootstrap_prefix
run_case "bootstrap-filter-controls-runtime"        _bootstrap_filter_controls_runtime

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
