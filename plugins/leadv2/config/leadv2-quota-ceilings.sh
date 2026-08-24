#!/usr/bin/env bash
# leadv2-quota-ceilings.sh — QUOTA-GATE-PARITY-01: the one editable place for the
# six declared per-provider/per-purpose quota ceilings. Sourced (not executed) by
# leadv2-provider-quota-gate.sh and leadv2-glm-quota-gate.sh.
#
# Values copied verbatim from plugins/leadv2/config/leadv2-routing.yaml
# router_v2.quota_ceilings (glm 80/90, codex 90/95, claude 95/95) — this file does
# NOT replace that yaml as the declared source of truth; it is the shell-readable
# mirror the two bash gates need (neither guarantees PyYAML).
#
# KNOWN DIVERGENCE (deliberately not fixed here, see architect prepass §0):
# lib/leadv2-glm-policy-resolve.py's DEFAULT_BUILD_THRESHOLD_PCT enforces codex
# BUILD at 80.0, not the 90 declared here/in the routing yaml. That is STRICTER
# than declared, so it is not a safety hole — it is left alone per the mission's
# "do NOT change the values" constraint. tests/test-provider-quota-gate.sh asserts
# this exact exception by name so it cannot silently widen.
#
# leadv2_quota_ceiling <glm|codex|claude> <build|review>
#   Echoes the integer ceiling on stdout, rc 0. On an unknown provider/purpose,
#   echoes nothing and returns rc 1 (caller must treat that as fail-open, never
#   as a literal 0 ceiling).

LEADV2_CEIL_GLM_WORK="${LEADV2_CEIL_GLM_WORK:-80}"
LEADV2_CEIL_GLM_REVIEW="${LEADV2_CEIL_GLM_REVIEW:-90}"
LEADV2_CEIL_CODEX_WORK="${LEADV2_CEIL_CODEX_WORK:-90}"
LEADV2_CEIL_CODEX_REVIEW="${LEADV2_CEIL_CODEX_REVIEW:-95}"
LEADV2_CEIL_CLAUDE_WORK="${LEADV2_CEIL_CLAUDE_WORK:-95}"
LEADV2_CEIL_CLAUDE_REVIEW="${LEADV2_CEIL_CLAUDE_REVIEW:-95}"

leadv2_quota_ceiling() {
  local provider="${1:-}" purpose="${2:-}"
  case "${provider}:${purpose}" in
    glm:build)     printf '%s\n' "${LEADV2_CEIL_GLM_WORK}" ;;
    glm:review)    printf '%s\n' "${LEADV2_CEIL_GLM_REVIEW}" ;;
    codex:build)   printf '%s\n' "${LEADV2_CEIL_CODEX_WORK}" ;;
    codex:review)  printf '%s\n' "${LEADV2_CEIL_CODEX_REVIEW}" ;;
    claude:build)  printf '%s\n' "${LEADV2_CEIL_CLAUDE_WORK}" ;;
    claude:review) printf '%s\n' "${LEADV2_CEIL_CLAUDE_REVIEW}" ;;
    *) return 1 ;;
  esac
}
