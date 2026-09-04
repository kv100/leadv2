verdict: APPROVE-candidate
next_action: review_round_2

# ANTI-SILENCE-STATUSLINE-01 round 11 — developer full report

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`
HEAD before this round: `365b5da`. Commit made this round: `ed199c0`.

## 1. Investigation — could the reported damage be reproduced?

The round-10 report claimed: after running `test-status-surface.sh`, `docs/leadv2/questions`
ends up as a symlink into the suite's temp sandbox, dangling once the sandbox is cleaned.

Direct repro attempts on this HEAD did **not** reproduce it:

```
BEFORE: docs/leadv2/questions -> /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/questions
$ bash plugins/leadv2/scripts/tests/test-status-surface.sh   # exit 0, 91 passed
AFTER:  docs/leadv2/questions -> /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/questions  (unchanged)
```

Audited the whole file for any direct manipulation of `docs/leadv2/questions`: none found. Every
renderer/watcher/widget invocation in this suite is sandboxed via the `NEW_SB()` env wall
(`LEADV2_STATUS_QUESTIONS_DIR`, `LEADV2_STATUS_HANDOFF_DIR`, `LEADV2_STATUS_REPO_ROOT`, etc.), and
the render script itself (`leadv2-status-surface.sh`) only ever calls
`leadv2-state-path.sh --no-link` for its default, which explicitly skips the migration/symlink
side effect. No other repo path is re-pointed by this file either — audited for `ln -s`, found
zero occurrences (mission's "audit for any other repo path": **0 found**).

Working theory for the round-10 observation: this repo's own `/leadv2` control-plane hooks fire
on every prompt in every concurrent session/worktree and legitimately touch
`docs/leadv2/{active.yaml,bus.jsonl,merge-queue.jsonl,questions,...}` via
`leadv2-state-path.sh` (confirmed: at session start, `git status` already showed all of these as
modified, unrelated to any test run — this is normal live-system churn, not test damage). The
round-10 reviewer likely observed a real concurrent-session touch, not this suite. This is
UNVERIFIED (I cannot reconstruct their exact session state) — noted, not asserted as fact.

Also confirmed the *current* HEAD's tracked git blob for `docs/leadv2/questions` (from the round-10
"session close" commit `a310073`) points to a dead temp path
(`/var/folders/.../core-offline-run.aqFVru/.../home/.claude/leadv2-state/leadv2/questions`), while
the actual working-tree inode had already been hand-repaired (by a prior session) to point at the
real `~/.claude/leadv2-state/leadv2/questions`. This mismatch is real and matches the report — but
it is a **pre-existing commit defect on this path**, not something `test-status-surface.sh` did in
this round. `docs/leadv2/questions` is outside `LANE_WRITES`, so it was left untouched.

## 2. Fix: real assertion + repair trap on the one path in question, plus a genuine bug found

Since I could not prove the suite currently mutates the real path, but the mission requires the
suite to *prove* hermeticity (not assume it), I added:

- A snapshot (`_herm_snapshot`) of `docs/leadv2/questions`'s real-world type (symlink target / dir
  / file / missing), resolved via `git -C "$SCRIPT_DIR" rev-parse --show-toplevel` — **never**
  `../..` hops (per GATE-WRONG-ROOT-FALSE-DEAD-01).
- A real PASS/FAIL assertion at the end of the file comparing before/after snapshots.
- A repair function (`_herm_restore`) wired to `trap ... EXIT INT TERM`, so any drift — from this
  suite or a concurrent process — is corrected before the process exits.

While wiring the trap I found the suite already breaks its own promise: line ~1212 (R5r2 minifix
block) does `trap cleanup_mini EXIT` — a bare `trap ... EXIT` **replaces** any earlier EXIT
handler in bash, it doesn't stack. This is a real, pre-existing bug: if any future fixture *did*
retarget `docs/leadv2/questions`, my (or any) EXIT-trap-based repair would have been silently
dropped by this later trap. Fixed by making `cleanup_mini` also call `_herm_restore`:

```bash
cleanup_mini() { rm -rf "$MiniFix"; _herm_restore; }
trap cleanup_mini EXIT INT TERM 2>/dev/null || true
```

## 3. Falsification (RED / repair-proof / revert / GREEN)

**Baseline GREEN** (guard present, no mutation):
```
BEFORE: docs/leadv2/questions -> .../leadv2-state/leadv2/questions
exit=0 ... PASS: hermetic: docs/leadv2/questions unchanged (L:.../leadv2-state/leadv2/questions)
=== 92 passed, 0 failed ===
AFTER:  docs/leadv2/questions -> .../leadv2-state/leadv2/questions  (unchanged)
```

**RED control** — temporarily inserted (right after the trap is armed) a mutation simulating the
exact round-10 defect (a fixture retargeting the real path without restoring it):
```bash
rm -rf "$_HERM_QDIR" 2>/dev/null; mkdir -p /tmp/herm-red-control-target
ln -sfn /tmp/herm-red-control-target "$_HERM_QDIR"
```
First attempt (before the `trap cleanup_mini` fix) — proved the FAIL AND proved the repair trap
was silently dropped (real path stayed pointed at the dead control target after exit):
```
exit=1 ... FAIL: hermetic: docs/leadv2/questions changed L:.../leadv2-state/leadv2/questions -> L:/tmp/herm-red-control-target
=== 91 passed, 1 failed ===
AFTER: docs/leadv2/questions -> /tmp/herm-red-control-target   <-- NOT repaired (proves the trap-clobber bug)
```
After fixing `cleanup_mini` to chain `_herm_restore` — same RED mutation, now correctly repaired
on exit despite the assertion still failing (proving the assertion and the repair are independent
signals, as required):
```
exit=1 ... FAIL: hermetic: docs/leadv2/questions changed L:.../leadv2-state/leadv2/questions -> L:/tmp/herm-red-control-target
[TEST] HERMETIC-RESTORE docs/leadv2/questions L:/tmp/herm-red-control-target -> L:.../leadv2-state/leadv2/questions
=== 91 passed, 1 failed ===
AFTER: docs/leadv2/questions -> .../leadv2-state/leadv2/questions   <-- repaired
```

**Revert control mutation, final GREEN:**
```
BEFORE: docs/leadv2/questions -> .../leadv2-state/leadv2/questions
exit=0 ... PASS: hermetic: docs/leadv2/questions unchanged (L:.../leadv2-state/leadv2/questions)
=== 92 passed, 0 failed ===
AFTER:  docs/leadv2/questions -> .../leadv2-state/leadv2/questions  (unchanged)
```

`git diff --stat` for the commit: `plugins/leadv2/scripts/tests/test-status-surface.sh | 51 insertions(+), 2 deletions(-)`
(the temp RED-control lines were removed before commit — confirmed via final `git diff --stat`
showing only the permanent guard code).

## 4. `tests/run-all.sh` reconciliation

Diffed against main (`cf1349e`):
```
git diff cf1349e -- tests/run-all.sh
```
Result: our branch already has, on top of main, exactly the lane-specific additions the mission
asked to "re-apply" — the `test-*.sh` self-selection case (a changed test suite selects itself
even when its production counterpart didn't change) and the two
`leadv2-lane-status-line*.sh:...test-statusline-readable.sh` map rows. Confirmed main already
carries the state-file bounding (`leadv2-run-all-last-checked-sha`), the widened
`scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob, and the `freepool-arm.yaml` case (grepped
`cf1349e:tests/run-all.sh` directly). **No change needed** — `bash -n tests/run-all.sh` passes,
file is untouched in this round's commit.

