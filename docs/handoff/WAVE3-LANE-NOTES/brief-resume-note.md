
---

## RESUME NOTE — read this FIRST, before you plan anything (lead, 2026-09-03T21:xx)

**This lane already has work. Do not start from zero. You will destroy it if you do.**

A previous worker on this exact lane was killed mid-task at ~2026-09-03T17:54:44Z — not because it
finished, but because the parent Claude Code session exited and took every lane worker with it
(measured: zero processes for five lanes, three of them with an identical stream age to the second).
Its work was sitting uncommitted in this worktree and would have been swept, so the lead committed
it verbatim as a single `wip(<task-id>): rescue uncommitted lane work after worker death` commit on
this branch.

So, before your first edit:

1. **Read `git log -1` and `git show HEAD` in this worktree.** That commit is the previous worker's
   half-finished state. It is your starting point.
2. **Judge it, do not trust it.** It was never reviewed, never tested, and no negative control was
   ever run against it. Parts of it may be wrong or half-written mid-function. Keep what is right,
   fix what is not, and say in your final report which parts you kept and which you rewrote.
3. **Do not revert it and do not `git checkout` over it.** If you disagree with an approach in it,
   change it forward in a new commit so the history shows the decision.
4. A clean working tree here means "the lead committed the rescue", NOT "the task is done". The only
   evidence that this task is done is a green suite plus a negative control that was actually run.

## What still has to be true before this lane can close

- The negative control is a mutation inserted **inside a function body**, never at file top level —
  a top-level insert turns every suite red for the wrong reason and reads as a pass.
- Proof is the **`baseline_rc` / `mutated_rc` pair plus the literal red suite line**. Show the suite
  green, apply the mutation, show it red, revert, show it green again, and paste both exit codes.
- The suite must be **registered in `EXTRA_SUITE_MAP` in `tests/run-all.sh`**, and you must prove
  that `--scope changed` actually SELECTS it. An unregistered suite rots silently: of the 23 suites
  the plan assumed, the runner can currently reach 9. A green suite CI never runs is worth nothing.
- Green on macOS **and** in a linux container. Paste both exit codes.
- Before you finish: `git diff --diff-filter=D --name-only main...HEAD` — **three dots**. Two dots
  report other people's commits in main as your deletions; that false reading nearly cost five lanes
  today. Anything genuinely deleted by mistake gets restored from main.
- Commit your work in this lane before you exit. Do not leave it uncommitted — that is exactly how
  the previous worker's output almost vanished.

## Off limits

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by the lead session.
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — another architect is working in it.
- `tests/known-red-suites.txt`; weakening any assertion; committing to `main`; any commit inside
  `~/MythicalGames`.
- Never print or log a credential value, token, or refresh token. Labels, subscriptionType, uuid
  tails and digests only.

One thing that will save you an hour: the routing arbiter answers `all_arms_capped` in roughly 1773
of ~1800 cases, so the fallback ladder hands out nearly all work. Those refusal lines are known and
owned by the lead — do not investigate or fix them.
