# Native Codex gap audit

## Findings

- `codex fork` branches an interactive founder chat; it is not worker dispatch.
- Native workers use `spawn_agent` with `fork_turns`; subsequent fixes use
  `followup_task`, live guidance uses `send_message`, status uses `list_agents`,
  and cancellation uses `interrupt_agent`.
- The plugin currently routes Codex workers and reviewers through
  `codex-companion`, while its root/status skills do not describe native agents.
- The personal `source-command-leadv2` skill incorrectly treats Codex as a child
  of a Claude lead.
- Review defaults multiply calls: fanout 3, always-on Haiku hack detection, and a
  verifier per High/Critical finding. Reused handoff state also turns a new diff
  into another review round.
- The PreToolUse hook only understands `tool_input.command`; it misses
  `apply_patch`, MCP writes and Agent tools, and can false-positive on read-only
  commands containing forbidden text as search data.
- Status omits native agents and the native plan. The runbook still hard-codes
  WIP=1 and Sol/xhigh instead of Terra/high with collision/quota-based capacity.

## Decisions

1. Native Codex agents handle bounded read-heavy exploration, triage and review.
   External dispatcher/worktrees remain the write path and the Claude/GLM path.
2. Default review is machine checks plus one independent reviewer. A second
   reviewer is only for protected/high-risk changes. One exhaustive pass is
   followed, if needed, by one targeted recheck of changed High blockers.
3. Root profile is Terra/high. WIP is dynamic from available slots, provider
   health, dependency order and write-set collisions; it is never fixed at one.
4. Hooks cover shell, apply_patch, MCP writes and Agent lifecycle without parsing
   command-shaped text that is merely search input.
5. Founder status is compact: `IN PROGRESS` and `NEXT`, merging native and
   external lanes.