## 5. Falsification set (per protocol)

```
$ bash -n plugins/leadv2/scripts/tests/test-status-surface.sh && echo OK1
OK1
$ bash -n tests/run-all.sh && echo OK2
OK2
$ bash plugins/leadv2/scripts/tests/test-status-surface.sh
=== 92 passed, 0 failed ===
```
No Python files were changed this round.

Commit: `ed199c0` on `worktree-ANTI-SILENCE-STATUSLINE-01`.
`git diff --stat`: `plugins/leadv2/scripts/tests/test-status-surface.sh | 51 insertions(+), 2 deletions(-)` only.

## 6. Left alone

- `docs/leadv2/questions`'s committed bad symlink target (points to a dead temp dir) — outside
  `LANE_WRITES`, and the working-tree inode is already hand-repaired; fixing the git-tracked blob
  itself is a separate, out-of-scope change (arguably it shouldn't be tracked at all now that main
  gitignores it as a real directory post-`cf1349e` — that's a merge-time reconciliation, not a
  lane-scope fix).
- The pre-existing duplicate `leadv2-lane-pulse-watch.sh:...test-lane-pulse-founder.sh` row and the
  extra `leadv2-status-surface.sh:...test-status-surface.sh` row in `tests/run-all.sh`'s
  `EXTRA_SUITE_MAP` — harmless (de-duped by `add_suite`), not named in the mission's reconciliation
  list, left as-is to keep this round's diff minimal.

DELIVERABLE_COMPLETE
