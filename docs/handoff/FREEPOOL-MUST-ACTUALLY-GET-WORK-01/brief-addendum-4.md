# FREEPOOL-MUST-ACTUALLY-GET-WORK-01 — addendum (4), read together with brief.md

## Measured while dispatching this very task — plus a correction

The dispatch of this brief was made with `--task-class standard` and no `--protected`.
The classifier put it at `heavy` and the free arm was excluded on SIZE, not on the flag:

    arm_excluded by=router arm=freepool task=e8db84ba reason=arm_not_capable_for_size
      task_class=heavy when=light,standard,bulk
    route_resolved by=arbiter arm=codex ... util_freepool=0

**Correction to the lead's first framing of this (founder, 2026-09-03).** Do NOT read this as
"the caller's class should win". The classifier is meant to be authoritative — that is the whole
point of making the arbiter smart, and a caller must never be able to declare a task small in
order to steer it onto a cheap arm. If `heavy` is the right verdict for a task of this shape,
then excluding the free arm here is CORRECT behaviour and there is nothing to fix in it.

Two real defects remain, and neither is about who has authority:

- **The override is silent.** The journal records only the final `task_class=heavy`. It never
  records that a caller asked for `standard`, that it was overridden, or why. Emit both values
  and the deciding reason whenever the classifier disagrees with the caller, so an arm dropping
  out of contention leaves a traceable line instead of a mystery. This is observability, and it
  changes no routing decision.
- **`--task-class` is parsed, documented in `usage()`, and then ignored on this path.** A flag
  that changes nothing is a lie in the interface. Either remove it, or keep it and document it
  explicitly as a HINT the classifier may override — and then actually journal the override.

Out of scope for this lane, worth its own backlog row only if you find evidence either way:
whether `heavy` is the correct verdict for a task of this shape. Do NOT tune the classifier here.

Evidence for everything above: task e8db84ba, 2026-09-03T01:36Z.
