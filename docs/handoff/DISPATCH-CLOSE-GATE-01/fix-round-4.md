# DISPATCH-CLOSE-GATE-01 — round 4: as it stands, merging this kills the dispatcher in three repos

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,plugins/leadv2/scripts/tests/fixtures/,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full report: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r3.md`. HEAD is `70b7749`.

**Verified working, do not redo:** the specimens are tracked in git; `--scope changed` selects from
the dirty lane; the test no longer writes into the production scripts dir; and both round-2 wins
still hold (deleting the three `_mission_writeset_guard` call sites gives 16/2; the two real
specimens behave).

**Read C1 first. Nothing else in this lane matters until it is fixed.**

## [Critical] C1 — the unguarded `source` kills the dispatcher outright in three repos

`leadv2-dispatch-code.sh:459,461` source the two new libs by a path that resolves against the
*consumer* repo. In `persona-engine`, `m3-market` and `respiro-ios` the scripts are per-file
symlinks and those libs do not exist there, so the source fails; `set -e` arrives via
`leadv2-helpers.sh:10`, and the dispatcher exits `rc=1`. Traced live by the reviewer.

That is not a degraded feature — it is **the dispatcher not starting at all** in the repo this
session dispatches from. Merging this as-is would take the whole system down.

Guard both sources, or resolve them against the canonical plugin dir. Then prove it by running a
real dispatch from `persona-engine` — not by reading the path logic.

## [Critical] C2 — Mechanism 2 still scans a directory that holds nothing

Round 3 changed the resolution, but a live probe over the real tree shows **0 of 107 task dirs**
contain a worker claim where the gate now looks; probing `BROAD-STATUS-ROWS-02` directly returns
empty. So the gate still cannot fire on a real close.

Find where a worker's claimed fixes actually live — read a completed lane's artifacts and follow
what the close path really writes — then key the gate on that. Prove it by pointing the gate at
three completed lanes and showing it reads their claims.

## [Critical] C3 — the downgrade still has no control

Unwrapping **all five** `_pc_evidence_with_unproven` call sites — the entire user-visible effect —
leaves both suites at 19/0 and 18/0. This is the third round in a row that the only thing the
founder would actually see is untested. Assert on the rendered close note itself and prove it RED by
unwrapping.

## [Critical] C4 — extractor precision is 3/5, and the named false positive is unfixed

`fix-round-2.md:99` — the review's own named example — still refuses. And
`REQUIRE_MISSION_WRITESET` **defaults to 1**, so this ships enabled and would park correct
dispatches, including this lane's own.

Either reach 5/5 on the sweep, or default `REQUIRE_MISSION_WRITESET=0` and say so plainly in
`report.md`. A checker that refuses two correct missions in five is not ready to be on by default,
and the founder's own framing is that one false positive gets it disabled forever.

## [High] the artifacts do not support their claims

`round3-red/` is **missing entirely**, and `round2-red/` contains only **green** logs. An artifact
directory of passing runs is not evidence of a mutation being caught — another lane today shipped a
green run under a RED header, and that is now a hard failure of the round, not a nit.

Regenerate every artifact from a run whose exit status you assert, and make the artifact writer fail
loudly when the run it records did not go red.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion; no control
  mutating a scratch copy; no `git show HEAD:` pre-image.
- Bash 3.2.57 only — and check every `${arr[@]}` expansion is guarded under `set -u`. Another lane
  today shipped a guard that died on an unbound array and falsely rejected every good worker.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

A real dispatch from `persona-engine` succeeding with the new sources in place (output pasted); the
red-proof gate reading real worker claims from three completed lanes; a control on the rendered
`unproven` note that goes RED when unwrapped; sweep precision 5/5 **or**
`REQUIRE_MISSION_WRITESET=0` by default with the reason stated; and every artifact regenerated from
an asserted run.
