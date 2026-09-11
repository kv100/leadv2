# Round 3 — fable: the apparatus we pay for and never invoke

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-03-WHAT-WE-CARRY-AND-NEVER-USE.md` in this
worktree first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are the fable arm. You produced round 1's corrected census and round 2's external-tooling
verdicts, both of which found defects in the lead's own numbers. This is the founder's question,
in his words, and it is a judgment task, not a survey.

## The founder's question

> «есть ощущение что использование скиллов, MCP и т.д. не доходит ни до лида, ни до субагентов —
> ведь я очень редко вижу, чтобы они использовались. Например, у нас уже был скилл оценки задач,
> а в итоге мы написали скрипт. Я уверен, что такого дохуя. Вопрос: стоит ли улучшать скиллы, не
> использовать и дальше, начать использовать? То же самое про MCP.»

He is describing a specific failure he has already seen once: **a skill existed for task
estimation, and the work was done by writing a script instead.** He believes this is systemic.
Establish whether it is, then decide.

## What to establish, in this order

1. **Census the apparatus.** How many skills exist and where (plugin `skills/`, repo `.claude/`,
   user-level), how many agent definitions, how many MCP servers and tools, how many hooks and
   commands. Count what is *installed*, not what is documented.

2. **Measure invocation, per surface, from the transcripts.** `~/.claude/projects/*/**.jsonl` and
   `history.db` carry every `Skill` call, every `Agent` spawn with its `subagent_type`, every
   `mcp__*` call, every `ToolSearch`. Produce a table: surface → times invoked over the available
   history → last invocation date. The reference session's numbers are in the brief (0 mcp calls,
   11 ToolSearch all for built-ins) but that is one session; widen it. **Include subagents** — the
   founder's claim is that skills/MCP reach neither the lead nor the subagents, and a subagent's
   tool calls are in its own transcript, not the parent's.

3. **Explain the zeros.** A surface invoked zero times has a cause, and the causes are different
   and lead to different verdicts:
   - never loaded (schema deferred / not in the agent's tool list / server failed to connect),
   - loaded but never surfaced to the model (no listing, description does not match any real
     question shape),
   - surfaced but always beaten by a cheaper habit (`Bash` + `grep` is right there and costs one
     call — this is the estimation-skill case the founder names),
   - genuinely obsolete (its job moved into a script, a hook, or a plugin command).
   Sample enough real cases to support the attribution. Name the specific skills.

4. **The estimation case, specifically.** Find it. Which skill, when written, when last invoked,
   and which script now does the job. It is the founder's own example and it must be answered by
   name, not by category.

5. **Cost of carrying each surface.** Skill frontmatter loads eagerly; MCP schemas load per the
   brief's measurement; agent definitions load into the spawner. Give tokens per turn for each
   surface. A surface that costs ~0 to carry and is invoked 0 times is a different verdict from
   one that costs 6,354 tokens on every turn and is invoked 0 times.

6. **Verdict per surface: improve / start using / retire.** With the arithmetic, and for
   "start using", the specific trigger — the question shape that should route there and what
   currently absorbs it instead. "Improve" must name what is wrong with the description or the
   routing, not merely assert that the skill is good.

## Two things the founder asked inside this

- **The two code-intel MCPs** (`repowise`, `codebase-memory-mcp`) are in scope and get the same
  treatment as anything else: 8,769 tokens on every turn between them, 0 calls in the reference
  session. The repo's own `CLAUDE.md` mandates routing questions to them. Judge the mandate
  against the measurement. The founder asked specifically whether the graph MCP should stay.
- `repowise distill` is installed, executed 0 of 2,151 Bash calls, and is not on `PATH` in a child
  session. That is the same disease in a different surface — include it.

## The trap

The cheap conclusion is "retire everything with zero calls". That is wrong for any surface whose
zero is caused by (a) or (b) above — it was never reachable, so its zero measures our wiring, not
its value. Separate "never used" from "never reachable" before any retire verdict, or say you
could not and mark it unresolved.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-fable-apparatus.md` — nothing else.

## Report back

Under 400 words: the invocation table, the attribution of the zeros, the estimation-skill answer
by name, the per-surface verdicts ranked by tokens-per-turn carried, and the one number in
BRIEF-03 you checked that was wrong.
