# LEAD-USES-ITS-OWN-TOOLS-01 — the lead hand-rolls work the plugin already implements

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead.

## What was measured (and what was thrown away)
Three independent censuses were run. Two produced unusable output and are recorded here so nobody
repeats them:
- A code-reachability agent declared 25 hooks ORPHAN because it only looked in `hooks.json`. FALSE:
  hooks are also wired as a name+predicate table inside `hooks/leadv2-bash-pre-dispatch.sh`, and one of
  its "orphans" (`leadv2-block-bash-heredoc.sh`) blocked two of the lead's own commands the same hour.
- A log-usage agent reported counts like "leadv2-shared: 348,061 invocations". Those are string
  occurrences in files, not invocations, and its zero-list contained names that do not exist.

What survived, measured by the lead directly over 400 session transcripts modified in the last 30 days
(`xargs grep -oh '<name>.sh' < <file-list>` — note BSD xargs has no `-a`):

| entry point | mentions / 30d |
|---|---|
| leadv2-judge.sh | **0** |
| leadv2-inbox.sh | 4 |
| leadv2-event.sh | 15 |
| leadv2-session-runner.sh | 46 |
| leadv2-lanes-snapshot.sh | 75 |
| leadv2-lanes.sh | 166 |
| leadv2-suite-falsifiable.sh | 218 |
| leadv2-phase-record.sh | 263 |
| leadv2-status.sh | 316 |

Inventory for scale: 245 top-level scripts, 43 skills, 37 hooks, 8 workflows, 2 commands; ~23 of the
scripts are lead-facing entry points, the rest are helpers called by other scripts.

## The defect
`leadv2-judge.sh` — the plugin's own unified Opus judge for round-cap decisions — has not been invoked
once in 30 days. On 2026-09-02 the lead hit the review round cap twice (FABLE-THINK-TIER-01,
BRAIN-CLASS-LIVE-01) and both times hand-wrote a ~400-word `Agent(leadv2:critic, opus)` prompt instead.
Cause: `commands/leadv2.md` names the capability only as `Skill(leadv2-judge) mode=review`, so the lead
reaches for an agent; nothing points at the script, and nothing detects that the lead is re-implementing
it. Same shape, lower severity, for `leadv2-lanes.sh` / `leadv2-status.sh`: the lead composed founder
status tables by hand five times today.

## Required
1. `review-run.sh`, when it writes `status: blocked reason=review_roundcap`, must print the exact
   `leadv2-judge.sh` invocation for that lane (remedy line, like the phase-precondition refusal does).
2. `commands/leadv2.md` Phase-5 row: name the SCRIPT, not only the skill.
3. A guard that catches the pattern: a lead `Agent(...)` spawn whose prompt contains judge-shaped text
   (`VERDICT:`, `round cap`, `LAND or FIX-ROUND`) while `leadv2-judge.sh` exists → warn with the command.
4. Re-run the entry-point census for all ~23 entry points with the transcript method above, and for each
   true zero decide: wire it, document it, or delete it. A capability nobody can reach is dead weight
   that still has to be maintained.

## Done when
- the round-cap refusal carries a runnable remedy; the census table for all entry points is in this
  handoff with a decision per zero; the guard's suite has a negative control.
