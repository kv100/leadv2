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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a2d18758" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.