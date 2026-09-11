# LEAD-BURN-MECHANISM-01 — sol's job: try to break astra's negative

You are `gpt-5.6-sol`, the adversarial/exhaustive arm. You are **not** being asked the original
question. Another arm already answered it, negatively, and that negative now blocks a whole
class of work. Your job is to attack it.

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF.md` for the measurement, then
`docs/handoff/LEAD-BURN-MECHANISM-01/PROPOSAL-astra.md` for the claim you are attacking. Unlike
the other arms, **you are explicitly told to read astra's file.** That is the point.

## The claim under attack

Astra's load-bearing conclusion, in its own words:

> The live `hooks.json` supplies `PreToolUse`, `PostToolUse`, `UserPromptSubmit` and `Stop`, and
> **no pre-assistant-message event.** `PreToolUse` receives a tool only *after* the model has
> already emitted the one-tool assistant message. A denial therefore cannot batch that
> already-paid turn; it creates a corrective turn. `Stop` can read the transcript but also fires
> after the text is generated. **Neither can remove any of the 11,356 or 13,437 observed turns.**

If that is right, the entire "put a guard in `plugins/leadv2/hooks/`" direction is dead and
should not be built. A conclusion that expensive, reached by one arm in one pass, must survive a
hostile check before anyone acts on it.

## What would falsify it — attack these, in this order

1. **Is the event list actually complete?** Astra names four events from `hooks.json`. The
   plugin's own `hooks.json` reportedly spans ~10 event types. Enumerate every event the runtime
   supports — not every event this repo happens to use — and check each one against the claim.
   A single event that fires before or between assistant messages breaks it.
2. **Is "the turn is already paid" true?** This is the crux and it is an assertion about
   billing, not about hooks. If a `PreToolUse` denial causes the model to retry *within the same
   assistant turn* rather than emit a new one, the denial is free and astra is wrong. If it
   forces a new turn, astra is right. Establish which, with evidence, not reasoning.
3. **Does a corrective turn actually cost more than it saves?** Astra treats "creates a
   corrective turn" as disqualifying. But one corrective turn that teaches a batch of five calls
   replaces four turns — net −3. Astra never did that arithmetic. Do it: at what batch size does
   a deny-and-retry mechanism break even, and does the measured data ever reach that size?
4. **The `Stop` angle.** Astra dismisses `Stop` because it fires after generation. But
   `leadv2-lead-prose-guard.sh` already hangs there and already reads the transcript. Establish
   what `Stop` can actually do — can it block, can it inject, does a block cause a regeneration
   that replaces the text-only turn or one that adds to it? 45.8% of the bill is text-only
   turns; if `Stop` can suppress even a fraction, astra's "unreachable" is wrong.
5. **Anything astra asserted without showing the check.** Its report is 19 lines for a
   four-part question. Find the assertion it did not verify.

## The honest outcomes, all three acceptable

- **Astra is wrong** — name the event or the mechanism it missed, with the verification.
- **Astra is right but for a weaker reason than it gave** — the conclusion stands, the argument
  does not. Say which part is load-bearing and which was decoration.
- **Astra is right and the reasoning holds.** Then say so plainly. A confirmed negative from a
  hostile second pass is worth more than the first pass was, and this is a perfectly good result.

Do not manufacture a disagreement to look useful. Do not soften a real one.

## Deliverable — exactly one file

    docs/handoff/LEAD-BURN-MECHANISM-01/FALSIFY-sol.md

No code, no `plugins/` edits, no test suites. Do not modify BRIEF.md or PROPOSAL-astra.md.
Do not read or create `PROPOSAL-fable.md` — a third arm is working that half independently.

## Hard constraints

- `~/.claude/burn/history.db` is read-only, always (`file:...?mode=ro`). Never write to it or to
  anything under `~/.claude/burn/`.
- Do not read or modify `~/.claude/settings.json` or any permission file.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit with `git commit -m "..." -- docs/handoff/LEAD-BURN-MECHANISM-01/FALSIFY-sol.md`;
  do not push.

## Report back

Under 400 words: your verdict on each of the five attacks, the break-even batch size from
attack 3 with its arithmetic, and one sentence saying whether the hook direction is dead or
alive — because a build decision hangs on it.
