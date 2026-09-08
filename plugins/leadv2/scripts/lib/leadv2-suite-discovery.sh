#!/usr/bin/env bash
# plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh — C5, GATE-DISCOVERS-246-UNTRACKED-SUITES-01
#
# Tracked-admission contract for suite discovery: a suite runs only if
# something tracked admits it — never because it happens to sit under a
# scanned directory. Measured 2026-09-08 (lead) and re-measured 2026-09-09
# (this lane, main checkout): .claude/scripts/tests holds 246 test-*.sh
# absent from git ls-files, zero of them carrying a '# run-all-triggers:'
# header — invisible to --scope changed selection, fully visible to the
# --scope all four-root find: a full sweep executes 246 suites no commit
# owns, no reviewer sees, and no header ever admitted.
#
# This lib is the single admission decision both discovery sites share:
#   - tests/run-all.sh --scope all selection (the execution vector; 246)
#   - scan_suite_triggers' header walk (a header planted on an untracked
#     file would otherwise inject trigger rows and reach execution via
#     --scope changed — dormant today, a live contract hole)
# tests/run-all.sh deliberately sources nothing from the plugin tree (it
# must run standalone in scratch fixture repos), so this lib is invoked as
# a subprocess; the wiring line belongs to the caller (B2 owns that file).
#
# Admission = the file is known to git in ROOT: staged or committed
# (git ls-files --error-unmatch). A never-added file is refused. Staging is
# the author's explicit "admit this" act, so a brand-new suite runs under
# discovery the moment it is git-added — the authoring loop (run it
# directly) never needed discovery in the first place.
#
# Refusal is loud and counted, never a silent narrowing:
#   names mode (default) — one [UNTRACKED-SKIP] line per refused file, by
#     name, then a count summary: the nightly full sweep is where a human
#     reads the whole list.
#   count mode — a single count line, for call sites that run on EVERY
#     invocation (the trigger scan): proportional signal, still visible.
#
# usage: leadv2-suite-discovery.sh --root <ROOT> [--dir <DIR>]... [--skip-report=names|count]
# stdout: admitted absolute test-*.sh paths, one per line, sorted per dir
# stderr: the skip report (mode above)
# exit 0: list printed; exit 2 named refusal (bad_usage / not_a_git_work_tree /
#         git_hard_failure) — an unproven or partial list is never printed
#         as if it were an answer.
#
# Portable: bash 3.2 (no assoc arrays, no ${var,,}); POSIX find/sort only.
# bash-guard: allow
set -uo pipefail

# Admission decision. rc 0 = admitted (tracked/staged), rc 1 = refused,
# rc 2 = git itself failed (the caller must fail loudly — never fall back
# to a raw find, which is exactly the bug this lib exists to close).
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the marked lines INSIDE this function body
# (never at top level). Both must turn
# plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh red:
#   c5-mut-1 (gate disabled — untracked executes again):
#     's|1) return 1 ;;  # c5-mut-1: untracked -> refused.*|1) return 0 ;;|'
#     -> case 1 red: the planted poison suite runs (marker present, rc=1).
#   c5-mut-2 (refuse everything — the green-that-runs-nothing):
#     's|0) return 0 ;;  # c5-mut-2: tracked -> admitted.*|0) return 1 ;;|'
#     -> cases 2/3 red: zero [SELECT]/[RUN] rows, tracked trigger rows gone.
leadv2_suite_is_admitted() { # <root> <abs-file> -> 0 admitted | 1 refused | 2 git failed
  local _root="$1" _f="$2" _rel="" _rc=0
  # Outside ROOT is not admitted — the same containment rule add_suite
  # applies downstream; refusing here keeps the contract in one place.
  case "${_f}" in
    "${_root}/"*) _rel="${_f#"${_root}/"}" ;;
    *) return 1 ;;
  esac
  # --error-unmatch: rc 1 = path not in the index (never staged, never
  # committed) = untracked = refused; rc >= 2 = git broke, not a verdict.
  git -C "${_root}" ls-files --error-unmatch -- "${_rel}" >/dev/null 2>&1
  _rc=$?
  case "${_rc}" in
    0) return 0 ;;  # c5-mut-2: tracked -> admitted
    1) return 1 ;;  # c5-mut-1: untracked -> refused
    *) return 2 ;;
  esac
}

# Scan accumulators (globals): rel paths of refused files, their count, and
# files git itself could not answer for (hard failure -> exit 2 upstream).
_C5_SKIPPED=""
_C5_SKIPPED_N=0
_C5_UNANSWERED=""

