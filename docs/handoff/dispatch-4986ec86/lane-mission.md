# NATIVE-CODEX-OPS-PROFILE-01-R1

Finish the Codex-native operating profile without touching dispatcher, review
engine or hooks.

1. Runbook: launch the root lead as Terra/high. Remove every fixed WIP=1 rule;
   capacity is computed from native slots, live provider health, dependencies and
   overlapping write sets. Mention that `codex fork` is founder-chat branching,
   while worker concurrency uses native agent controls.
2. Status skill: merge native `list_agents` state and current native plan with the
   external leadv2 registry/quota sources. Render only a compact founder view with
   `IN PROGRESS` and `NEXT`; never invent counts or quotas.
   Pulse is a state-change/maximum-60-second progress update while work is active,
   not WIP=1 and not a request for technical decisions. Lifecycle hooks supply
   machine pulse evidence; chat emits only the compact milestone.
3. Source-command skill: Codex is the single-task lead, not a child of
   Claude/Opus. It may have an optional supervising parent of any type. Use native
   agent continuation semantics and preserve evidence-first close.
4. Focused install/contract tests must reject Sol/xhigh, fixed WIP=1 and
   Claude-child wording, and assert Terra/high plus native status/control terms.

Keep chat Russian/docs English. Commit all files and leave the worktree clean.

acceptance:
  surface: file_artifact
  observable: Installed operational docs launch Terra/high, admit dynamic non-conflicting work, show native plus external status compactly, and no longer define Codex as Claude's child.
  authored_at: 2026-08-24T21:40:00Z

LANE_WRITES: plugins/leadv2/docs/codex-lead-pilot-runbook.md,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2-status/SKILL.md,plugins/leadv2/codex-skills/source-command-leadv2/SKILL.md,plugins/leadv2/codex-lead/tests/test-codex-install.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4986ec86" "<question>" \
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