# NATIVE-CODEX-CONTROL-PLANE-01-R2-TARGETED

Targeted continuation on worktree `a2d18758` at `e4dc1f7`. Fix only the native
review High blockers plus the write-worker contradiction below; do not redesign.

1. Remove fictional `shared_writes`. Accept the real native schemas for
   `spawn_agent`, `followup_task`, `send_message`, `wait_agent`,
   `interrupt_agent`, `list_agents`, and `update_plan`. Native subagents inherit
   the same tool hooks, so the spawn gate must not invent unsupported fields.
2. Never infer MCP safety from a verb substring. Use an exact read-only allowlist
   of fully-qualified tools (plus an explicit environment allowlist extension);
   unknown/dynamic MCP tools fail closed. Prove `mcp__x__search_and_delete` denies.
3. Make lifecycle recording concurrency-safe without lossy shared read-modify-
   replace. Prefer one atomic file per agent in a registry directory, or a bounded
   portable lock. Prove 64 concurrent starts all remain visible and stops remove
   only their own entries.
4. Restore every mandatory root gate deleted from the original skill: pilot
   bootstrap, lv2guard side effects, external dispatch, review, compact status and
   evidence close. Add native semantics without replacing those controls.
5. `apply_patch` must remain usable by a sanctioned external Codex write worker:
   allow only when event `cwd` is an isolated `/.claude/worktrees/<lane>` and every
   patch target resolves inside that cwd; deny on main worktree, absolute escape or
   `..` escape. Parse the documented `tool_input.command`, not prose.

Update focused tests to use official wire shapes, include main-vs-isolated patch
cases, exact MCP allow/deny, native continuation tools, restored root gates and
parallel lifecycle stress. Preserve all prior green guard/manifest tests. Commit
and leave clean.

acceptance:
  surface: file_artifact
  observable: Official native agent tools work, unknown MCP writes fail closed, isolated dispatcher patches work without main-tree escape, concurrent lifecycle events are lossless, and all mandatory lead gates remain present.
  authored_at: 2026-08-24T21:43:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2/SKILL.md,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh,plugins/leadv2/codex-lead/tests/test-codex-hooks.sh,plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-95d23246" "<question>" \
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