# MISSION — CODEX-DOOR-DEAD-01, finish it (you found the review half; land it and answer the dispatch half)

Resume the same worktree (`3b96b97c`). It holds a 66-line change to
`plugins/leadv2/scripts/leadv2-review-run.sh` and **no report**, so nothing has landed and nobody can
act on what you found.

## What you already established — keep it, it looks right

`REVIEW-CODEX-EMPTY-BASE-01`: codex's `--base HEAD` diffs a committed lane's current HEAD against
itself, because `resolveReviewTarget` treats an explicit `--base` as authoritative and never falls
back to working-tree mode. So an already-committed lane always hands codex an empty branch diff →
short stdout → and the body-persist guard correctly reports `review_body_lost`, because codex writes
its `[codex-task] tier=…` banner to stderr whether or not a real body exists.

That explains **`ee807b33`'s two `review_body_lost` verdicts exactly.** Finish it:

1. A test that a committed lane resolves a base which is not its own HEAD, and that a bare `HEAD`
   base is refused rather than silently reviewing nothing. Red against the pre-fix script.
2. Commit on `main` in `~/Projects/leadv2`.
3. Write `docs/handoff/CODEX-DOOR-DEAD-01/report.md` — the mechanism, the fix, the test.

## The half still unanswered — the dispatch door

Four lanes (`8c576a71`, `3063f046`, `f7f1c2c8`, `b2714233`) were routed to codex as **builders** and
wrote zero bytes: no `developer.stream.jsonl`, no file touched in the lane worktree, while the close
loop polled `waiting_worker` for 20+ minutes. That is a different failure from an empty review diff —
a builder does not diff anything.

Is it the same root cause or a second one? Decide it with a reproduction, not by reading the spawn
path. If it is a second fault, name the mechanism; if you cannot reproduce it, say so plainly and
give the smallest safe mitigation, because codex is currently locked out for 6h and that costs us the
arm on every lane.

## Also owed

`record-quota-lockout` cannot express "this provider is broken, stand it down": given
`--provider codex --hours 3` it recorded `arm_postspawn_verdict … quota=no` and left an **expired**
lockout file untouched, so the router picked codex again minutes later and killed another lane. Add a
supported duration-based stand-down, distinct from "out of quota".

## Hard constraints
- **Never `reset --hard`, `clean`, or `stash`** in this tree — three live repos share it. Re-`git
  diff` immediately before you `git add`.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
The committed fix, its test, the dispatch-door verdict, the lockout duration support, and
`docs/handoff/CODEX-DOOR-DEAD-01/report.md`. End with DELIVERABLE_COMPLETE.
