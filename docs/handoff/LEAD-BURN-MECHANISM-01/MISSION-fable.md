# LEAD-BURN-MECHANISM-01 — fable's half (REVISION 2)

**Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF.md` in this worktree first** for the
measurement. Then read this, which narrows your half considerably. If BRIEF.md is not in this
worktree, stop and say so.

## What changed: the other arm already closed the mechanism question, negatively

The codex arm (astra) ran first and **blocked rather than proposing**, correctly. Its verified
finding, which you should treat as established and NOT re-derive:

> The live `hooks.json` supplies `PreToolUse`, `PostToolUse`, `UserPromptSubmit` and `Stop`, and
> **no pre-assistant-message event.** `PreToolUse` receives a tool only *after* the model has
> already emitted the one-tool assistant message — the turn is paid. Denying it does not batch
> that turn, it adds a corrective one. `Stop` likewise fires after the text is generated.
> **Neither can remove any of the 11,356 text-only turns or any of the 13,437 one-tool turns.**

So the entire hook-guard class has a verified saving of **zero**, and the brief's list of
candidate mechanisms is dead. Do not propose a hook. Astra also corrected two numbers by drift:
opus is now 28,246 turns / 8,582,770,142 cr. Use the current values you measure yourself.

Astra named two surfaces that are NOT dead: the **notification producer** (whatever enqueues
the 693 injected messages, which is outside `plugins/leadv2`), and the **model emitter itself**,
which no plugin can reach.

## Your half, now the only half left

The mechanism door is shut, so the behavioural question is no longer the soft half — it is the
whole answer. Two things, in this order:

**1. The batchable fraction — this is the deliverable.** Astra gives a mathematical ceiling of
6,718 removed messages if every one of the 13,437 calls could be paired, and states plainly that
the census carries no independence labels, so that ceiling is not a finding. **Produce the real
number.** The transcripts are on disk; a call is a candidate for batching only if it did not
depend on the previous call's result. Classify a sample large enough to defend, say how you
classified, and give the fraction with its error bars. If the honest answer is "most calls were
genuinely dependent and the reachable saving is small", that is a valuable result and you should
report it as such — do not inflate it to justify a mechanism.

**2. Why zero.** Not "low" — 0 of 13,437, on a rule stated in the harness prompt itself. A rule
with exactly zero compliance is not forgotten; something makes it structurally unreachable.
Candidates, none endorsed: independence is only knowable after the first result arrives; the
cost of a call lands on a later turn nothing connects back to the decision; the instruction is
read once while the behaviour is chosen thousands of times. Name the one you can support.

Then, and only then, say what would actually change the number given that hooks cannot. Be
willing to conclude that nothing inside this repo can, and to name what lives outside it.

## Deliverable — exactly one file

    docs/handoff/LEAD-BURN-MECHANISM-01/PROPOSAL-fable.md

No code, no `plugins/` edits, no test suites, no changes to BRIEF.md.
Do not read `PROPOSAL-astra.md` — everything from it that you need is quoted above.

## Hard constraints

- `~/.claude/burn/history.db` is **read-only, always** (`file:...?mode=ro`). Never write to it or
  to anything under `~/.claude/burn/` — unversioned, outside every repo, 15.5 MB live database.
- Do not read or modify `~/.claude/settings.json` or any permission file.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit with `git commit -m "..." -- docs/handoff/LEAD-BURN-MECHANISM-01/PROPOSAL-fable.md`;
  do not push.
- If a premise here fails your own measurement, **block and name it**, as astra did. That block
  was worth more than a proposal would have been.

## Report back

Under 400 words: the batchable fraction with your method and error bars, the cause you name for
zero compliance and what supports it, what would actually move the number given hooks cannot,
and the one number you checked that this mission or BRIEF.md got wrong.
