# MISSION — REPORT-ONLY-MISSIONS-01 (an analysis lane's work is thrown away because it has no diff)

Work in `~/Projects/leadv2`. This is the plugin's own repo.

## The defect, with two of today's incidents

`leadv2-review-run.sh` gates a lane on its **diff**. A lane whose deliverable is a report — a
diagnosis, a measurement, an architecture verdict — produces no diff, so the gate returns:

```
status: blocked
reason: no_work
base: HEAD
```

and the dispatcher records a terminal. The analysis itself is sitting on disk, or was never
written, and nobody looks again.

It happened twice today on persona-engine:

1. `197a95d3` wrote a genuinely good diagnosis and the gate declared `no_work / empty_diff`. It
   was nearly discarded.
2. `d44ddd50` (the op-concurrency analysis — "can the engine reach 60 comments/day at all") was
   dispatched **three times**. Every time the gate said `no_work`, and no report ever appeared at
   `docs/handoff/OP-CONCURRENCY-01/report.md`. The lead eventually stopped delegating it. Three
   dispatches, zero output, and the gate reported the same thing whether the worker wrote a
   brilliant report or did nothing at all — which is the real damage: **`no_work` cannot
   distinguish "analysis lane finished" from "worker died".**

## What to build

A report-only lane must be gated on its **deliverable file**, not on a diff. Concretely:

- A mission must be able to declare that its deliverable is a file at a given path. Decide how —
  a field the dispatcher reads, a convention in the mission, whatever fits the existing shapes —
  and say why you chose it.
- For such a lane the gate passes when that file exists and is non-trivial, and fails when it does
  not. **`no_work` must stop being a possible verdict for a lane that declared a deliverable** —
  the two states that matter are "the report is there" and "it is not", and today those look
  identical.
- A lane that declares no deliverable keeps today's diff-gated behaviour exactly.

Think about what "non-trivial" means and defend it. A file that exists but says "I could not
determine this" is a legitimate report and must pass; a zero-byte file or an unfinished stub must
not. Do not invent a quality judgement of the content — that is the lead's job, not the gate's.

## Hard constraints
- Do not weaken the diff gate for code lanes. This adds a second shape; it does not relax the
  first.
- Plugin repo only.

## Evidence required
Two runs against real fixtures: a report-only lane that wrote its deliverable (passes) and one
that did not (fails, with a reason that names the missing path). Show the old behaviour on the
same fixtures for contrast. Report to `docs/missions/REPORT-ONLY-MISSIONS-01.report.md`. End with
DELIVERABLE_COMPLETE.
