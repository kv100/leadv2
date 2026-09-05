# NATIVE-CODEX-ROOT-SKILL-01-R2

Narrow replacement for the parked broad orchestration lane. Update only the
root leadv2 skill so it describes the actual Codex-root control plane.

Required contract:

- Native read-heavy agents use `spawn_agent` with explicit `fork_turns`;
  `followup_task` continues the same task, `send_message` guides a live agent,
  `wait_agent` waits, `interrupt_agent` cancels, and `list_agents` reports state.
- `codex fork` is an interactive founder-chat branch, never worker dispatch.
- External dispatcher/worktrees remain the only write-worker path and the
  Claude/GLM path.
- WIP is dynamic from free slots, provider health, dependencies and overlapping
  write sets. Never hard-code WIP=1.
- Keep founder chat in Russian and compact: one-line milestone updates and an
  `IN PROGRESS` / `NEXT` status; ask only product decisions.
- Token policy: default `fork_turns: none` for isolated scans, `all` only when the
  worker needs the conversation; one reviewer normally, escalation only by risk.

Preserve frontmatter and plugin naming. Do not touch other files. Commit and
leave the worktree clean.

acceptance:
  surface: file_artifact
  observable: The installed leadv2 root skill states native Codex agent semantics, external write isolation, dynamic WIP and compact quota-efficient founder communication.
  authored_at: 2026-08-24T21:25:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2/SKILL.md
