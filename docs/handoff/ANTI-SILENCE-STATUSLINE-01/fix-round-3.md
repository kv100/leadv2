# ANTI-SILENCE-STATUSLINE-01 — fix round 3 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh

Five commits, HEAD `fe203b3`. Full report:
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r2.md`. Read it.

**Accepted:** F1 is FIXED and mutation-proven — removing the tail backoff now goes RED
(`pass=14 fail=1`), and disabling the composer refit goes RED with 3 fails. The composer renders
exactly at budget for 30/34/60/80/120/200. CI selection is run-verified: all three
`EXTRA_SUITE_MAP` rows fire. That is real.

Everything below is measured, and the first item is the founding incident again.

## [Critical] F4 — a `done` lane still takes the narrow slot from a `dead` lane

`break` and first-row preservation are genuinely mutation-proven (MUT-A/MUT-E go RED). But the
rank is `rank = (cls == "live") ? 1 : 0` with an **unkeyed `sort`**, so `done` and `dead` share
rank 0 and tie-break arbitrarily. Measured at W=26/30/34/40/50/60: `lanes 3: …·done·9m +2` — a
finished lane occupies the only visible slot while a **dead** lane is hidden behind `+2`.

The whole surface exists to answer one question: *did a lane die?* A finished lane is the least
urgent thing on the board and it is currently outranking the most urgent. Rank explicitly by
urgency — dead first, then silent/stale, then live, then done — and make the sort total (add a
deterministic tiebreaker) so the order cannot depend on input sequence. Control: a fixture with
one `dead` and one `done` lane at W=26 must show the `dead` one.

## [High] N2 — the round's own rule broken twice: two fixes with no control

MUT-B (surface `marker_len=0`) and MUT-C (composer `_surf_marker=""`) **both survive green**. And
MUT-C renders **64 visible characters at COLUMNS=60** — that is r1's F2 restored by deleting a
single assignment, with no assertion anywhere able to see it. Add controls that fail when each
marker length is zeroed.

## [High] N3 / F3 — the tail measures bytes and cuts characters

`leadv2-lane-status-line-tail.sh` measures with `awk '{print length}'` (bytes: 8 for a Cyrillic
character) and cuts with `${#}` (chars: 5). You fixed this exact bug in the *test helper* in this
same commit and left it in production. That is what F12 was.

Consequence, measured: `TAILCLAMP W=80 … REST=[ 6·?·6s 7·?·7s +5] DROPPED_N=3` — seven lanes
hidden, `+3` printed. The composer's counts are exact; the tail's are not. Fix the tail to measure
in characters, excluding ANSI, and make its dropped-count exact. Control on both halves.

## [High] F2 — off-budget at W=22

An unconditional trailing space plus a negative-slack clamp yields **23 visible chars at
COLUMNS=22**. The fix has no control. Add one, and cover the degenerate narrow widths (20-28) that
the current fixtures skip.

## [High] F5 / F7 / F8 — not fixed

- F5: the base is still raw-sliced mid-word, and the slice loses colour (a cut inside an ANSI
  sequence).
- F7: the `width` assertion still allows 22 characters of slack because it measures ANSI bytes.
- F8: a clean checkout still reports `pass=15 skip=1` — the skip is inert and protects nothing.

## [Medium] N5, N6, F9

- N5: the shrink loop seeds at `…` and only ever shrinks, wasting 10-14 columns at W=30/34 while
  destroying the lane name. Seed at the full label and shrink toward the budget.
- N6: this diff newly puts `test-status-surface.sh` — currently **21 failures** — on the blocking
  path for its own writeset, so `run-all` is `4 passed, 2 failed`. Either fix that suite or state
  plainly, with evidence, that its failures pre-date this lane and are out of scope; do not leave
  CI red and unexplained.
- F9: 112-117 ms per render, and this round added a second `sed`. This script runs on every
  statusline render — keep it lean.

## Rules

- **Every fix gets an assertion that fails when the fix is removed, and you RUN it.** Three fixes
  this round shipped without one; that is the same failure the previous round was sent back for.
- Measure visible width in CHARACTERS, excluding ANSI escapes. Bytes are not width here.
- Never cut inside an ANSI escape sequence.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

Every assertion mutation-proven (paste RED and GREEN for each, RED logs under
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/round3-red/`), `run-all --scope changed` green or its
redness explained with evidence, lane clean of source changes, and renders at
20/22/26/30/34/60/80/120/200 with the visible-character count of each — showing no line over
budget, an exact `+N`, and a **dead** lane present and first at every width.
