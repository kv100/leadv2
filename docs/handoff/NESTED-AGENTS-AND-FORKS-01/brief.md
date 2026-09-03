# NESTED-AGENTS-AND-FORKS-01 — dispatched workers have no contract for subagents, and forks are never used

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead on founder
order: workers SHOULD delegate to cheaper agents; the point of the capability is that cheap models do the
bulk work. Today it produced the opposite.

## Measured, not assumed

Across 400 session transcripts modified in the last 30 days:

| probe | count |
|---|---|
| `"subagent_type":"fork"` | **0** |
| `subagent_type":"Explore` | 2 |
| `escalation-budget` | 4 |
| a journaled spawn/escalation denial | 0 |

And the structural fact behind those numbers: **there is no worker-side preamble governing spawns.**
`grep -rl preamble` over `scripts/ docs/ skills/` finds nothing that a dispatched worker reads, and
`leadv2-dispatch-code.sh` carries no `Agent(` guidance for the child. The child gets a mission and a set
of constraints about files, and nothing at all about how to delegate. So every worker improvises.

What the improvisation cost on 2026-09-02, across five lanes:
- BRAIN-CLASS-LIVE-01 R4g spawned a nested developer with `isolation:"worktree"`. The child produced a
  correct 119-line diff into a stray worktree (`agent-a4be34650195f2188`) that the epilogue never reads;
  the lead salvaged it by hand. Round otherwise lost.
- WORKER-MCP-ALL-ARMS-01 R4f spawned a nested developer with `run_in_background=true`, then ended its turn
  after 5 turns "per pulse mode". A dispatched worker has no next turn, so the child was unreachable.
- The other three lanes did all the work themselves on the sonnet arm — 58, 83 and 86 turns — with no
  delegation to a cheaper model at all, which is the waste the capability exists to prevent.

Fork is the sharpest miss: `commands/leadv2.md` documents (FORK-ADOPT-01) that `Agent(subagent_type="fork")`
inherits the caller's full conversation and prompt cache, so a fix-round that must see the whole task
history costs almost nothing. Zero uses in 30 days, by the lead or any worker.

## What this task must deliver

1. **A worker-side delegation contract**, injected into every dispatched worker's prompt by the dispatcher
   (one place, so it cannot drift):
   - Delegation is ENCOURAGED for bulk reads, censuses, mechanical edits — prefer a cheap model.
   - **Synchronous only.** Never `run_in_background` from a dispatched worker: it has one turn-chain and
     receives no notifications. Await the child inside the same turn.
   - **Never `isolation:"worktree"`** — the child must write in the lane worktree.
   - The parent commits the child's output before its turn-chain ends.
   - Model guidance: haiku for reads/censuses, sonnet for edits, never opus from a worker.
2. **Make fork reachable.** State in the same contract when a fork beats a fresh agent (the child needs the
   task history), with one worked example. Then verify by measurement, not by hope: after the change, a
   fork must appear in a real round, and the census probe above must move off zero.
3. **Prove the escalation budget is real or delete it.** `escalation-budget.yaml` is documented in Phase 4
   of `commands/leadv2.md`, appears 4 times in 30 days, and has never denied anything. Either write a suite
   that shows a spawn beyond budget is refused (with a negative control), or remove the machinery — an
   unenforced budget is the lying-green disease.
4. **Epilogue guard:** flag a lane whose only new work lives in a worktree other than the lane's, and
   journal `worker_wrote_outside_lane task=<id> path=<other>`. That single line would have made today's
   BRAIN salvage automatic.

## Constraints
- Land in the plugin repo. Every check ships a negative control that goes red in a mktemp FULL copy
  (including `lib/`) whose baseline is green. No nested background spawns while building this, obviously.

## Done when
- the contract text is injected by the dispatcher and visible in a real worker's prompt (paste it);
- a suite proves the epilogue flags an out-of-lane worktree, with a negative control;
- the escalation budget either refuses a spawn in a test or is gone;
- the fork probe is non-zero on a real round, or the doc says plainly that fork is not usable from a
  dispatched worker and why.
