# Round 3 — sol: price the founder's actual decision, and his condition

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-03-WHAT-WE-CARRY-AND-NEVER-USE.md` in this
worktree first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are `gpt-5.6-sol`, the adversarial arm. You falsified round 1's census and round 2's
compaction premise, and were right both times. Your own round-2 result is the input here: optimum
~164k for persona-engine, ~274k for getmany, and `--autocompact` is real and settable.

Two other arms work the apparatus and guard halves; do not read their files.

## The decision, in the founder's words

> «ранний автокомпакт не делать раньше, ну давай на 10 процентов раньше. Сейчас вроде на 500k,
> давай на 450. Я соглашусь на 400, если на старте сессии тут и в других местах не будет занято
> 130-150k контекста.»

So the live proposal is **450k**, not your 164k optimum, and **400k is conditional on the session-
start floor dropping below ~130-150k.** Your job is to price exactly that, adversarially, and to
tell him plainly if either number buys nothing.

## What to establish

1. **What 450k is worth against the measured 467,627.** Run it through your own round-2 cost model
   with the measured `F` and `g`. A 4% reduction in the ceiling is a small move on a sawtooth; give
   the number, and if the saving is inside your model's error bars, **say it is indistinguishable
   from zero** rather than reporting a false precision. That is the most useful thing you can
   return.
2. **The marginal curve between 450k and 164k.** He has agreed to 450 and conditionally to 400.
   Where does the curve actually bend? If most of the available saving sits below 400k, the honest
   answer is that both of his numbers are on the flat part and the conversation should be about
   300k — with the arithmetic to justify asking.
3. **His condition, measured.** "130-150k occupied at session start, here and in other places."
   Measure the real session-start prefix per repo across the available history — persona-engine,
   getmany-followup-bot, m3-market, leadv2 — as a distribution, not one number. The round-2 floor
   table was already falsified once (the claimed m3-market floor of 59,876 does not reproduce), so
   treat every prior floor figure as suspect and re-derive. Then answer the only question that
   matters to him: **is the 130-150k condition already met somewhere, and what would it take to
   meet it in persona-engine?** Two decided changes are pending and you may model them: unsetting
   `ENABLE_TOOL_SEARCH=auto:50` (~10k of MCP schemas deferred) and the guard-injection reductions
   another arm is pricing. State what remains after both.
4. **Whether one global threshold is safe at all.** Your round-2 table already says no — getmany
   loses at 250k. Give the per-repo recommendation as a table the lead can implement directly, and
   name where the value is set: `claude-subsession.sh` passes `--autocompact`, but the interactive
   lead session is launched by the founder, not by that script. **If the interactive session's
   threshold cannot be set from this stack, say so** — that would make the whole lever apply only
   to subsessions, which is a different and much smaller prize, and the founder needs to know it
   before he acts.

## The trap

The flattering answer is "450k is a good first step". Check whether it is a step at all. If the
measurable saving from 467k to 450k is under a few percent of session cost, the correct
deliverable is one sentence saying so, followed by the threshold that would actually pay.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-sol-threshold.md` — nothing else. No `plugins/`
edits, no code, no test suites.

## Report back

Under 400 words: what 450k saves, where the curve bends, the measured session-start floor
distribution per repo with your method, whether his 130-150k condition is reachable and after
which changes, whether the interactive session's threshold is settable at all, and the one thing
in BRIEF-03 you checked that was wrong.
