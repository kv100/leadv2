#!/usr/bin/env bash
# leadv2-review-signals.sh — compute the review-safety signals for the product-close
# review-pool resolver.
#
# ONE function, sourceable by both leadv2-dispatch-product-close.sh and the test harness.
# The close script is an executable with top-level side effects and cannot be sourced, so a
# one-function lib is the only way a test exercises the LIVE computation rather than a
# re-implementation -- which would make the test tautological.
#
#   leadv2_review_signals <routing_yaml> <writes_csv>
#     stdout: exactly one line of JSON -- the --signals payload for
#             leadv2-glm-policy-resolve.py:
#               {"protected_path": <bool>, "safety_touched": <bool>}
#     stderr: one line  signals_source=<token>   (for the caller to log)
#     globals set:
#       LEADV2_REVIEW_SIGNALS_SOURCE    = lane_writes | no_lane_writes_failclosed |
#                                         no_patterns_failclosed | lib_missing_failclosed
#       LEADV2_REVIEW_SIGNALS_PROTECTED = 1 | 0   (the protected_path bool, as 0/1 for logs)
#       LEADV2_REVIEW_SIGNALS_MATCHED   = <first-matching path> | "-"
#
# WHY THIS EXISTS (CODEX-GATE-01 item 6): resolve_review_pool_call() used to pass
# --signals '{}' hardcoded, so the resolver's kimi safety-exclusion branch
# (leadv2-glm-policy-resolve.py:332-335) was unreachable on the live review path -- a free
# (kimi) arm could review a safety-gate / publish / payments diff. The build path derives its
# safety signal from CLI flags a human types (--protected/--safety); that source is not data
# the close path can reuse, so per the mission's documented fallback we pattern-match the
# lane's own write paths against protected patterns declared in routing yaml.
#
# SIGNAL SEMANTICS -- fail-CLOSED (mirrors resolve_arm's resolver_missing_failclosed at
# leadv2-dispatch-code.sh:483): unknown scope and missing patterns must NEVER admit the free
# unproven review arm. The resolver excludes kimi when EITHER signal is true.
#   any lane-write path matches a pattern  -> protected=true  safety=true   (lane_writes)
#   lane writes present, none match        -> protected=false safety=false  (lane_writes)
#   WRITES_CSV empty/unset (scope unknown) -> protected=true  safety=true   (no_lane_writes_failclosed)
#   no patterns in any consulted yaml      -> protected=true  safety=true   (no_patterns_failclosed)
#
# PATTERNS are plain globs matched with bash `[[ == ]]` (so `*` spans `/` -- a pattern like
# `*safety*` matches `agent/foo/safety-gate.py`). NO regex. Declared in routing yaml under
# `router.glm_policy.protected_path_patterns` and looked up in this order -- the SAME
# co-located-then-canonical convention resolve_review_pool_call uses for the resolver binary:
#   1. the <routing_yaml> arg (tenant override: ${LEADV2_ROUTING_YAML:-.../.claude/ref/leadv2-routing.yaml})
#   2. ${LEADV2_CANONICAL_ROOT:-~/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml
# First yaml IN THIS ORDER that CONTAINS the key wins; the in-lane default is the safety net
# so a tenant override that lacks the key never silently fail-closes kimi review everywhere.

# Internal: print one protected_path_patterns entry per line from a yaml file (regex-only,
# no pyyaml dep -- mirrors leadv2-glm-policy-resolve.py's extract_glm_policy_block). Empty on
# any failure or absent key. Handles both block-list and inline-flow `[a, b]` forms.
_leadv2_review_signals_extract() {  # <yaml_file>
  [[ -n "${1:-}" && -f "${1}" ]] || return 0
  python3 - "$1" <<'PY' 2>/dev/null
import sys, re
try:
    txt = open(sys.argv[1]).read()
except Exception:
    sys.exit(0)
items = []
# block-list form:
#   protected_path_patterns:
#     - "*safety*"
m = re.search(r'(?m)^[ \t]*protected_path_patterns:[ \t]*\n((?:[ \t]+-[ \t].*\n)+)', txt)
if m:
    for im in re.finditer(r'(?m)^[ \t]*-[ \t]*"?([^"\n]+?)"?[ \t]*$', m.group(1)):
        items.append(im.group(1).strip())
else:
    # inline flow form: protected_path_patterns: ["*safety*", "*publish*"]
    m2 = re.search(r'(?m)^[ \t]*protected_path_patterns:[ \t]*\[([^\]]*)\]', txt)
    if m2:
        items = [s.strip().strip('"\'') for s in m2.group(1).split(',') if s.strip()]
for s in items:
    if s:
        print(s)
PY
}

