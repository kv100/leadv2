# CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The defect, in one line

`plugins/leadv2/hooks/leadv2-continuation-guard.sh:332`

```bash
# Had a tool call → pass through. A measured/reported turn is not silent.
[[ "$HAS_TOOL_CALL" == "yes" ]] && exit 0
```

The guard's own header states the contract it means to enforce (`:12`):

> demanding either: (a) a tool call / **dispatched worker / armed watcher** this turn, or
> (b) only the missing continuation/close line

It states three acceptable things and **checks only the first**. So any turn that touched any
tool — even one that left nothing running — passes.

## Why this matters more than it looks

A tool call proves the turn did work. It does **not** prove the session will ever wake again.
Nothing in this architecture re-enters the lead on its own: the only things that wake it are a
background command completing, a Monitor emitting an event, or a Monitor expiring. If a turn ends
with no live background job and no armed Monitor, the session sleeps until a human types.

Measured on 2026-09-17: the lead ran a full turn of `task-close.sh` / `task-add.sh` / report
writes — many tool calls, guard passed — and ended with every Monitor expired and no background
job. Three lanes with finished, unverified work sat dead for **six hours** while the anti-silence
pulse wrote `[ПУЛЬС 07:16Z] live=0 — тишина` into a file that no Monitor was relaying. Both
halves of the failure are the same root: nothing was armed to wake anyone.

The founder's words: this has recurred dozens of times. Every previous fix addressed *reporting*
(pulse, watchers, status lines). None addressed *waking*. The guard is the only mechanism placed
to catch it and its predicate is too weak by exactly one clause.

## What to build

Change the predicate from "did this turn use a tool" to **"will anything wake this session
again"**. A Stop-time turn is safe if an active task exists AND at least one of:

1. a live lane/worker/dispatcher process attributable to this session exists;
2. a live background command exists;
3. an armed-watcher sentinel is fresh (see below).

If none holds while an active task exists, BLOCK with a message naming what to arm.

**The sentinel is the part needing design.** A Stop hook cannot see Claude Code's internal
Monitors, so requirement 3 needs a file the lead writes when it arms one, with a timestamp and
the monitor's expiry. Decide its shape, where it lives (control plane, not the repo — see
`REGISTRY-MUST-LEAVE-GIT-01`), and how a stale sentinel is distinguished from a live one. State
in the report what you rejected and why. A sentinel that never expires would re-create the
present bug in a new place.

Keep every existing pass-through that is genuinely safe (`stop_hook_active`, the per-session
anti-loop sentinel, fail-open on crash, the kill switch `LEADV2_CONTINUATION_GUARD=0`). This
change must not be able to wedge a session: a guard that deadlocks is worse than one that leaks.

## Off limits

- Do not widen the guard into a general "did the lead do enough work" judge. It has exactly one
  job: no stall may be mistaken for completion.
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.

## Controls

Two independent claims, two negative controls, each run, both outputs pasted:

1. a turn with tool calls but **no** waker armed → the guard BLOCKS (today it passes; this is the
   bug, and this control must go red before the fix and green after);
2. a turn with a live background job or fresh sentinel → the guard PASSES (no false block — a
   guard that blocks a working session is the failure mode that gets a guard switched off).

Apply each mutation inside the function body in the lane worktree, never a scratch copy. Assert
the mutation target is present before running.

## Deliverable

`docs/handoff/CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01/report.md` — the new
predicate, the sentinel design with the rejected alternative named, both controls with pasted
output, and the suite that now guards `leadv2-continuation-guard.sh` with its name and how CI
selects it.
