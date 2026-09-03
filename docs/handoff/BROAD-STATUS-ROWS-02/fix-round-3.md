# BROAD-STATUS-ROWS-02 — fix round 3 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh,plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh,tests/run-all.sh

Three commits are in the lane, ending at `b9a1e62`. Full report:
`docs/handoff/BROAD-STATUS-ROWS-02/review-opus-r2.md`. Read it — the Mediums and Lows are there
and are yours.

**Accepted, do not redo:** all four prior Critical/High findings are genuinely fixed at runtime.
The reviewer produced five in-body RED/GREEN mutation pairs and every one reverts green
(identity 9/9, blind 9/9, founder 2/2). The Critical is verified by run: 7 own + 1 foreign now
renders `persona-engine/FOREIGN-01` with correct hidden arithmetic `8−6=2`.

What failed is what the fix introduced. The reserve logic swapped the old bug for its inverse.

## [High] `:637-644` — foreign rows are EXEMPT, not reserved

Ten foreign lanes render a ten-row founder table. Foreign row count is unbounded by construction
(`leadv2-lanes-snapshot.sh:411-471` applies no cap and no status filter). A reserved slot is a
bounded slot; an exemption is no cap at all. Give foreign rows a bounded reservation and let the
surplus fall into the hidden count like everything else.

## [High] `:636` — the junk-lie, inverted onto the founder's own board

`max(0, 6 − foreign)`: six foreign lanes evict all seven own-repo lanes, and the founder is told
`7 мусорных/лишних строк таблицы`. That is the exact sentence this task exists to delete, now
pointed at his own repo. Neither side may be starved: reserve a floor for each, and when both
exceed it, split the cap and report the hidden count honestly per side.

## [High] `:227-229`, `:405` — the rescued foreign row wears an own-repo lane's identity

The foreign row joins own-repo `lane_detail` on a **bare** task_id, so it renders the own lane's
`stream_bytes=55` and its mission title. Consequence measured: a foreign lane silent for an hour
displays as `пишет сейчас`. That is worse than the row being missing — it is a false liveness
claim on the one surface whose job is to say whether a lane died. Join on `(repo, task_id)`, the
same key the dedup already uses. The round's own T4 passes on this, so T4 is not a control for it
— fix the assertion too.

## [High] `tests/run-all.sh:120-121` — the Critical's only control is not selected by CI

Blind `T5a` is the sole control for the cap fix and has no `EXTRA_SUITE_MAP` row. Replaying
`--scope changed` for a lone `leadv2-broad-status.sh` edit selects the other two suites and not
that one. Add the row and prove selection with `--scope changed`, pasting the output.

## [Medium] `:501-515`, `:890-891` — the digest still keys on the bare task_id

Three foreign lanes render beside `+0 линии подняты`. Same key fix as above.

## Also outstanding

- **L1** `:371-373` — missing `isinstance` guard. Not fixed.
- **L2** — dedup drops are uncounted. Not fixed.
- **L3 recurred**: no RED artifact, no before/after render, no developer deliverable in the
  handoff dir, though the round-2 brief demanded all three. The reviewer had to manufacture the
  controls again. This is the third round it has been asked for.
- The identity suite header still documents 3 tests for 6, and still carries the unbacked claim
  that "each T is proven with a RED/GREEN pair". Either make it true or delete it.

## Rules

- Every fix keeps its negative control and you RUN it: mutation INSIDE the function body, RED,
  revert, GREEN. **Leave the RED output on disk** in `docs/handoff/BROAD-STATUS-ROWS-02/`.
- Do not weaken an assertion to make a fix pass. T4 above is an assertion that must get stricter.
- Commit before you stop. The previous two rounds both died with work uncommitted and the lead
  picked it up by hand.

## Done means

Lane clean of source changes, commit shas reported, one line per finding saying fixed or
disputed-with-evidence, RED artifacts on disk, `--scope changed` output pasted, and a rendered
before/after for three fixtures: 7 own + 1 foreign; 10 foreign + 0 own; 6 foreign + 7 own.
