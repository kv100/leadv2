# BROAD-STATUS-ROWS-02 — fix round 4 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh,plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh,plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh,tests/run-all.sh

Four commits, HEAD `23cada2`. Full report:
`docs/handoff/BROAD-STATUS-ROWS-02/review-opus-r3.md`. Verdict: 4 High + 3 Medium.

**Accepted, do not redo** — the reviewer re-ran everything and confirmed: suites are honest
(identity 10/0, blind 11/0, founder 2/0); the repo-keyed detail join, the own-repo floor, the
`EXTRA_SUITE_MAP` selection (replayed), L2 and three more are **genuinely FIXED**, with MX-1/2/3
red-then-green. `round3-red/` finally carries real RED artifacts. That is the first round on this
lane where the fixes held under an independent mutation.

Four things remain.

## [High] R3-1 — you broke a suite four commits ago and CI could not tell you

`plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh` went **22/0 → 16/6 at
`c0fe726`** and is still red at HEAD. Nobody noticed because six suites that read the renderer
have no `EXTRA_SUITE_MAP` row — CI is silent on all of them.

The root cause is a real contract clash, not an accident: that suite's `:281` asserts *"col-1 is a
human name, never a hex id"*, and this task deliberately inverted that — the whole point of
`BROAD-STATUS-ROWS-02` is that column 1 carries lane IDENTITY (task_id, sig8 fallback) while the
human title moves to "Что делает".

So the old assertion is the one that must change — **deliberately, in its own commit, with the
reason in the message**, not by weakening it into vagueness. Then add the missing
`EXTRA_SUITE_MAP` rows for all six renderer-reading suites, and prove selection with
`--scope changed`. A suite that can go red for four commits without CI noticing is the same
lying-green disease this task exists to cure, one level up.

## [High] R3-2 — the under-fill: 4 empty slots and a claim that 8 rows did not fit

10 foreign + 0 own renders **2 of 6 rows** and prints `8 строк таблицы не поместилось` while four
slots sit empty. Blind `T6`'s `-eq 2` locks the under-fill in, so the assertion is defending the
bug. The reservation must be a floor, not a ceiling: when one side has no rows, the other takes
the whole cap. Fix `T6` to assert the cap is FILLED whenever enough rows exist, and make the
hidden count equal to what was actually dropped.

## [High] R3-3 — the L1 guard resurrects the false-empty-board lie

The `isinstance` fix at `:211` **deletes non-dict rows uncounted**, so a malformed collector table
now renders `⚠ ДОСКА ПУСТА`. Measured. That is LANE-DETAIL-BLIND-01 verbatim: "no lanes" and
"could not read the lanes" collapsing into one indistinguishable output, which the original brief
named as the thing that must never regress. A malformed row is unreadable, not absent — count it
and render it as a named degraded row.

## [High] R3-4 — three fixes with no negative control

MX-4 (digest key), MX-5 (L1 filter) and MX-6 (hidden-count wording) all revert with **zero suite
failures**. Give each one an assertion that fails when the fix is removed, and paste the RED run.

## [Medium] the three

- Foreign slots are allocated **alphabetically**, not by liveness or repo, so a whole repo can be
  permanently invisible while another is always shown. Allocate by liveness first, then round-robin
  across repos.
- Per-side hidden counts are computed at `:701-703` and then discarded.
- The commit message overclaims: "degrades instead of crashing" is false, and two of the four RED
  logs are not suite reds. Say only what the runs show.

## Rules

- Do not weaken an assertion to make a fix pass. R3-1 and R3-2 both require changing an assertion
  — do it deliberately, each in its own commit, with the reasoning in the message.
- Every fix keeps a control you RUN: mutation inside the function body, RED, revert, GREEN. Leave
  the RED output in `docs/handoff/BROAD-STATUS-ROWS-02/round4-red/`.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

All renderer suites green (`test-broad-status-renderer-truth.sh` back to 22/0 or its assertion
deliberately re-specified), six `EXTRA_SUITE_MAP` rows added and `--scope changed` output pasted,
lane clean of source changes, one line per finding fixed-or-disputed, and the three fixtures
re-rendered: 7 own + 1 foreign; 10 foreign + 0 own (must fill the cap); 6 foreign + 7 own.
