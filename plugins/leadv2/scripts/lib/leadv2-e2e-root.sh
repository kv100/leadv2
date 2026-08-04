#!/usr/bin/env bash
# leadv2-e2e-root.sh — shared e2e root validation (GATE-WRONG-ROOT-FALSE-DEAD-01)
#
# Sourced by both e2e gate callers (leadv2-dispatch-product-close.sh,
# leadv2-phase8-e2e-gate.sh) so there is ONE validation mechanism, not two.
# Provides:
#   _lv2_realpath() — portable realpath via python3 (no readlink -f on macOS)
#   _lv2_e2e_resolve_root() — validates a candidate e2e root against a ref root
#
# This file is sourced, not executed. No set -e/uo here — the caller owns that.

_lv2_realpath() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }

# Validates <candidate> as an e2e root that lives in the same repo as <ref_root>.
# On success: sets _lv2_e2e_root=<candidate>, returns 0.
# On failure: sets _lv2_e2e_root_reason=<named>, returns 1.
# Named reasons: e2e_root_missing, e2e_root_not_toplevel, e2e_root_foreign_repo,
#                e2e_root_escaped.
_lv2_e2e_resolve_root() {  # <candidate> <ref_root>
  local r="${1:?candidate root required}" ref="${2:?ref root required}"
  local real_r real_ref tl real_tl real_common_r real_common_ref
  _lv2_e2e_root="" _lv2_e2e_root_reason=""
  [[ -d "${r}" ]] || { _lv2_e2e_root_reason="e2e_root_missing"; return 1; }
  # R7: compare physical paths — candidate may be a logical path through a symlink.
  real_r="$(_lv2_realpath "${r}")"
  real_ref="$(_lv2_realpath "${ref}")"
  tl="$(git -C "${r}" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${tl}" ]] || { _lv2_e2e_root_reason="e2e_root_not_toplevel"; return 1; }
  [[ "$(_lv2_realpath "${tl}")" == "${real_r}" ]] || { _lv2_e2e_root_reason="e2e_root_not_toplevel"; return 1; }
  # Same-repo guard: the candidate's git common-dir must match ref_root's.
  # NOTE: `git rev-parse --git-common-dir` may return a RELATIVE path (.git)
  # from the main repo — resolve it from WITHIN the repo directory so
  # os.path.realpath sees the right base, not the caller's CWD.
  local common_r common_ref
  common_r="$(cd "${r}"   && git rev-parse --git-common-dir 2>/dev/null || true)"
  common_ref="$(cd "${ref}" && git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "${common_r}" && -n "${common_ref}" ]] || { _lv2_e2e_root_reason="e2e_root_not_toplevel"; return 1; }
  real_common_r="$(cd "${r}"   && _lv2_realpath "${common_r}")"
  real_common_ref="$(cd "${ref}" && _lv2_realpath "${common_ref}")"
  [[ "${real_common_r}" == "${real_common_ref}" ]] || { _lv2_e2e_root_reason="e2e_root_foreign_repo"; return 1; }
  # Escape guard: ref must not be inside candidate (candidate pointed at ~/Projects
  # would pass the toplevel check for ~/Projects, but ref would be inside it — W2).
  case "${real_ref}" in
    "${real_r}/"*) _lv2_e2e_root_reason="e2e_root_escaped"; return 1 ;;
  esac
  _lv2_e2e_root="${r}"
  return 0
}
