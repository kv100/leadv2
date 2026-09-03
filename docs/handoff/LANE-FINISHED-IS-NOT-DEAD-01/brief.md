# LANE-FINISHED-IS-NOT-DEAD-01 — a finished lane is escalated as a death, and a finished lane blocks its own re-dispatch

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-FINISHED-IS-NOT-DEAD-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-active-registry.sh,plugins/leadv2/scripts/leadv2-lane-placement.sh,plugins/leadv2/scripts/tests/test-lane-finished-state.sh,tests/run-all.sh,docs/handoff/LANE-FINISHED-IS-NOT-DEAD-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

**The pid fix from `7f22d3d` is correct and stays.** The V5 session confirmed its plugin copy is
identical to canonical (ancestor of HEAD, mtime after the commit). The recorded pid is now
truthful. This lane is about what the system *concludes* from a truthful pid.

## The defect: there are three lane states, and the code knows only two

A lane can be **running**, **dead**, or **finished**. Today "finished" has no representation, so
it is misread in both directions — and both errors were observed live today on
V5-M0-SKELETON-01.

**Direction 1 — a finished lane escalated as a death.** Three questions fired at the founder:
`q-5c7bda1e` (~08:5x), `q-991cc44f` (~09:1x), `q-3d20007c` (~09:3x), all saying
`corroborated dead: pid dead`. All three were **true about the pid and useless**: the worker had
already finished normally and committed — `8f898d5ae`, `6c9831c83`. Three founder interrupts
for three successful rounds.

**Direction 2 — a finished lane blocking its own re-dispatch, and this one costs more.** A
fix-round dispatch was refused:

```
lane_placement_refused reason=lane_is_live ... verdict=alive age=443
```

Liveness was judged by **stream freshness** while the pid was dead and the work was already
committed. The V5 lead had to wait out an ~11-minute window and re-dispatch by hand.

So the same missing state makes the system say "it died" about a success and "it's alive" about
a finish, at the same moment, from two different probes.

## [Critical] introduce "finished" and derive it from evidence, not from one signal

A lane with **no live pid** and **a commit in the lane within the last N minutes** is
*finished* — not dead, not alive. Concretely:

- finished ⇒ **no escalation to the founder**; the pid being gone is the expected end of a
  round, not an incident;
- finished ⇒ **re-dispatch is admitted**; `lane_is_live` must not be satisfied by stream mtime
  alone when the pid is gone and a commit exists;
- dead (no pid, no recent commit, no deliverable) ⇒ escalate exactly as today;
- alive (pid live) ⇒ unchanged.

Read the two probes before you touch them: the escalation path in
`leadv2-active-registry.sh` and the placement verdict in `leadv2-lane-placement.sh`. They must
agree on the same three-state answer — a lane that one calls finished and the other calls alive
is the bug, restated.

Pick N and justify it in `report.md`. Do not make "finished" depend on a worker's own claim of
success; a commit in the lane and an absent pid are both externally checkable facts, which is
the point.

## Acceptance

Build `test-lane-finished-state.sh` against a fixture lane and fixture registry — never a real
lane, never a real state root — covering:

1. live pid ⇒ alive; re-dispatch refused as today;
2. no pid + a commit inside the window ⇒ **finished**: no escalation raised, re-dispatch
   admitted;
3. no pid + no commit + no deliverable ⇒ dead: escalation raised exactly as today;
4. no pid + a commit, but a stream file that is still fresh ⇒ still finished — stream mtime
   must not override the pid+commit evidence (this is the exact 09:5x refusal);
5. the escalation path and the placement path return the same state for all four fixtures.

Add the `EXTRA_SUITE_MAP` rows for both touched scripts and prove selection with
`--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0 — that exact defect shipped in this very suite's sibling last night.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Do not weaken or revert the `worker_pid` fix from `7f22d3d`; a mutation removing it must
  still turn `test-lane-registry-outlives-dispatcher.sh` red.
- The suite must leave every repo path and every real state root byte-identical, on the failure
  path too.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A finished lane raises no escalation and does not block its own re-dispatch, a genuinely dead
lane still escalates, and a mutation collapsing "finished" back into either neighbour turns the
suite red with the exit code following.
