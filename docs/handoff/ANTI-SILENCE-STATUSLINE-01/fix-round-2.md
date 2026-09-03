# ANTI-SILENCE-STATUSLINE-01 — fix round 2 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh

Four commits, HEAD `8ad022f`. Full report: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r1.md`
— read it. Verdict: 4 Critical + 5 High.

**Accepted, do not redo:** requirement 1 (lanes first) is genuinely met and mutation-proven — the
reviewer's ordering mutation went RED with 2 failures. Requirement 4 (quotas yield to lanes)
holds. The four widths do differ now; that is real progress over the previous round, where 80 and
200 columns were byte-identical.

**Correction to the brief you were given:** its `LANE_WRITES` named
`plugins/leadv2/scripts/tests/run-all.sh`, which does not exist. You correctly edited
`tests/run-all.sh`. That was my error, not yours. The header above is fixed.

Everything below is a claim this round made that measurement contradicts.

## [Critical] F1 — the field-boundary fix has no control

The reviewer removed the backoff twice — in the tail (`leadv2-lane-status-line-tail.sh:1098`) and
independently in the composer (`leadv2-lane-status-line.sh:216`) — and **both mutations stayed
`pass=14 fail=0`**. It is not a dead branch: instrumented, the clamp fires 6× per suite run,
including once at width 80, the exact width R12 inspects.

The reason R12 cannot see it: its glob `*·[a-z?]·[0-9]*` accepts any prefix before the first `·`,
so a slice that leaves the `·arm·age` tail intact still matches. R12 is therefore decorative — the
assertion this whole finisher round was dispatched to add. Rewrite it so it fails when the cut
lands inside a token, and prove it by removing the backoff and showing RED.

## [Critical] F2 / F3 — the budget is exceeded by its own marker, and the marker lies

A real render at `COLUMNS=60` produced **63 visible characters** — over budget by the width of the
`+N` marker itself, which is added after the budget is spent. And it reported `+3` where **5 lanes
were actually hidden**: the ` +2` that `emit_oneline` already appended upstream is counted as one
lane by the `tr -s ' ' | grep -c` arithmetic.

Both halves matter. An over-budget line is the mid-word truncation problem returning by another
door, and a dropped-count that undercounts tells the founder fewer lanes are hidden than really
are — on the one surface whose job is to say what is running.

## [Critical] F4 — a silent lane is skipped and a healthy one takes its slot

`leadv2-status-surface.sh:~1707` uses `continue`, not `break`. The sort correctly puts silent
lanes first, but the greedy fitter then **skips an unfittable silent lane and admits a later,
shorter live one**. Measured at W=30 and W=34: the only lane on the line is a healthy one.

That is the founding incident reproduced — the founder looking at his statusline and not seeing
the lane that died. Requirement 2 says a silent or dead lane is the most prominent field on the
line; a fitter that can drop it in favour of a live lane violates it at every narrow width. If a
silent lane cannot fit, it must still be represented — truncate its label, not its existence.

## [High] the remaining five

In `review-r1.md`, with file:line and scenarios. They are yours; fix or dispute each with
evidence.

## CI selection is unproven, not met

The reviewer could not complete `tests/run-all.sh --scope changed` (exceeded 120s in a scratch
clone), so the three new `EXTRA_SUITE_MAP` rows are read-verified only. Run it yourself with a
longer timeout and paste the output naming the three suites.

## Rules

- Every fix keeps its negative control and you RUN it: mutation INSIDE the function body, RED,
  revert, GREEN. Paste both runs and leave the RED output in the handoff dir.
- **An assertion that survives its own mutation is not a control.** F1 is exactly that; do not add
  a second. After writing each assertion, break the code it guards and confirm it goes red.
- Measure visible width with escape sequences and non-ASCII excluded — the base text carries
  Cyrillic and `·`.
- `git add <file> <file>`, never `git add <dir>`: a sibling lane committed 15 control-plane files
  that way today.
- Commit before you stop.

## Done means

Suite green with every assertion mutation-proven, lane clean of source changes, commit shas
reported, one line per finding fixed-or-disputed, `--scope changed` output pasted, and a re-run
render at 30, 34, 60, 80, 120 and 200 columns showing: no line over budget in visible characters,
an accurate `+N`, and a silent lane present at every width.
