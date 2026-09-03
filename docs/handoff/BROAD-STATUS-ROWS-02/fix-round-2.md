# BROAD-STATUS-ROWS-02 — fix round 2 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-lanes-snapshot.sh,plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh,plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh,tests/run-all.sh

Your commit `c0fe726` is in the lane. The full report is
`docs/handoff/BROAD-STATUS-ROWS-02/review-opus.md` — read it; the Mediums and Lows are there and
are yours too. The reviewer ran the code, produced the RED artifacts your round did not, and
confirmed each finding by execution. Verdict: 1 Critical, 3 High, 4 Medium, 3 Low.

**What is accepted, so you do not redo it:** fix A is real at runtime, not lying-green — reverting
`linia = id_display` inside the loop turns the suite 1-passed/4-failed, and removing the dedup turns
T2 red. The CI wiring is clean: `--scope changed` selects the new suite. Keep both.

## [Critical] `leadv2-broad-status.sh:587-590` — requirement B is closed by claim, and the drop is still live

`TABLE_ROW_CAP = 6` keeps only the FIRST 6 rows (`rows_out = rows_out_full[:TABLE_ROW_CAP]`), while
`leadv2-lanes-snapshot.sh:1661-1690` **appends** foreign-repo rows to the end of the table, after
own-repo rows are ranked and capped. A cross-repo lane is therefore the systematic casualty of the
cap. Measured with 7 own lanes + 1 foreign `repo=persona-engine` lane: the foreign lane is absent
from the pulse and the founder is told `(скрыто: 2 мусорных/лишних строк таблицы)` — it is described
to him as junk.

This is defect B verbatim, untouched. Your commit message claims "verified via a live repro … that
the cross-repo merge itself already includes both own- and foreign-repo lanes" — that covers only
the MERGE, the repro is on disk nowhere, and the merge was never the failing stage. A cross-repo
lane must survive the cap: rank it, reserve it a slot, or raise the cap — but it may not be silently
cut, and it may never be counted as junk.

## [High] the dedup key ignores `repo`

`str(row.get("task_id") or "?")`: a foreign lane sharing a task_id with an own lane is silently
deleted although its rendered identity differs. Measured both ways. Key on the identity you actually
render, not on a fragment of it.

## [High] the same `or "?"` collapses every task_id-less row

Two lanes without a task_id become one; the second vanishes with **no degraded row**. That regresses
the `:203-213` lesson this task's brief called out by name — a lane that cannot be identified must
render as a named degraded row, never disappear. Measured.

## [High] identity prefers the dispatch id over the task_id

A lane with `task_id=BROAD-STATUS-ROWS-02` renders `| dispatch-9f3a1c22 |`, and the founder's own
task id appears in no column at all. Requirement A said the reverse: task_id first, sig8 only as the
fallback when task_id is absent. Measured.

## [Medium] T3b is not a control

It passes with the entire fix reverted, so the suite header's claim that "each T is proven with a
RED/GREEN mutation pair" is false, and no RED artifact exists in the handoff dir. Either make T3b
fail under its named mutation or delete the claim — do not leave a decorative assertion wearing a
control's label.

## [Medium] the closed-lane line lost its human name

`:519` now reads `Закрыто сегодня: dispatch-5b7d0e91 (pid gone)`. The identity belongs in "Линия";
the human name still belongs in the prose. Put it back.

## [Medium] you were asked to extend, not duplicate

The brief said extend `test-broad-status-lanes-blind.sh`; a new 215-line suite landed beside it, and
its fixtures (`task_id="dispatch-<hex>"`) are shaped so the identity-source bug above is invisible.
Reshape the fixtures so a real task_id and a dispatch id are distinguishable, and fold what belongs
into the existing suite.

## Rules for this round

- Every fix keeps its negative control and you RUN it: mutation INSIDE the function body, suite RED,
  revert, GREEN. **Paste both runs and leave the RED output in the handoff dir** — its absence is
  half of what failed this review.
- Do not weaken an assertion to make a fix pass.
- Do not claim a verification you did not leave on disk. The Critical exists because a commit
  message asserted a repro nobody can find.
- Commit before you stop. A round that ends with uncommitted edits in the lane produced nothing.

## Done means

`git -C <lane root> status --porcelain` shows only control-plane residue, commit shas reported, one
line per finding saying fixed or disputed-with-evidence, and a rendered before/after of the table for
a fixture with 7 own-repo lanes plus 1 foreign lane — the after must show the foreign lane.
