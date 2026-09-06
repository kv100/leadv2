#!/usr/bin/env bash
# test-judge-shaped-agent-guard.sh — LEAD-USES-ITS-OWN-TOOLS-01
#
# Subject: the REAL hooks/leadv2-judge-shaped-agent-guard.sh, fed the real
# PreToolUse JSON shape on stdin. Faked one level lower: a plugin root with
# (or without) the judge skill file.
#
# DECLARED NEGATIVE CONTROL (apply INSIDE the guard's body; must turn this
# suite RED): empty or invert the judge-shape regex
#   grep -qiE 'VERDICT:|round cap|roundcap|LAND or FIX-ROUND'  ->  grep -qiE 'ZZZ_NEVER'
# => case (a) fails: a judge-shaped prompt no longer warns.
# Case (b) -- ordinary prose must NEVER warn -- stays green under that same
# mutation, which is the point: a guard that warns on everything would pass (a)
# and be useless.
# Second declared mutation, in leadv2-review-run.sh's round-cap printf: drop
#   \nremedy: Skill(leadv2-judge) mode=review
# => case (f) fails. Case (g) -- the cap still exits 8 -- must stay green under
# it: the fix names a remedy, it does not soften the refusal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${LEADV2_JUDGE_GUARD_SH:-${SCRIPT_DIR}/../../hooks/leadv2-judge-shaped-agent-guard.sh}"
[[ -f "${GUARD}" ]] || { echo "FATAL: guard not found: ${GUARD}" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/judge-guard.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/plugin/skills/leadv2-judge"
printf '# leadv2-judge skill\n' > "${WORK}/plugin/skills/leadv2-judge/SKILL.md"

run() { # <plugin_root> <prompt> [env assignments...] -> stderr of the guard
  local root="$1" prompt="$2"; shift 2
  local json
  json="$(printf '%s' "${prompt}" | jq -Rs '{tool_name:"Agent",tool_input:{prompt:.}}')"
  printf '%s' "${json}" | env CLAUDE_PLUGIN_ROOT="${root}" "$@" bash "${GUARD}" 2>&1 >/dev/null
}

JUDGEY='Read the two review rounds and give a VERDICT: LAND or FIX-ROUND for this lane.'
PLAIN='Refactor the slot planner so the pillar proportions are computed once per cycle.'

echo "== the guard notices a judge-shaped Agent prompt"
OUT="$(run "${WORK}/plugin" "${JUDGEY}")"
if grep -q 'judge-shaped' <<< "${OUT}" && grep -q 'Skill(leadv2-judge) mode=review' <<< "${OUT}"; then
  ok "(a) judge-shaped prompt warns, and names the skill that already exists"
else
  bad "(a) no notice for a judge-shaped prompt (stderr='${OUT:0:80}')"
fi

# (b) the property that makes (a) worth having: ordinary work must be silent.
OUT="$(run "${WORK}/plugin" "${PLAIN}")"
if [[ -z "${OUT}" ]]; then
  ok "(b) NEG-CTL: an ordinary prompt is not warned about"
else
  bad "(b) NEG-CTL: guard warned on ordinary prose (stderr='${OUT:0:80}')"
fi

# (c) nothing to point at -> say nothing. The row's own premise died here: it
#     named leadv2-judge.sh, which has never existed.
mkdir -p "${WORK}/empty"
OUT="$(run "${WORK}/empty" "${JUDGEY}")"
if [[ -z "${OUT}" ]]; then
  ok "(c) no judge skill present -> silent, never points at a phantom tool"
else
  bad "(c) warned while the judge path does not exist"
fi

# (d) a notice, never a refusal: the exit status must stay 0 in every case.
printf '%s' "$(printf '%s' "${JUDGEY}" | jq -Rs '{tool_name:"Agent",tool_input:{prompt:.}}')" \
  | CLAUDE_PLUGIN_ROOT="${WORK}/plugin" bash "${GUARD}" >/dev/null 2>&1
rc=$?
if [[ ${rc} -eq 0 ]]; then ok "(d) warns without blocking (exit 0)"; else bad "(d) guard exited ${rc} — it must never deny"; fi

# (e) the kill switch works
OUT="$(run "${WORK}/plugin" "${JUDGEY}" LEADV2_JUDGE_SHAPED_GUARD=0)"
if [[ -z "${OUT}" ]]; then ok "(e) LEADV2_JUDGE_SHAPED_GUARD=0 silences it"; else bad "(e) kill switch ignored"; fi

# ── the other half of the row: the refusal must NAME the remedy ────────────
# This runs the REAL leadv2-review-run.sh against a seeded round-cap state, so
# it is the production path that writes review-gate.md, not a grep of the file.
REVIEW_RUN="${LEADV2_REVIEW_RUN_SH:-${SCRIPT_DIR}/../leadv2-review-run.sh}"
if [[ -f "${REVIEW_RUN}" ]]; then
  echo "== the round-cap refusal names the tool that already exists"
  H="${WORK}/handoff"; mkdir -p "${H}"
  printf 'attempts=9\nspawns=9\n' > "${H}/.review-round.state"
  : > "${H}/build-attempt-1.diff"
  ( cd "${WORK}" && LEADV2_REVIEW_MAX_ROUNDS=1 timeout 60 bash "${REVIEW_RUN}" \
      --task judge-guard-fixture --root "${WORK}" --handoff "${H}" \
      --diff "${H}/build-attempt-1.diff" --author fixture ) >/dev/null 2>&1
  rc=$?
  if grep -q '^reason: review_roundcap' "${H}/review-gate.md" 2>/dev/null; then
    if grep -q '^remedy: Skill(leadv2-judge) mode=review' "${H}/review-gate.md" 2>/dev/null; then
      ok "(f) review-gate.md names the remedy by name, not just 'escalate or PARK'"
    else
      bad "(f) blocked without naming the remedy: $(tr '\n' '|' < "${H}/review-gate.md" 2>/dev/null | cut -c1-90)"
    fi
    if [[ ${rc} -eq 8 ]]; then
      ok "(g) NEG-CTL: the cap still refuses (exit 8) — naming a remedy is not permission"
    else
      bad "(g) NEG-CTL: round cap no longer refuses (exit ${rc}, expected 8)"
    fi
  else
    echo "  skip — round-cap path not reached in this environment (no verdict written)"
  fi
fi

echo
echo "passed=${PASS} failed=${FAIL}"
[[ ${FAIL} -eq 0 ]]
