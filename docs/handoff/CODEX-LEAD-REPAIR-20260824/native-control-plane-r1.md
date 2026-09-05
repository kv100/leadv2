# NATIVE-CODEX-CONTROL-PLANE-01-R1

Implement the first usable Codex-native control-plane slice in one isolated lane.

1. Root skill must define native `spawn_agent(fork_turns)`, `followup_task`,
   `send_message`, `wait_agent`, `interrupt_agent`, `list_agents`; clarify that
   `codex fork` branches founder chat and is not worker dispatch.
2. Keep external dispatcher/worktrees as the only write-worker and Claude/GLM
   path. Native agents are bounded read-heavy exploration, triage and independent
   review unless a project explicitly permits shared writes.
3. Replace fixed WIP=1 with capacity from native slots, provider health,
   dependencies and write-set collisions. Independent read work may overlap.
4. Make founder updates compact (`IN PROGRESS` / `NEXT`) and token-efficient;
   default isolated agents to `fork_turns: none`, use `all` only when required.
5. Extend the Codex PreToolUse adapter to recognize unified shell, apply_patch,
   MCP write-capable tools and Agent/spawn operations from `tool_name` plus typed
   `tool_input`. Do not scan arbitrary search/query text as a shell command.
   Unknown write-capable shapes fail closed; known read-only tools remain allowed.
6. Add SubagentStart/SubagentStop lifecycle hook entries that update a plugin-local
   native-agent registry/pulse artifact without invoking an LLM. The hook must be
   bounded, atomic and safe when optional fields are absent.
7. Add executable tests for shell deny/allow, read-only search false-positive,
   apply_patch/MCP/Agent classification, malformed payload, and lifecycle start/stop.

Do not touch review engine, dispatcher, runbook or status skill. No real provider
calls. Commit all changes and leave the worktree clean.

acceptance:
  surface: file_artifact
  observable: The lead skill uses native Codex agent semantics and hooks guard all write channels while recording native agent lifecycle, with executable tests passing.
  authored_at: 2026-08-24T21:30:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2/SKILL.md,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks.json,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh,plugins/leadv2/codex-lead/tests/test-codex-hooks.sh
