# NATIVE-CODEX-ORCHESTRATION-01-R1

Adapt leadv2 from a Claude-shaped Codex wrapper to a true Codex-root workflow.
Keep external dispatcher/worktrees as the only write-worker path; document native
agents as bounded read-heavy exploration, test triage and independent review.

Required changes:

1. Root skill: describe native `spawn_agent(fork_turns)`, `followup_task`,
   `send_message`, `wait_agent`, `interrupt_agent`, and `list_agents`. State that
   `codex fork` branches the founder chat and is not worker dispatch. Prefer
   `fork_turns: none` for isolated scans and `all` only when task context is
   necessary.
2. Root skill/runbook: remove fixed WIP=1. Compute capacity from available slots,
   provider health, dependencies and overlapping write sets. Independent
   non-writing work may run concurrently.
3. Runbook: make the lead profile Terra/high, not Sol/xhigh.
4. Personal source-command skill: remove the assumption that Codex is a child of
   Claude/Opus; make it a headless single-task lead under an optional supervising
   parent of any type.
5. Status skill: include native agent state and the native plan, and render only a
   compact `IN PROGRESS` / `NEXT` founder view alongside external lanes.
6. Add or update bounded tests that assert these contracts and reject the old
   fixed-WIP/Claude-child wording.

Do not change dispatcher, review engine or hook files. Preserve existing user
changes. Run focused tests, commit the bounded lane, and leave it clean.

acceptance:
  surface: codex_native_orchestration
  observable: Root, status, runbook and source-command contracts use native Codex agent semantics, Terra/high and dynamic WIP, with focused tests passing.
  authored_at: 2026-08-24T21:20:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2/SKILL.md,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2-status/SKILL.md,plugins/leadv2/codex-skills/source-command-leadv2/SKILL.md,plugins/leadv2/codex-lead/codex-lead-pilot-runbook.md,plugins/leadv2/codex-lead/tests

