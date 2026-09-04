# Architect decision — dispatch-c717fd8a blocked question

## Question
The backfill found `getmany-followup-bot/.claude/ref/leadv2-main-model.yaml` still set to `fable`,
but the WORKTREE PIN confines all edits to this lane. Keep the pin and report a reversible manual
command, or authorize editing the external getmany checkout?

## Decision

DECISION_OPTION: a
RATIONALE: The WORKTREE PIN and the standing "never edit shared/external trees on your own initiative" rule both forbid mutating a checkout outside this lane without an explicit founder order; the timeout is not consent, and a reported reversible command loses nothing.

## Why option a

1. **Authority.** Editing another repo's checkout is a founder-owned scope change. The global rule
   (user CLAUDE.md, "Shared trees — edit policy") is explicit: never edit shared or external trees
   unless the founder says so. An unanswered question within a timeout is silence, not approval.
   Option b would convert a timeout into an authorization, which is exactly the failure this rule
   exists to prevent.
2. **Reversibility and audit.** A reported one-line command keeps the change in the founder's hands,
   visible, and trivially reversible via `git checkout -- <file>` in that repo. A silent edit from
   this lane would land in a checkout whose git status, branch, and other live sessions this lane
   cannot see, so a conflict there would be invisible from here.
3. **Cost of delay is zero.** getmany-followup-bot is not a MythicalGames repo and is not on this
   lane's dispatch path. Its main-model pin staying on `fable` for another session does not block
   dispatch-c717fd8a's acceptance; it is a follow-up item, not a gate.
4. **Lane hygiene.** The pin exists so a lane's diff is reviewable as one unit. Writes outside the
   worktree root are a guard violation under the subagent protocol ("Writable scope — $WRITE_ROOT").

## What the task should emit instead of the edit

Report, in the task deliverable, a reversible manual backfill for the founder to run:

```bash
# in the getmany-followup-bot checkout
git -C <getmany-followup-bot-root> diff -- .claude/ref/leadv2-main-model.yaml   # confirm clean first
sed -i '' 's/^\([[:space:]]*model:[[:space:]]*\)fable\b/\1opus/' \
  <getmany-followup-bot-root>/.claude/ref/leadv2-main-model.yaml
# revert: git -C <getmany-followup-bot-root> checkout -- .claude/ref/leadv2-main-model.yaml
```

UNVERIFIED: the exact key name (`model:`) and target value in that file were not inspected from
this lane; the task should print the file's current line alongside the command so the founder
sees before/after. Also add the item to the backlog via `scripts/task-add.sh` so it is tracked,
not just mentioned.

## Out of scope
- Any write under the getmany-followup-bot checkout from this lane.
- Any MythicalGames repo change (neither option touches them).

DELIVERABLE_COMPLETE
