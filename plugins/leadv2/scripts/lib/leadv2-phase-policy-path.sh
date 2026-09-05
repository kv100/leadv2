#!/usr/bin/env bash
# leadv2-phase-policy-path.sh — resolve the PHASE-POLICY document.
#
# ROUTING-YAML-HAS-TWO-READERS-AND-TWO-FILES-01 (2026-09-05).
#
# Two different documents were sharing the filename leadv2-routing.yaml:
#
#   A  router registry        top-level `router_v2` + `router`
#      -> arms, capability_matrix, dispatch_ladder, active_account
#   B  phase policy           top-level `phases` `stop_rules` `downgrade_chain`
#                             `floor_rules` (+ phases.glm_policy.codex_quota_gate)
#
# They share ZERO top-level keys (measured 2026-09-05: the router registry parses
# to arms=7 ladder=9 cap_matrix=9 and NO phases; the phase policy to arms=0
# ladder=0 cap_matrix=0 and phases=8). Four readers -- leadv2-router.sh,
# leadv2-cost-estimate.sh, codex-task.sh and leadv2-router-v2.sh -- want document
# B, took the tenant path with no fallback, and got whichever document happened
# to live there. In the plugin's own repo that is document A, so they degraded to
# their own defaults SILENTLY. This resolver makes that impossible: it selects by
# the document's SHAPE, not by its filename, and every miss is loud.
#
# Resolution order (first hit wins):
#   1. $LEADV2_PHASE_POLICY_YAML          explicit override; must exist, else rc=1
#   2. $LEADV2_ROUTING_YAML               legacy override, honoured ONLY when it
#                                         carries document B (it also names
#                                         document A for other readers)
#   3. <root>/.claude/ref/leadv2-phase-policy.yaml       the current name
#   4. <root>/.claude/ref/leadv2-routing.yaml            the old name -- accepted,
#                                         with a deprecation line naming the new
#                                         path, and ONLY when it is document B
#   rc=1 and nothing on stdout otherwise. Callers must say so out loud; a caller
#   that quietly substitutes a default is the disease this file exists to end.

# Document-B shape test. Grep, not pyyaml: two of the four callers run in
# contexts where pyyaml is not guaranteed, and this only needs the top-level
# key names, which are anchored at column 0 in every real file.
_lv2_is_phase_policy_doc() {  # <file> -> rc 0 if document B
  local _f="${1:-}"
  [[ -n "${_f}" && -r "${_f}" ]] || return 1
  grep -qE '^(phases|stop_rules|floor_rules):' "${_f}" 2>/dev/null || return 1
  # A file that also declares router_v2 is document A (or a merge of the two,
  # which has never existed); refuse it rather than guess.
  ! grep -qE '^router_v2:' "${_f}" 2>/dev/null
}

_lv2_phase_policy_warn() {  # once per process, per message
  local _key="LV2_PP_WARNED_${2:-x}"
  [[ -n "${!_key:-}" ]] && return 0
  printf -v "${_key}" '1'; export "${_key?}"
  printf '[leadv2-phase-policy] %s\n' "$1" >&2
}

# leadv2_phase_policy_path <repo_root>
#   stdout: absolute path of the phase-policy document. rc=1 and empty when none.
leadv2_phase_policy_path() {
  local _root="${1:-${PROJECT_ROOT:-$PWD}}"
  local _new="${_root}/.claude/ref/leadv2-phase-policy.yaml"
  local _old="${_root}/.claude/ref/leadv2-routing.yaml"

  if [[ -n "${LEADV2_PHASE_POLICY_YAML:-}" ]]; then
    if [[ -r "${LEADV2_PHASE_POLICY_YAML}" ]]; then
      printf '%s' "${LEADV2_PHASE_POLICY_YAML}"; return 0
    fi
    _lv2_phase_policy_warn \
      "ERROR: LEADV2_PHASE_POLICY_YAML=${LEADV2_PHASE_POLICY_YAML} is not readable" env
    return 1
  fi

  # The legacy override names BOTH documents depending on the reader, so take it
  # only when it actually carries this one.
  if [[ -n "${LEADV2_ROUTING_YAML:-}" ]] && _lv2_is_phase_policy_doc "${LEADV2_ROUTING_YAML}"; then
    printf '%s' "${LEADV2_ROUTING_YAML}"; return 0
  fi

  if [[ -r "${_new}" ]]; then
    printf '%s' "${_new}"; return 0
  fi

  if _lv2_is_phase_policy_doc "${_old}"; then
    _lv2_phase_policy_warn \
      "DEPRECATED NAME: reading the phase policy from ${_old}. Rename it to ${_new} (ROUTING-YAML-HAS-TWO-READERS-AND-TWO-FILES-01); the old name is still read, for now." old
    printf '%s' "${_old}"; return 0
  fi

  # Loud on the way out, naming what was looked for and what was found instead.
  if [[ -e "${_old}" ]]; then
    _lv2_phase_policy_warn \
      "NOT FOUND: ${_new} does not exist and ${_old} is NOT the phase-policy document (it declares router_v2, i.e. it is the router registry). Nothing here carries phases/stop_rules/floor_rules." wrongdoc
  else
    _lv2_phase_policy_warn "NOT FOUND: neither ${_new} nor ${_old} exists." none
  fi
  return 1
}