# One scanned directory. Prints its admitted test-*.sh (sorted — the same
# `find | sort` order run-all applied, so selection order never moves) to
# stdout; refused files accumulate for the report. Missing dir = skip
# silently, mirroring the `[[ -d ... ]] || continue` the old scan had.
leadv2_suite_discovery_scan() { # <root> <dir>
  local _root="$1" _dir="$2" _f="" _arc=0
  [[ -d "${_dir}" ]] || return 0
  while IFS= read -r _f; do
    [[ -n "${_f}" ]] || continue
    leadv2_suite_is_admitted "${_root}" "${_f}"
    _arc=$?
    case "${_arc}" in
      0) printf '%s\n' "${_f}" ;;
      1) _C5_SKIPPED="${_C5_SKIPPED}${_f#"${_root}/"}
"
         _C5_SKIPPED_N=$((_C5_SKIPPED_N + 1)) ;;
      *) _C5_UNANSWERED="${_C5_UNANSWERED}${_f#"${_root}/"}
" ;;
    esac
  done < <(find "${_dir}" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort)
}
# bash-guard: allow

# The loud, counted refusal. names mode: one line per refused file BY NAME
# (the whole point — "246 skipped" begs "which ones"), then the count.
# count mode: one count line, for every-invocation call sites.
leadv2_suite_discovery_report() { # <mode: names|count>
  local _mode="$1" _rel=""
  [[ ${_C5_SKIPPED_N} -gt 0 ]] || return 0
  if [[ "${_mode}" == "names" ]]; then
    while IFS= read -r _rel; do
      [[ -n "${_rel}" ]] || continue
      printf 'suite-discovery: [UNTRACKED-SKIP] %s — not tracked by git, nothing admits it, refusing to execute\n' "${_rel}" >&2
    done <<< "${_C5_SKIPPED}"
  fi
  printf 'suite-discovery: [UNTRACKED-SKIP] %d suite file(s) refused: not tracked by git (stage or commit to admit; run directly while authoring) — GATE-DISCOVERS-246-UNTRACKED-SUITES-01\n' "${_C5_SKIPPED_N}" >&2
}

leadv2_suite_discovery_main() {
  local _root="" _mode="names" _dirs=() _d=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) _root="${2:-}"; [[ -n "${_root}" ]] || { echo "suite-discovery: FATAL bad_usage --root needs a value" >&2; return 2; }; shift 2 ;;
      --dir)  _dirs+=("${2:-}"); [[ -n "${_dirs[${#_dirs[@]}-1]}" ]] || { echo "suite-discovery: FATAL bad_usage --dir needs a value" >&2; return 2; }; shift 2 ;;
      --skip-report=*) _mode="${1#--skip-report=}"; shift ;;
      -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | grep '^#' | head -25; return 0 ;;
      *) echo "suite-discovery: FATAL bad_usage unknown argument: $1" >&2; return 2 ;;
    esac
  done
  [[ -n "${_root}" ]] || { echo "suite-discovery: FATAL bad_usage --root is required" >&2; return 2; }
  case "${_mode}" in names|count) ;; *) echo "suite-discovery: FATAL bad_usage --skip-report must be names|count (got '${_mode}')" >&2; return 2 ;; esac
  # ROOT must be a git work tree: the admission answer is only provable
  # against git. run-all already FATALs on root_escape before discovery, so
  # this fires only on direct misuse — loudly, exit 2, never a guess.
  if ! git -C "${_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "suite-discovery: FATAL not_a_git_work_tree root=${_root} — cannot prove admission, refusing rather than listing unproven files" >&2
    return 2
  fi
  # Default: the four canonical suite roots, in run-all's own order.
  if [[ -z "${_dirs[@]+x}" ]]; then
    _dirs=("${_root}/plugins/leadv2/scripts/tests" \
           "${_root}/.claude/scripts/tests" \
           "${_root}/plugins/leadv2/tests" \
           "${_root}/tests")
  fi
  for _d in ${_dirs[@]+"${_dirs[@]}"}; do
    leadv2_suite_discovery_scan "${_root}" "${_d}"
  done
  if [[ -n "${_C5_UNANSWERED}" ]]; then
    # git failed on these files: an unanswered file is not admitted, and a
    # list with holes in it is not an answer — named exit 2.
    printf 'suite-discovery: FATAL git_hard_failure — git could not answer for:\n%s' "${_C5_UNANSWERED}" >&2
    return 2
  fi
  leadv2_suite_discovery_report "${_mode}"
  return 0
}

# Executed (subprocess — run-all wiring invokes `bash <this> --root ...`).
# Sourced use is allowed: functions above carry no main side effects.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  leadv2_suite_discovery_main "$@"
  exit $?
fi
# bash-guard: allow
