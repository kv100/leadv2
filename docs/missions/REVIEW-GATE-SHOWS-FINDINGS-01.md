# MISSION — REVIEW-GATE-SHOWS-FINDINGS-01 (the gate hides the very thing it was asked for)

Work in `~/Projects/leadv2` — this is the plugin's own repo, the single source. Do not edit any
consuming project's copy.

## The defect, with today's evidence

`leadv2-review-run.sh` writes `docs/handoff/dispatch-<id>/review-gate.md`. On a passing review it
writes three lines:

```
status: pass
reviewer: glm
diff: ac209434
```

and on a failing one it adds counts:

```
status: fail
critical: 0
high: 1
medium: 1
low: 2
```

**Neither form contains a single finding.** A lead who reads only the gate — which is what the
gate exists for — learns that something is wrong but not what. Every time, the lead must then
open `review-<arm>.md` by hand and read the whole report, which is exactly the reading the gate
was introduced to make unnecessary.

Three real cases from persona-engine on 2026-08-14, all of which the gate hid:

1. `PASS_WITH_NITS` with three Mediums, one of which (a stale `stop_reason` mirror on
   request-failure paths) meant the observability seam being shipped could lie in precisely the
   failure case it was built to diagnose.
2. `status: pass` on a lane whose reviewer ended with **"do not merge as-is"** — a proven Medium
   where a glob symlinked over git-tracked files, so future commits to them would silently never
   reach the server. The gate said `pass`. Nothing else.
3. `status: fail high: 2` on a lane whose two Highs were "the report can never produce output on
   live data" and "the regexes cannot match the real log format" — both about the same script, and
   both invisible from the gate.

Case 2 is the serious one: a lead trusting the gate would have merged a lying-green defect into
the very task built to eliminate lying-green defects.

## What to build

Make `review-gate.md` carry the findings themselves, not only their counts. At minimum, for every
Critical and High, and for any Medium the reviewer marked as blocking: a one-line summary, the
file and line it anchors to, and the reviewer's verdict on it.

Two things matter more than the format:

- **A reviewer's explicit "do not merge" must reach the gate as a distinct state.** Today a
  reviewer can write `PASS_WITH_NITS` and then say in prose that the diff must not land, and the
  gate reports `pass`. Whatever you call it, that must be machine-visible.
- **Never truncate a Critical or High to a count.** If the gate must stay short, drop Lows first;
  a High that is only a number is the whole defect restated.

The reviewer report is written by many different arms (codex, glm, sonnet, opus) whose markdown
shapes differ. Say plainly what happens when the findings cannot be parsed out of a given report:
the gate must degrade to "could not extract findings — read review-<arm>.md", never to a silent
`pass` with no findings shown. A parse failure that looks like a clean review would be this same
bug with extra steps.

## Hard constraints
- The gate's verdict semantics stay as they are. This changes what the gate SHOWS, not what it
  DECIDES; no diff becomes mergeable that was not mergeable before.
- Plugin repo only. Nothing under a consuming project.
- Content becomes permanent only when committed here.

## Evidence required
Run the changed gate against the three real reports named above — they are on disk at
`~/Projects/persona-engine/docs/handoff/dispatch-{9573bd97,95eb1cb9,82e1056d}/` — and paste the
`review-gate.md` each one now produces. A gate that only works on a fixture has not been tested.
Report to `docs/missions/REVIEW-GATE-SHOWS-FINDINGS-01.report.md`. End with DELIVERABLE_COMPLETE.
