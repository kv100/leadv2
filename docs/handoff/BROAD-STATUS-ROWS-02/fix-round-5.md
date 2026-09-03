# BROAD-STATUS-ROWS-02 — fix round 5 (review said FAIL / do_not_merge; small round)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh,plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh

Nine commits, HEAD `1ea7be5`. Full report:
`docs/handoff/BROAD-STATUS-ROWS-02/review-opus-r4.md`.

**This round is nearly done.** The reviewer re-ran everything and confirmed: renderer-truth 22/0,
row-identity 11/0, lanes-blind 14/0, founder 2/0. **R3-1 is FIXED and the re-specified assertion
was made STRONGER, not weakened** — parsed-column equality, in its own commit, with the other
assertion bodies untouched. That is exactly what was asked. **R3-4 is FIXED**, all three
mutations reproduced independently from your `round4-red/` artifacts. All eight `EXTRA_SUITE_MAP`
rows select, replayed. Everything else this round is landable and should be kept.

Two new Highs and two loose ends. Then this lane closes.

## [High] N4-1 — the reserve arithmetic still lies on the everyday board

`leadv2-broad-status.sh:703-711` special-cases only `own == 0`. So **2 own + 4 foreign = 6 lanes
against a cap of 6 renders 4 rows** and prints `2 чужих строк не поместилось`.

Six lanes, six slots, and it drops two — then tells the founder they did not fit. WIP is 2 lanes
per session, so `own` in the 1–3 range **is the normal board**, not an edge case. Make the
arithmetic general: when total ≤ cap, every row renders and nothing is reported hidden. The floor
only binds when the two sides genuinely compete.

## [High] N4-2 — the suite defends a shape it never tests

`T5`/`T6`/`T7` use `own ∈ {0, 7}`. There is no fixture anywhere in the 1–3-own range, which is
why N4-1 shipped green. Add fixtures at own=1, 2 and 3 crossed with foreign=1..5, and assert both
the rendered row count and the hidden-count sentence.

## [High] three fixes shipped without a control

Of the reviewer's nine in-body mutations, six were caught and **three survived green**:
- **MU3** — the degraded prefix line.
- **MU6** — the round-robin allocation.
Give each an assertion that fails when the fix is removed, and paste the RED run.

## [Medium] R3-3 — the lie is gone, the remedy is half-built

`⚠ ДОСКА ПУСТА` no longer appears for a malformed table: good. But the degraded row is still only
a prefix line, and the table itself still prints `(живых линий нет)` beneath it. A malformed row
must appear as a NAMED row inside the table, so a reader counting rows sees it.

## [Medium] R3-5 — the code comment at `:727-733` states the opposite of what the code does

Fixture 7 shows two lanes silent for six hours taking both reserved slots ahead of two actively
writing ones, while the comment claims liveness ordering. Either implement the ordering the
comment describes — silent-but-recent ahead of long-dead, actively-writing never starved — or
correct the comment. A comment that contradicts its code is a trap for the next reader.

## Not yours — do not fix, do not let it block you

`test-broad-status-duty.sh` is red at HEAD (28/10) but **strictly better than the anchor**
(24/14), and `run-all.sh` is red in every scope for pre-existing reasons (foreign-lanes 5/3,
glm-ladder FAIL=1) — identical at `d4f5408`. Confirmed pre-existing by bisect. Leave them; say so
in your report.

## Rules

- Every fix keeps a control you RUN: mutation inside the function body, RED, revert, GREEN. Leave
  the RED logs in `docs/handoff/BROAD-STATUS-ROWS-02/round5-red/`.
- Do not weaken an assertion. R3-1 showed the right way: re-specify deliberately, in its own
  commit, and make it stronger.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

All four suites green, fixtures covering own=1..3 × foreign=1..5, MU3 and MU6 each with a control
that fails, lane clean of source changes, one line per finding fixed-or-disputed, and the
rendered table for 2 own + 4 foreign showing **six rows and no "не поместилось" sentence**.
