verdict: APPROVE
next_action: review_round_2

# MAIN-CORE-SUITE-RED-01 round 2 — developer full report

Full per-suite root-cause/fix/negative-control detail lives in
`docs/handoff/MAIN-CORE-SUITE-RED-01/report.md`. This file summarizes the
same work for the `/leadv2` subagent protocol.

## Method

Round 1 (`d2971b7e`) was rejected because the gate re-measures against a
**clean current-`main` base**, and all four suites were still red there.
Round 2 started by reproducing each suite against a real `git clone --local
-b main` (not `git archive main` — archives drop `.git`, which spuriously
breaks tests doing `git show <rev>:<path>`, e.g. test-injector-dedup's
golden-commit check). All four reproduced red, matching the mission's
description exactly.

Partway through, discovered this lane's own worktree carries files well
behind current `main` for several paths outside `LANE_WRITES` — `hooks.json`,
`leadv2-phase-record.sh`, and (critically) `test-phase-precondition.sh`
itself, ~218 lines behind. Running a suite directly in this lane's checkout
can therefore show spurious failures unrelated to any fix (stale
off-limits dependency), and naively copying this lane's stale test file
onto a fresh main clone would have reverted ~218 lines of unrelated main
history — the opposite of a genuine fix. To avoid that, every fix below was
built and verified against a fresh main clone, and for suite 4 specifically
the test file was re-synced from current `main` before applying the
one-hunk fix, so the actual diff against `main` stays a clean, minimal
change instead of an accidental revert.

## Suite 1 — test-idle-lead-guard.sh

Case 10 asserted a stale `hooks.json` Stop-array ordering contract that
ONE-LANE-WATCH-01 (`9f00e7ed`/`c49cc9fb`) obsoleted when it retired the
standalone `leadv2-idle-lead-guard.sh` Stop hook in favor of the self-arming
`leadv2-lane-watch-v2.sh`. Rewrote the assertion to match the current
contract (hook absent from Stop, promise-guard still present, lane-watch-v2
armed on SessionStart/disarmed on SessionEnd). rc 1→0, `PASS=19 FAIL=0`
against clean main. Negative control: re-adding the retired hook to
`hooks.json` reproduces the exact original failure; reverting restores
green.

## Suite 2 — test-injector-dedup.sh

The multisession negative control's `perl -0pi` mutation anchor was a
single-line literal that TERMINAL-LANES-STILL-READ-AS-LIVE-01 (`b8db6058`)
silently broke by rewriting the target comprehension across multiple
lines — the mutation became a no-op, so the "negative control" was
actually asserting nothing. Fixed the anchor to match across the line
break and added a `grep -q '\[:3\]'` guard so future anchor rot fails
loudly instead of silently. rc 1→0, `PASS=10 FAIL=0`. Also flagged (out of
`LANE_WRITES` scope, not fixed): a harmless backtick-in-comment bug in
`leadv2-user-prompt-context.sh` that prints spurious
`line 167: phase: command not found` to stderr on every invocation.

## Suite 3 — test-lane-diff-single-repo.sh

`_pc_lane_commits_ahead()` in `leadv2-dispatch-product-close.sh` could not
prove "zero commits" for a lane whose start-SHA/cache/origin are all
unresolvable — exactly the common case, since every lane is born with one
`--allow-empty "lane <id> anchor"` commit (T11-F2), which always keeps
`HEAD != parent HEAD` and defeats the existing prove-zero check. Added a
second prove-zero branch recognizing that specific birth-anchor shape
(parent of HEAD == parent repo's HEAD, subject matches `"lane "*" anchor"`,
empty diffstat). rc 1→0, `5 passed, 0 failed`. This is a genuine product
fix, not a test change — `leadv2-dispatch-product-close.sh` is in
`LANE_WRITES` and not on the off-limits list. Negative control: the suite's
own built-in red-first pass (running against the unpatched committed file
via `git archive HEAD`) already demonstrates the fail→pass transition.

## Suite 4 — test-phase-precondition.sh

`_phase_precondition_guard()`'s `REQUIRE_PHASES=0` kill switch was
confirmed byte-identical to pre-C4 behavior and ruled out as the cause.
Instrumenting the test to capture real dispatch stderr (instead of
`/dev/null`) revealed the actual chain: the `glm-stub.sh` fixture's `bg`
case emitted a doubled `"$RUNS/$handle$handle"` envelope under a comment
claiming "dispatch-code's GLM adapter extracts a handle from the legacy
envelope" — but the current adapter (documented directly above the glm
case in `leadv2-dispatch-code.sh` as GLM-ARM-THROUGHPUT-01) takes the `bg`
output verbatim as the handle, no extraction, because the old
halving/extraction logic was deliberately removed for truncating every
handle to a useless half-string. The doubled envelope made `status
<handle>` always report `not_live`; dispatch fell back from glm to a real
(unstubbed) sonnet launcher, which failed for an unrelated reason (missing
role file) — the visible `G3: dispatch should exit 0 (got 4)` was several
arms removed from the real cause. Fixed the stub to emit the bare handle
once, matching the documented current contract, entirely within the test
file (`LANE_WRITES`, neither off-limits file touched). rc 1→0, `pass=82
fail=0` against clean main. Negative control: reintroducing the doubled
envelope on a clean-main copy reproduces the exact original failure
(`pass=81 fail=1`); reverting restores green.

## Files changed (all within LANE_WRITES)

- `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh`
- `plugins/leadv2/scripts/tests/test-injector-dedup.sh`
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`
- `plugins/leadv2/scripts/tests/test-phase-precondition.sh`
- `tests/mutations/catalog.yaml` (new)
- `docs/handoff/MAIN-CORE-SUITE-RED-01/report.md` (new)

None of `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`,
`leadv2-dispatch-code.sh`, or `leadv2-phase-record.sh` were touched.
`tests/known-red-suites.txt`/`known-failures.txt` do not exist in this
checkout at all, so nothing was added to or removed from them.

## Self-checks

`bash -n` clean on all four changed `.sh` files. No `.py` files changed.
Each suite individually run to green against a fresh `main` clone plus this
lane's diff (see report.md for exact rc/pass-fail numbers). Diff does not
touch `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*`
(those paths show up in `git status` as modified from concurrent hook/state
activity in this shared worktree, not from this task's edits — confirmed
via `git diff --stat HEAD` scoped to the files listed above only).

DELIVERABLE_COMPLETE
