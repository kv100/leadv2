verdict: APPROVE
next_action: review_round_2

# BROAD-STATUS-ROWS-02 — fix round 5, developer full report

Source: `docs/handoff/BROAD-STATUS-ROWS-02/review-opus-r4.md` (main checkout). Two new Highs
(N4-1, N4-2), one High-with-control gap (three fixes shipped without a mutation control —
covers MU3 and MU6), and two Mediums (R3-3, R3-5). Lane worktree:
`.claude/worktrees/BROAD-STATUS-ROWS-02`, LANE_WRITES:
`plugins/leadv2/scripts/leadv2-broad-status.sh`,
`plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh`,
`plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh`. Only the first two were
touched; row-identity needed no change this round.

## [High] N4-1 — reserve arithmetic now yields when both sides fit

`leadv2-broad-status.sh:713-736`. Round-4's floor/reserve split special-cased only
`_own_row_count == 0`; every other case (including the normal 1-3-own board) fell into the
`else` branch and got capped to `FOREIGN_ROW_RESERVE` even when the total never exceeded
`TABLE_ROW_CAP`. Fix: when `_own_row_count + _foreign_row_count <= TABLE_ROW_CAP`, nothing
is competing for a slot, so `_foreign_slots = _foreign_row_count` (everyone renders, no
hidden-count sentence). The `own==0`/`foreign==0`/both-compete branches are unchanged.

Verified: reverting just this branch (restoring round-4's `elif _own_row_count == 0:` as the
first check) reds 12 assertions across the T10 matrix — every combo where total ≤ 6 but own
∉ {0}. RED log: `round5-red/N4-1-reverted.log`.

## [High] N4-2 — own=1..3 × foreign=1..5 matrix

`test-broad-status-lanes-blind.sh` T10: a generic `collector-own-foreign-matrix.sh` stub
reads `MATRIX_OWN_N`/`MATRIX_FOREIGN_N` from the environment; the test loops all 15 combos,
computes the expected own/foreign row counts and hidden-sentence presence from the same
floor/reserve formula, and asserts both per combo. 30 assertions total, all green. The
mission's headline case (2 own + 4 foreign → 6 rows, no "не поместилось") is combo
own=2/foreign=4 in this matrix — passes explicitly by name ("T10 own=2 foreign=4").

## [High] MU3 / MU6 — mutation controls for two round-4 fixes that shipped without one

Per the reviewer: MU3 (`if malformed_row_count:` → `if False:` at the table_prefix append,
:664) and MU6 (the round-robin `while`/`_repo_buckets` block → flat first-N slice, :776-795)
both survived green in round 4.

- **T9** (MU3 control): a fixture mixing one real own-repo row with two malformed rows.
  Asserts the table_prefix line's own distinctive wording (`НЕ ЧИТАЮТСЯ 2 строк(и) таблицы`)
  — text that exists ONLY at that append call site, so it can't be satisfied by the R3-3
  in-table rows added below. RED with MU3 applied: `round5-red/MU3-mutated.log` (T8b and T9
  both fail). GREEN after revert confirmed.
- **T11** (MU6 control): 3 foreign repos × 4 lanes + 7 own lanes, `FOREIGN_ROW_RESERVE=2`.
  Round-robin must give repo 1 (m3-market) and repo 2 (persona-engine) one slot each, never
  both to repo 1. RED with MU6 applied: `round5-red/MU6-mutated.log` (`m3-market=2
  persona-engine=0 respiro-ios=0`). GREEN after revert confirmed.

## [Medium] R3-3 — malformed rows are now named rows INSIDE the table

`leadv2-broad-status.sh` right after the main row-building loop: for each malformed
(non-dict) table row, append a synthetic row `| (строка N повреждена) | формат не читается |
НЕ ЧИТАЕТСЯ |` into `rows_out` (wording deliberately distinct from the table_prefix line so
T8c/T9 stay independently verifiable). Consequence: `live_lane_count` (`len(rows_out_full)`)
now counts these rows too, so the old `elif live_lane_count == 0 and malformed_row_count:`
branch in the empty-headline block became permanently unreachable — removed, replaced with a
comment explaining why. T8c/T8d added (named rows present, `(живых линий нет)` placeholder
absent when rows are merely unreadable).

## [Medium] R3-5 — comment corrected, not the sort

`leadv2-broad-status.sh:739-750`. The round-4 comment claimed the round-robin's per-repo
row order "is the liveness order the upstream rows already arrive in." Reviewer's fixture 7
showed that's false: `leadv2-lanes-snapshot.sh` sorts a repo's own foreign rows via
`sorted(session_by_task.items())` (session-key order, not recency), so a lane silent for
hours can rank ahead of one actively writing. `leadv2-lanes-snapshot.sh` is not in this
lane's LANE_WRITES, so implementing the recency ordering the old comment described is out of
scope — corrected the comment to state the actual limitation instead of a false guarantee.

## Suite results (foreground, this session)

- `test-broad-status-renderer-truth.sh`: 22 passed, 0 failed
- `test-broad-status-row-identity.sh`: 11 passed, 0 failed
- `test-broad-status-lanes-blind.sh`: **48 passed, 0 failed** (was 14; +34 from T8c/T8d/T9/T10×30/T11)
- `test-lane-pulse-founder.sh`: 2 passed, 0 failed
- `tests/run-all.sh --scope changed`: 10 passed, 2 failed — `run-core-offline.sh` and
  `test-broad-status-duty.sh` (28 passed/10 failed). Both pre-existing per the mission
  ("Not yours — do not fix"); duty.sh's 28/10 here matches the mission's stated baseline
  exactly. Neither file is in LANE_WRITES; neither was touched.

`bash -n plugins/leadv2/scripts/leadv2-broad-status.sh` and the test file: both OK.
`python3 -m py_compile` on the embedded python heredoc (lines 174-1199, extracted to a temp
file): OK.

## Left alone

- `test-broad-status-row-identity.sh` — no finding this round required a change there.
- `leadv2-lanes-snapshot.sh` — R3-5's actual liveness-sort fix belongs there; out of
  LANE_WRITES scope, documented as a limitation in the comment instead (see above).
- The `run-core-offline.sh` / `test-broad-status-duty.sh` failures — pre-existing, confirmed
  by the mission's own bisect; not touched.

Commit `7c5d52a` on `worktree-BROAD-STATUS-ROWS-02`. Working tree clean for the two touched
LANE_WRITES files. RED artifacts: `docs/handoff/BROAD-STATUS-ROWS-02/round5-red/` (worktree
copy) — `MU3-mutated.log`, `MU6-mutated.log`, `N4-1-reverted.log`,
`GREEN-final-lanes-blind.log`.

DELIVERABLE_COMPLETE
