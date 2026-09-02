#!/usr/bin/env bash
# leadv2-think-model.sh — THE think-model resolver entry (FABLE-THINK-TIER-01).
# Every think-role spawn site (plan synthesis, judge/critic, architect prepass,
# diagnose root-cause, learn proposal, PO audit, lead main model) resolves its
# arm through this file. The policy itself lives in leadv2-router.sh
# think_model(): the model-capability.yaml kill switch is checked FIRST and
# always wins, even over an explicit LEADV2_THINK_MODEL env pin — the env
# only supplies the DEFAULT candidate, never an outright override; opus is
# used ONLY when the candidate is unavailable. That opus fallback lives in
# exactly ONE place — the router — never at a call site.
# Usage: think="$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh")"
set -uo pipefail
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="${LEADV2_TEST_ROUTER:-${LIB_DIR}/../leadv2-router.sh}"
exec bash "$ROUTER" think-model
