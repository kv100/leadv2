# Nested agents: is depth 1 / read-only / two-types still the right shape?

**Founder order, 2026-09-08:** «оу ну и тоже самое про nested agents отдельно решить нужны ли,
какая глубина и если нужны то пусть fable + astra придумают дизайн. и воркфлоу и nested agents
делаем до waves.» Same treatment as the dynamic-workflow question, and it lands BEFORE the waves
gate, not after it.

This is a **report-only design mission.** Change nothing. Two arms answer it independently and
their two reports are compared; a single merged opinion wearing two names is worth less than two
that disagree.

---

## Do not re-derive these. They are measured, as of 2026-09-08, post-merge.

Nested agents are not a gap to be filled. They exist, they are governed, and the governing
document is `plugins/leadv2/config/nested-spawn-policy.yaml`, read by
`plugins/leadv2/hooks/leadv2-routing-guard.sh` behind `LEADV2_NESTED_DEPTH_GATE` (default ON).
Current contract, verbatim from that file:

    max_depth: 1
    max_nested_per_task: 3
    tool_class: read_only

    base_allowlist:  explore (haiku|sonnet, 3), general-purpose (haiku|sonnet, 3)
    per_caller:      developer -> explore (haiku, 3); architect -> general-purpose (sonnet, 2)

Write-capable roles are hard-denied regardless of the file's contents. A per-repo override at
`<project>/.claude/leadv2-overrides/nested-spawn-policy.yaml` wins ENTIRELY when present -- it
does not merge.

The lane prompt at `plugins/leadv2/scripts/leadv2-dispatch-code.sh:6142-6143` adds two rules the
yaml does not express: never `run_in_background=true` on a nested spawn (await it in the same
turn), and never `isolation:"worktree"` (the child writes in THIS lane's worktree).

The platform has moved underneath this policy, and the file says so itself: Claude Code 2.1.224
defaults to spawn depth 3, no per-session subagent cap, 20 concurrent. User settings pin
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` as a backstop. So leadv2's depth 1 is now a deliberate
narrowing of a more permissive platform, not an inherited limit.

**Correcting my own earlier statement:** I told the founder there was "no depth cap found." That
was wrong -- I had grepped the scripts and not the config. There is a cap, at `:26`. Do not repeat
the error; quote the file.

**Known blocker, already filed as its own task (`10ee163f7a3e`), do not re-diagnose it:** the
built-in `Explore` agent requires an explicit model, while the arbiter's spawn gate refuses a
spawn that carries an explicit model for a built-in agent. The two rules block each other, so in
practice a nested spawn only succeeds through an agent that has frontmatter. Take this as an
input: **the allowlist's two entries may both be unreachable as written.** Verify whether that is
so before designing on top of them.

---

## The four questions, in the order that decides the rest

1. **Is depth 1 correct?** The honest form of this question is not "is deeper better" but "name a
   task shape that genuinely needs a grandchild." If you cannot name one from this repo's actual
   work, depth 1 is right and the answer is one sentence long. If you can, say what the second
   level buys that a wider fan-out at depth 1 does not.

2. **Is `tool_class: read_only` correct?** A nested agent that cannot write cannot finish work; it
   can only inform the parent, which then writes. That is a real constraint with a real cost. State
   what it costs us today, and whether any write authority could be granted without making the
   lane's `LANE_WRITES` contract unenforceable -- that contract is the thing that keeps two lanes
   from silently overwriting each other, and it is per-lane, not per-agent.

3. **Should the ARBITER pick the nested agent, instead of a static allowlist?** This is the founder's
   doctrine for workflows -- «решает арбитр какие и как» -- and the same question applies here. The
   allowlist hardcodes explore/general-purpose at haiku/sonnet. The arbiter already has a
   capability x cost matrix and a `cheapest_capable` rule. Say whether the nested choice is the
   same KIND of decision the arbiter makes for a lane arm, or a different kind that only looks
   similar. Both answers are acceptable; an unargued "yes, use the arbiter" is not.

4. **Do codex and GLM belong here at all?** The founder's order for workflows was that every arm is
   usable and the arbiter chooses. For nested spawns the mechanism is Claude Code's own Agent tool,
   which has no codex or GLM arm -- so if those arms should be reachable from inside a lane, that is
   a different mechanism than nesting (codex has `mcp-server`, `agents`, `exec-server`, `cloud`, all
   currently unused). Say plainly whether the nested-agent question and the "codex inside a lane"
   question are the same question or two, and do not answer the second one here if it is a second.

---

## What makes a recommendation acceptable

Whatever you recommend must be **measurable the day it ships, by a value that has never varied
before.** A seam whose only evidence is "it feels faster" or "fewer calls" is not ready, and saying
a change is not ready is a valid recommendation -- preferred over a design that cannot be checked.

Name, for each recommendation:
- the single value that changes,
- where it is emitted today (file:line) or that it does not exist yet,
- and the mutation that would make it go the wrong way, so the change can be negative-controlled.

Recommending "keep it as it is" for any of the four questions is a complete answer if the argument
is there. This mission is not a request for changes; it is a request for a decision.

---

## Constraints

- **Report only. Do not modify any workflow, script, or config.** Output paths, one per arm, distinct:
  **You are the fable arm. Write ONLY** `docs/handoff/SMART-ARBITER-DESIGN-20260907/nested-agents-report-fable.md`. A second arm answers the same mission into its own file; do not read or wait for it.
- Read whatever you need, including the routing guard, the skill at
  `plugins/leadv2/skills/leadv2-subagent-protocol/NESTED-SPAWNS.md`, and
  `plugins/leadv2/config/direct-spawn-gate.yaml`.
- Do not open a founder question. If something is genuinely undecidable at your level, write the
  question into the report and say what you would need in order to answer it.
- Length: whatever the argument needs. A one-page report that answers all four is better than
  fifteen pages that answer none.

LANE_WRITES: docs/handoff/SMART-ARBITER-DESIGN-20260907/nested-agents-report-fable.md

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-62f2f47e" "<question>" \
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