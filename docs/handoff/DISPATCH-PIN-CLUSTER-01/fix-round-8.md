# DISPATCH-PIN-CLUSTER-01 — round 8: the guard you added fails open in silence

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-lane-placement-pin.sh,plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

Full review: `docs/handoff/DISPATCH-PIN-CLUSTER-01/review-r7.md`. HEAD is `721d746`.
**Note: `~/Projects/leadv2` main has moved to `42d3232`** (CLOSE-GATE and HOOK-OUTPUT-CAP merged,
both touching `tests/run-all.sh`). Rebase onto main first; expect to hand-splice `run-all.sh`
rather than take a side.

**Round 7 fixed four real things and the reviewer killed each with his own in-place mutation —
keep them all.** H-1: `dispatch_terminal_exists` returns rc0 for `pass_unlanded` again, identical
to the merge base, driven through the real CLI at both revisions, and
`test-dirty-lane-never-lands.sh:122-133` goes RED when mutated. H-2: the two contradicting comments
now agree. H-3: the counting form is restored and goes RED at 1 of 2 sites. C-1 runtime is verified
in a real 204-link consumer farm with no `lib/`: zero source errors post-merge. Also settled: the
`when::` stderr at `:5786` is **pre-existing on `origin/main` (`3dcd5f2`)**, not this lane's doing —
the reviewer's first zero on it was a false zero, and he corrected himself.

## [Critical] H7-2 — `[[ -f ]] && source` degrades to a silent fail-OPEN

With the lib absent, the guarded source prints **0 bytes to stderr** and leaves `lv2_lane_dirty`
undefined. `write_terminal:265-276` then skips both pins, and **a dirty lane records `landed`.**

That is the whole point of this lane inverted: the guard that was added so a consumer repo would
not die at launch now lets a consumer repo silently record a false success instead. Failing open
on a close gate is worse than failing loud at launch — that is the lying-green disease, delivered
by the fix for it.

Decide and implement one, and say which in `report.md`:

- resolve the lib through the canonical fallback and, if it is absent from BOTH roots, **refuse
  the terminal write** with a named error, or
- define a fail-CLOSED stub for `lv2_lane_dirty` (unknown ⇒ treat as dirty ⇒ never `landed`).

Prove it: with the lib removed, run the close path against a dirty lane and show it does NOT
record `landed`, plus the message it does emit. Then restore the lib and show the normal path
still records `landed` for a clean lane. Both pasted.

## [Critical] H7-1 — the consumer-symlink guard suite still does not exist

C-1's required suite was never built. Its stand-in is three `grep -Fq` against
`leadv2-dispatch-product-close.sh` source text — the assertion form this lane's own rules ban —
and it covers 1 of the 4 sourcing scripts.

Build `tests/test-consumer-symlink-farm.sh`: construct a farm with no `lib/` (the reviewer's
204-link reproduction is the model), run **all four** sourcing scripts through it, and assert each
resolves and behaves. Mutation-prove by stripping the canonical fallback from each of the four in
turn and showing the suite RED naming that specific file — position-independent, per the same
lesson the CLOSE-GATE lane just learned: a control that asserts on the first violation in a list is
flipped by any stranger's commit.

## [High] H7-3 — H-4 was not delivered, and its justification is contradicted

The pre-image re-anchoring is missing. `cmp -s` cannot catch round 6's own comment-only-delta case
— that is exactly the shape that already slipped through once. The `report.md` claim that the merge
base is "not viable" is false: `5d1a5d7:leadv2-dispatch-product-close.sh` carries all 8 anchors, the
reviewer checked. Re-anchor the pre-image against the merge base and show the control RED on a
comment-only delta.

## [Medium] M7-1 — `report.md` omits a result the brief ordered fixed, and cites a commit message

`test-lane-placement-pin.sh` is 24/3 (merge base 16/9) and `report.md` does not mention it. Fix the
three failures or state why they stand. Also: a commit message is not evidence — replace that
citation with a run.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

A close path that cannot record `landed` when the lib is missing, shown both ways; a consumer-farm
suite covering all four sourcing scripts with four position-independent RED controls; the
re-anchored pre-image RED on a comment-only delta; and `test-lane-placement-pin.sh` accounted for.
