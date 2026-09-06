#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent) — LEAD-USES-ITS-OWN-TOOLS-01.
#
# THE GAP THIS CLOSES: when leadv2-review-run.sh refuses a further round
# (status: blocked, reason: review_roundcap), the lead needs a judge. The
# plugin HAS one -- the `leadv2-judge` skill, mode=review -- and on 2026-09-02
# the lead hit the cap twice (FABLE-THINK-TIER-01, BRAIN-CLASS-LIVE-01) and
# both times hand-wrote a ~400-word Agent(leadv2:critic, opus) prompt instead.
# Hand-rolling loses what the skill carries: a fixed verdict vocabulary, the
# mode contract, and a record. Nothing structural noticed.
#
# NOTE ON THE ROW'S OWN PREMISE (measured 2026-09-06): the filed row blames a
# script `leadv2-judge.sh` with "0 mentions in 30 days". That file has never
# existed in this repo's history -- `git log --all -- '**/leadv2-judge.sh'` is
# empty -- so the zero counted a name, not a disuse. The capability is a SKILL.
# This guard therefore points at `Skill(leadv2-judge) mode=review`, the thing
# that actually exists.
#
# Behaviour: WARN, never deny. A judge-shaped prompt is not wrong -- there are
# real reasons to spawn one (the skill is unavailable, a different question).
# Exit is always 0; this hook can only ever add a line of stderr.
set -uo pipefail
trap 'exit 0' ERR

[[ "${LEADV2_JUDGE_SHAPED_GUARD:-1}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "${INPUT}" ]] || exit 0

# The judge path must actually exist, or there is nothing to point at.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
JUDGE_SKILL="${PLUGIN_ROOT}/skills/leadv2-judge/SKILL.md"
[[ -f "${JUDGE_SKILL}" ]] || exit 0

PROMPT="$(printf '%s' "${INPUT}" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)"
[[ -n "${PROMPT}" ]] || exit 0

# Judge-shaped: the vocabulary the judge skill owns. Kept deliberately narrow --
# a prompt merely mentioning "review" is not judge-shaped.
if ! printf '%s' "${PROMPT}" | grep -qiE 'VERDICT:|round cap|roundcap|LAND or FIX-ROUND'; then
  exit 0
fi

cat >&2 <<MSG
[leadv2-judge-shaped-agent-guard] NOTICE — this Agent prompt is judge-shaped.
The plugin already implements this: \`Skill(leadv2-judge) mode=review\`
(${JUDGE_SKILL#"${PLUGIN_ROOT}/"}). It carries the verdict vocabulary and the
mode contract; a hand-written prompt carries neither and leaves no record.
Spawn this agent anyway if the skill genuinely does not fit -- this is a notice,
not a refusal. Silence it for a session with LEADV2_JUDGE_SHAPED_GUARD=0.
MSG
exit 0
