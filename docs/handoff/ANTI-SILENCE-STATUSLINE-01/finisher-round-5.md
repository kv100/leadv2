# ANTI-SILENCE-STATUSLINE-01 — round 5 finisher (resume, do not restart)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

The previous worker committed `c22e0da` ("wip: harden statusline rendering controls") and stopped
partway. **Resume from that commit — do not restart the round.** The full brief is
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-5.md` and the review it answers is
`review-r4.md`; read both.

## What is actually done

`round5-red/` contains exactly one artifact: `MUT-Z.log`. One of six.

## What is left

Five controls still owe a production RED and its GREEN, each written to `round5-red/`:

- **MUT-R** — full revert of the rank fix at `leadv2-status-surface.sh:1681-1688`. This is the
  founding incident: a dead lane losing its slot on the founder's statusline. It has survived two
  rounds of "fixed" and there is still no control naming it. If only one of the five gets done,
  make it this one.
- **MUT-B** (marker length sweep), **MUT-V** (tail dropped-count off-by-one), **MUT-U** (ANSI strip
  before base clip), **MUT-W** (`full_label_cap`).

Plus, still open from the round-5 brief:

- **F5** — `leadv2-lane-status-line.sh:289` still raw-byte-slices
  (`"${_base_out_plain:0:$_base_visible_budget}"`), producing `O`, `Opu`, `Opus 5 `. Fix it to be
  visible-width aware and regenerate `render-proof.md` — the current proof file ships the defect as
  its own evidence.
- **F9** — tail 99.6 ms / composer 89.6 ms against a ~60 ms bar (bare bash floor is 5.1 ms).
  Per-character forking is gone; `$( )` per token is not.
- **`--scope changed`** must select **both** suites from the dirty lane. `test-status-surface.sh`
  is currently unselected and red at baseline (22 failures) — fix the baseline too, or it can never
  grade anything.

## The one rule that this round exists for

**A mutation control must fail when the mutation is applied to production.** Round 4's controls
`sed`-ed a scratch copy and asserted the copy rendered badly — so when the fix was already absent
the `sed` no-op left the broken production output satisfying the assertion, and the control printed
`PASS` at exactly the moment it should have screamed. One of them even printed `AssertionError`
into its own log and passed.

So: apply each mutation to the production file, inside the function body; treat a zero-match `sed`
as a hard failure, never a skip; assert on real rendered output.

## Rules

- No `grep` against script source as an assertion. No negated command as an assertion (`set -e`
  ignores it).
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- **Commit before you stop.** If you run out of room, commit what works and say plainly which of
  the five controls are still missing — a partial commit with an honest list is worth far more than
  work left uncommitted in the lane.

## Done means

Six RED/GREEN pairs in `round5-red/`, one per mutation, each produced against production; F5 fixed
with a regenerated proof that does not contain the bug; render time under ~60 ms; both suites
selected by `--scope changed` from a dirty tree; `test-status-surface.sh` green at baseline.
