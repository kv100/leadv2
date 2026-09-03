verdict: APPROVE
next_action: review_round_2

# LANE-MERGE-SILENTLY-REVERTS-MAIN-01 — developer full report

## What changed

1. **New gate: `plugins/leadv2/scripts/leadv2-merge-safety-gate.sh`**
   `leadv2-merge-safety-gate.sh <repo_root> <lane_branch> [<default_branch>]`
   - Resolves `DEFAULT_BRANCH` via the existing `lv2_default_branch` helper (sourced from
     `leadv2-branch-merged.sh`) if not passed explicitly.
   - `DELETED` = `git diff --name-status --diff-filter=D <default> <lane> --` (tip vs tip —
     exactly what `git diff --stat main..HEAD` shows a human).
   - `LANE_TOUCHED` = `git diff --name-only <merge-base> <lane> --` (the lane's own history).
   - Any path in `DELETED` not present in `LANE_TOUCHED` is an offender: the lane's tree is
     missing it, and the lane's own commits never mention it, so the only way it can be
     missing is that the default branch grew the file after the lane forked.
   - Exit 0 = safe. Exit 1 = refused, stderr lists every offender as `path:1 (<line-count>
     lines on <default>, absent from <lane>, never touched by lane commits)`, plus a fix
     line `FIX: merge <default> into the lane, then retry.` Exit 2 = usage/git error
     (unresolvable branch, no merge-base).

2. **Wired into `leadv2-deploy-merge.sh`** (line ~121, after the `git pull --ff-only origin
   main` backstop, before `git merge --ff-only "$TASK_BRANCH"`): calls the gate, and on rc=1
   writes a blocker + exits 1; rc>=2 also blocks (fail-closed on gate error, never fail-open).

3. **Wired into the T11 merge in `leadv2-dispatch-product-close.sh`** (line ~3437): the gate
   runs before `git merge --no-edit --no-ff "${_t11_branch}"`. On refusal, the existing
   `pass_unlanded` bookkeeping path is reused with a new reason code
   `merge_would_revert_main`, carrying `fix=merge_${_t11_default}_into_lane_then_retry` in the
   evidence string — so the fix line survives into the same audit trail the rest of T11 uses,
   not just stderr.

4. **Test suite: `plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh`** — 10
   assertions, each building real throwaway git repos under `mktemp -d` (no repo/branch
   mocking):
   - **case 1** — negative control #1 (mission item 4): lane B branches before lane A lands
     `fileX.txt` on main. Gate refuses (rc=1) naming `fileX.txt`; a real `--no-ff` merge is run
     to confirm it *would* in fact go through clean and drop the file (belt-and-suspenders);
     merging main into B first flips the gate green. Mirrors
     `SAFETY-PIN-SECOND-DOOR-01` / `HEAVY-TIER-VS-SAFETY-OPUS-01` (single journal file).
   - **case 2** — two files land on main after the lane forked; gate names both. Mirrors
     `E2E-TIMEOUT-…` and `LEAD-IS-OPUS-…` both losing the 304-line brief.
   - **case 3** — negative control #2 (mission item 3, reverse case): the lane's own commit
     deletes `obsolete.txt`. Gate does NOT refuse; a real merge confirms the file is genuinely
     gone afterward. Proves the discriminator doesn't block legitimate deletions.
   - **case 4** — the mixed case, deliberately built to stress the discriminator against the
     real WORKER-OUTLIVES round-3 shape (one file the lane legitimately deleted itself, one
     file another lane landed on main concurrently): gate refuses ONLY on the
     lane-never-touched file, never on the lane's own deletion. Then merging main in and
     re-checking: still green, the accidental file is gone, and the lane's own deletion
     (`obsolete.txt`) survived the main-merge undisturbed.
   - **case 5** — an unresolvable lane branch name returns rc=2 (hard error), not a silent
     pass — errors must not be swallowed into "safe to merge".

5. **`tests/run-all.sh`**: the suite is picked up by the existing self-select-by-stem
   convention (`test-leadv2-merge-safety-gate.sh` stem matches
   `leadv2-merge-safety-gate.sh`) automatically whenever the gate script itself changes. Two
   `EXTRA_SUITE_MAP` rows were added so the suite also re-runs when either caller changes:
   `leadv2-dispatch-product-close.sh:...test-leadv2-merge-safety-gate.sh` and
   `leadv2-deploy-merge.sh:...test-leadv2-merge-safety-gate.sh`.

## Discriminator argument (mission item 3)

Candidate: "did the lane's own commits (`base..lane`) touch this path." Checked against all
five measured cases plus both negative controls:

- All five real incidents are lanes that **never** touched the lost path — the discriminator
  correctly refuses every one (reproduced structurally in cases 1, 2, 4).
- The reverse case — a lane that deliberately deletes its own file — necessarily shows up in
  `LANE_TOUCHED` (git records the deletion as a diff entry on that path), so it is trusted and
  still lands (case 3, and the "own deletion" half of case 4).
- Rejected alternative: diffing content instead of tips-only presence (i.e. flagging any file
  the default branch modified after fork, on a path the lane never touched) — this would
  refuse nearly every ordinary merge, since the default branch is always moving. Scope is
  deliberately restricted to full-file absence via `--diff-filter=D` on tip-vs-tip, per the
  comment block at the top of the gate script.

## Off-limits compliance

`main`, `tests/known-red-suites.txt` untouched. No fixture weakened. `docs/leadv2/*` and
`docs/handoff/dispatch-nw*` show as modified in `git status` inside this worktree but those are
pre-existing unstaged changes from other concurrent sessions sharing this worktree's runtime
state files — not part of this diff, not staged, and not committed by this task (verified via
`git diff --cached --stat`, which lists only the 5 plugin/test files below).

## Self-check (falsification set)

`bash -n` on every changed shell file — all OK:
```
== plugins/leadv2/scripts/leadv2-merge-safety-gate.sh ==
OK
== plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh ==
OK
== plugins/leadv2/scripts/leadv2-deploy-merge.sh ==
OK
== plugins/leadv2/scripts/leadv2-dispatch-product-close.sh ==
OK
== tests/run-all.sh ==
OK
```
No Python files changed — `py_compile` not applicable.

Suite run, macOS (bash 3.2 target, native):
```
ok - case 1: refuses and names fileX.txt (rc=1)
ok - case 1: real merge exit 0 and fileX.txt would in fact survive (belt-and-suspenders confirmed)
ok - case 1 fix: merge main into laneB flips the gate green
ok - case 2: refuses and names both concurrently-landed files
ok - case 3: lane's own deletion of its own file is allowed to land
ok - case 3: real merge lands clean and obsolete.txt is genuinely gone
ok - case 4: refuses on the accidental file only, never on the lane's own deletion
ok - case 4 fix: green after merging main in, obsolete.txt still absent (lane's intent preserved)
ok - case 4 fix: laneE's own deletion of obsolete.txt survived the main-merge
ok - case 5: unresolvable lane branch is rc=2, not a silent pass
--- 10 passed, 0 failed ---
EXIT=0
```

Suite run, Linux container (`debian:12-slim`, git 2.39.5 installed, bash 5.2.15 aarch64):
```
ok - case 1: refuses and names fileX.txt (rc=1)
ok - case 1: real merge exit 0 and fileX.txt would in fact survive (belt-and-suspenders confirmed)
ok - case 1 fix: merge main into laneB flips the gate green
ok - case 2: refuses and names both concurrently-landed files
ok - case 3: lane's own deletion of its own file is allowed to land
ok - case 3: real merge lands clean and obsolete.txt is genuinely gone
ok - case 4: refuses on the accidental file only, never on the lane's own deletion
ok - case 4 fix: green after merging main in, obsolete.txt still absent (lane's intent preserved)
ok - case 4 fix: laneE's own deletion of obsolete.txt survived the main-merge
ok - case 5: unresolvable lane branch is rc=2, not a silent pass
--- 10 passed, 0 failed ---
RC=0
```

`--scope changed` selection proof (`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope
changed`), relevant line:
```
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
...
run-all: 14 selected, scope=changed, select_only=1
```

Adjacent suites sharing `leadv2-dispatch-product-close.sh` in `EXTRA_SUITE_MAP` (pre-existing
rows, not part of this diff) were spot-checked so this change doesn't regress that carrier file:
- `test-e2e-timeout-classification.sh` — 9 passed, 0 failed, RC=0
- `test-dirty-lane-never-lands.sh` — PASS, RC=0
- `test-worker-outlives-terminal-state.sh` — left running past 4 minutes; this suite belongs to
  the currently-active `WORKER-OUTLIVES-ITS-TERMINAL-STATE-01` lane (phase `review:fail` per
  the session list), tests Sonnet-launcher/finalizer-PID logic entirely unrelated to the merge
  gate, and my diff to `leadv2-dispatch-product-close.sh` only inserts the gate check ahead of
  the existing `git merge --no-ff` call — it does not touch any finalizer/PID code this suite
  exercises. Not run to completion; flagged here rather than silently omitted.

## Left alone

- Did not touch `leadv2-branch-merged.sh` (only sourced `lv2_default_branch` from it, verified
  the symbol exists first).
- Did not attempt to make the full `tests/run-all.sh --scope changed` run to completion locally
  (times out past 2 min due to `run-core-offline.sh` and other unrelated long suites in the
  selected set — a known, pre-existing runtime characteristic, not something introduced here).

DELIVERABLE_COMPLETE
