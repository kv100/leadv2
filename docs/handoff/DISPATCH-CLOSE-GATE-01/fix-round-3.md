# DISPATCH-CLOSE-GATE-01 — round 3 (review said fail)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,plugins/leadv2/scripts/tests/fixtures/,tests/run-all.sh,.gitignore,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full report: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r2.md`. HEAD is `f06d325`; resume from it.

**Won in round 2 — do not redo.** The wiring control is real: deleting all three
`_mission_writeset_guard` call sites now gives `pass=16 fail=2`, restore → `18/0`. Round 1's exact
mutation is caught. Both real specimens behave: `fix-round-4.md` → rc=0, pre-correction
`fix-round-5.md` → rc=1 naming `lib/leadv2-lane-guard.sh`. The red-proof library semantics are
correct (two fixes / one RED artifact → exactly one `unproven`; a `0 failed` artifact does not
satisfy; rc=0 so the lane is never trapped).

Everything below is about the mechanisms not reaching reality.

## [Critical] Mechanism 2 looks in a directory that does not exist anywhere

`leadv2-dispatch-product-close.sh:3237` passes `HANDOFF` = `docs/handoff/dispatch-<sig8>` (set at
`:180`), while `lib/leadv2-red-proof.sh:46` requires `<dir>/red`.

That path exists in **0 of 652** real dispatch dirs, and nothing in the repo creates it. The actual
convention — used by every lane today, including this one — is
`docs/handoff/<TASK-ID>/roundN-red/` and `docs/handoff/<TASK-ID>/red/`.

So the gate fires on 4 of 652 dirs, and all four are false positives: it reads `## [Critical]`
headings out of `lane-mission.md` and calls them claimed fixes. One of the four is this lane's own
`dispatch-1c354714`, where the four "unproven fixes" are round-1's review findings quoted verbatim.

Resolve the artifact directory the way the repo actually names it, keyed on the founder task id, not
the dispatch sig. And distinguish a *worker's claim of a fix* from *a heading in the brief it was
given* — reading the brief's own findings back as claims is what produced 4/4 false positives.

## [Critical] the extractor would have parked this lane's own re-dispatch

A 149-mission sweep gives 6 refusals at **precision 3/6**. One false positive is this lane's own
`fix-round-2.md`: its `## Done means` quotes `` `lib/leadv2-lane-guard.sh` `` as *expected checker
output*, and the Done-means backtick scan reads it as a required write. With
`REQUIRE_MISSION_WRITESET` defaulting to 1, dispatching that very brief would have been refused.

The founder's own framing: a false positive here gets the mechanism switched off permanently. Half
the refusals being wrong is not shippable. Distinguish a path the mission requires the worker to
*produce* from a path it merely *names* — as an example, as expected output, as evidence to read.
Re-run the 149-mission sweep and report the new precision; it must be 6/6 or the extractor stays
off by default.

## [Critical] the downgrade has no control

Removing **all five** `${_pc_unproven_suffix}` interpolations from the `_dl_note` calls — the entire
user-visible effect of Mechanism 2 — leaves both suites at `14/0` and `18/0`, because
`_extract_c5_block` slices only to the first `fi`. The library is tested; the thing the founder
would actually see is not. Add a behavioural assertion on the rendered close note, and prove it RED
by removing the suffix.

## [Critical] the specimens are gitignored and untracked

`.gitignore:40` excludes them, so the two load-bearing assertions hard-`fail` on any other checkout.
A control that only works on this machine is not a control. Track the specimens (add a
`tests/fixtures/` path and un-ignore it) and verify with `git ls-files` that they are committed.

## [High] the unguarded `source` breaks the three consumer repos

`leadv2-dispatch-product-close.sh:36` sources `lib/leadv2-red-proof.sh` resolved against the
consumer repo's own dir. In `persona-engine`, `m3-market` and `respiro-ios` the scripts are per-file
symlinks and that lib does not exist there — so this breaks the close path in every repo that is
not `leadv2`. Guard the source, or resolve it against the canonical plugin dir.

## [High] carried C4 — `--scope changed` still selects nothing on a real dirty lane

`run-all.sh:133-135` treats a docs-only dirty set as "the changed set", so the widened `lib/*.sh`
glob and both new `EXTRA_SUITE_MAP` rows are unreachable in the situation they exist for. Fix the
selection so a lane's docs-only dirt does not shadow the committed source range, and prove it from
the real dirty lane.

## [High] a test writes into the production scripts dir

`test-mission-writeset.sh:198` drops a full dispatcher copy into the production scripts directory.
This repo's single-source rule forbids a second real copy of a plugin-owned file — that is the
defect class that cost a whole day in July. Use a temp dir.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round3-red/`.
- The 149-mission sweep is now a required artifact: paste precision before and after.
- No `grep` against script source as an assertion; no negated command as an assertion; no control
  whose pre-image is `git show HEAD:`.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

The red-proof gate reading the directory the repo actually uses, with 0 false positives over the 652
dispatch dirs; extractor precision 6/6 on the 149-mission sweep; a behavioural control on the
rendered `unproven` note that goes RED when the suffix is removed; the specimens tracked in git; the
`source` guarded so the three consumer repos still close; `--scope changed` selecting both suites
from the real dirty lane; and no test writing into the production scripts dir.