leadv2_review_signals() {
  local routing_yaml="${1:-}" writes_csv="${2:-}"
  LEADV2_REVIEW_SIGNALS_SOURCE=""
  LEADV2_REVIEW_SIGNALS_PROTECTED="1"
  LEADV2_REVIEW_SIGNALS_MATCHED="-"

  local _canonical_default="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml"
  # Ordered lookup: first yaml that CARRIES the key wins.
  local _patterns=""
  _patterns="$(_leadv2_review_signals_extract "${routing_yaml}")"
  if [[ -z "${_patterns}" ]]; then
    _patterns="$(_leadv2_review_signals_extract "${_canonical_default}")"
  fi

  # No patterns anywhere -> fail-closed. Never admit the free arm on missing config.
  if [[ -z "${_patterns}" ]]; then
    LEADV2_REVIEW_SIGNALS_SOURCE="no_patterns_failclosed"
    LEADV2_REVIEW_SIGNALS_PROTECTED="1"
    LEADV2_REVIEW_SIGNALS_MATCHED="-"
    printf '{"protected_path":true,"safety_touched":true}\n'
    printf 'signals_source=no_patterns_failclosed\nsignals_matched=-\n' >&2
    return 0
  fi

  # Empty / unset lane writes -> scope unknown -> fail-closed.
  if [[ -z "${writes_csv}" ]]; then
    LEADV2_REVIEW_SIGNALS_SOURCE="no_lane_writes_failclosed"
    LEADV2_REVIEW_SIGNALS_PROTECTED="1"
    LEADV2_REVIEW_SIGNALS_MATCHED="-"
    printf '{"protected_path":true,"safety_touched":true}\n'
    printf 'signals_source=no_lane_writes_failclosed\nsignals_matched=-\n' >&2
    return 0
  fi

  # Match each lane-write path against every pattern (bash glob; `*` spans `/`).
  local _matched=""
  local _oldifs="${IFS:-}"
  IFS=','
  local _path _pat
  for _path in ${writes_csv}; do
    [[ -z "${_path}" ]] && continue
    while IFS= read -r _pat; do
      [[ -z "${_pat}" ]] && continue
      # shellcheck disable=SC2053  # glob, not regex -- unquoted pattern is intentional
      if [[ "${_path}" == ${_pat} ]]; then
        _matched="${_path}"
        break
      fi
    done <<< "${_patterns}"
    [[ -n "${_matched}" ]] && break
  done
  IFS="${_oldifs}"

  if [[ -n "${_matched}" ]]; then
    LEADV2_REVIEW_SIGNALS_SOURCE="lane_writes"
    LEADV2_REVIEW_SIGNALS_PROTECTED="1"
    LEADV2_REVIEW_SIGNALS_MATCHED="${_matched}"
    printf '{"protected_path":true,"safety_touched":true}\n'
    printf 'signals_source=lane_writes\nsignals_matched=%s\n' "${_matched}" >&2
    return 0
  fi

  LEADV2_REVIEW_SIGNALS_SOURCE="lane_writes"
  LEADV2_REVIEW_SIGNALS_PROTECTED="0"
  LEADV2_REVIEW_SIGNALS_MATCHED="-"
  printf '{"protected_path":false,"safety_touched":false}\n'
  printf 'signals_source=lane_writes\nsignals_matched=-\n' >&2
  return 0
}
