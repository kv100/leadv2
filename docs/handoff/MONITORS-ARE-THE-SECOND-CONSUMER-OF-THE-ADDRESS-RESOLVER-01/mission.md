# Mission: MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01

Repo: `~/Projects/leadv2`. Read `docs/handoff/MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01/brief.md`
IN FULL first — it carries the measured watcher census and the two-sided controls.

## §0 is now UNBLOCKED — but re-check it yourself, do not take my word

The brief's §0 says the resolver is absent from `main`. That was true when the brief was
written; it is no longer. The address-resolver branch was merged into `main` a few minutes
before you started. Re-run the brief's own stop-check before any work:

    grep -rln 'leadv2-lane-address.sh\|lane_address_' --include='*.sh' plugins/leadv2/scripts/

If it is EMPTY: stop and say so — the merge did not land and the premise is false again.
Do NOT write a second resolver alongside. If it is non-empty, the block is lifted; record
what you measured, not what this line claims.

## The defect

Observation surfaces address a lane by **dispatch-sig** (`docs/handoff/dispatch-<sig8>/`),
while the product is written under the **founder id** (`docs/handoff/<TASK-ID>/`). Both
directories are legal and no surface knows about the other. So a watcher reports "the lane
produced nothing" for 55 minutes while the report sits one directory over, and the lead
declares the worker dead and re-dispatches. That cost four of five streams on 2026-09-03.

It lies in BOTH directions: a watcher condition globbing `docs/handoff/dispatch-*/*.full.md`
matched a FOREIGN lane's report and produced a false "done". A false yes is more expensive
than a false no, because a lane gets closed on it.

## The work

Make the watchers consume `plugins/leadv2/scripts/lib/leadv2-lane-address.sh` instead of
hand-rolling `dispatch-<sig8>` paths. Candidates measured in the brief's §2 — verify each
count yourself before touching it, and check whether `leadv2-lane-watch-v2.sh` is already
immune (it documents independence from `*.stream.jsonl`) rather than assuming it is not.
Scope is whatever the census actually supports; say what you left out and why.

## Acceptance — a suite plus TWO named negative controls

1. A suite that keeps the real watcher function under claim and fakes only one level lower.
   A test that stubs the function it claims to cover proves nothing.
2. Control A (false NO): with the fix reverted, a lane whose product lands under the founder
   id must make the watcher report emptiness — and the suite must go RED naming it.
3. Control B (false YES): a foreign lane's report must not satisfy the watcher's condition
   for this lane — mutate and show the suite goes RED naming it.
   Insert each mutation INSIDE the function body in a scratch worktree; a line-number insert
   that lands at top level reddens everything for the wrong reason and reads as a pass.
4. The suite must be SELECTED by CI. Add the `# run-all-triggers:` self-declaration and prove
   selection with `tests/run-all.sh --scope changed`. A green suite CI never runs is worth
   nothing.
5. Report the suite's final count line verbatim. If it prints no count line, SAY SO — a suite
   that halts early under-counts its witnesses and a partial result reads like a complete one.

## Hard constraints

- NEVER `git add -A` anywhere in this repo or its worktrees — the shared tree carries other
  sessions' uncommitted work, and six times last night finished work was found sitting in a
  tree under an empty branch. Stage only your declared file set, by name.
- Never commit: `docs/leadv2/active.yaml`, `bus.jsonl`, `merge-queue.jsonl`, `open-threads.md`,
  `.bus-offsets`, `.bus.lock`, `.merge.lock`, `active.yaml.lock`, `questions`,
  `docs/LEAD_V2_STATE.md`, `tasks/*/journal.md`, foreign `phases.d`.
- Never `reset --hard` / `clean` / `stash` in the shared tree.
- Do not merge your branch. The lead merges.
- Suite runs are gated on machine state: run only while the 1-minute load is under ~12, and
  NEVER run a core suite while another live lane is inside its own e2e gate — that overlap
  killed five lanes on 2026-09-04. Your own suite is fine; the core suite is not.

## Deliverable

`docs/handoff/MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01/report.md`:
what you measured (§0 re-check, the census re-count), what you changed, the suite's verbatim
counts, both controls with their verbatim reds, and the CI-selection proof. Then commit your
declared set on your lane branch and print DELIVERABLE_COMPLETE.
