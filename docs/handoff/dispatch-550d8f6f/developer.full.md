verdict: APPROVE
next_action: review_round_2

# HANDOFF-DOCS-INVISIBLE-IN-LANES-01 — developer full report

Worked in lane worktree `.claude/worktrees/HANDOFF-DOCS-INVISIBLE-IN-LANES-01`, branch
`worktree-HANDOFF-DOCS-INVISIBLE-IN-LANES-01`. All work committed there (not pushed).
Full narrative, census, and test output is in
`docs/handoff/HANDOFF-DOCS-INVISIBLE-IN-LANES-01/report.md` on that branch — this file
summarizes for the lead without duplicating it.

## What happened

`brief.md` asked for a census-driven fix to `docs/handoff/*` untracked-doc leakage. Mid-task, a
`brief-addendum-second-cause.md` auto-merged into the lane (via an `origin/main` merge triggered
by lane-worktree tooling, not by me) describing a SECOND, independent cause of the same symptom
("brief invisible to worker") and explicitly asking me to choose and justify a fix. Both are
addressed.

## Cause 1 — untracked authored docs (original brief)

- Census: 7674 files on disk under `docs/handoff/`, 2134 tracked, 5265 correctly gitignored
  generated scratch, **275 leaked** (untracked, not gitignored, matches an authored-doc
  pattern — verified via `git ls-files --others --exclude-standard` + `git check-ignore -v`
  spot checks). Breakdown by pattern in report.md.
- `.gitignore`: added `!docs/handoff/*/continue-round*.md` — the one pattern named in the
  brief's own FREEPOOL example that had no negation (survived by luck on the two existing
  instances because the lead had force-added them).
- New suite `plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh`: detects
  untracked-but-not-ignored authored docs via a fixture, proves red (leak flagged) → green
  (after `git add`, clean). 4/4 pass. Registered in `tests/run-all.sh`'s `EXTRA_SUITE_MAP`
  under the pre-existing synthetic `gitignore` stem (same one HANDOFF-ARTIFACTS-GITIGNORED-01
  wired for `.gitignore` changes) — no new stem plumbing needed.
- Retroactive tracking: copied the 275 leaked files byte-for-byte from the main checkout into
  this worktree, `git add`ed with no `-f`, committed separately (`1f6dc786`) before the
  gitignore/test/pick_base commit — 38,437 lines / 3.1M.

## Cause 2 — lane worktree forks from a stale `origin/main` (addendum, found mid-task)

`leadv2-lane-worktree.sh`'s `pick_base()` always preferred `origin/main` over local `main`
whenever `origin/main` existed — even behind. The lead deliberately withholds pushes (a push
cancels in-flight CI via the workflow's concurrency group), so a committed-but-unpushed brief
was invisible to the very next lane's worktree. Addendum measured: 2 lanes, 2 arms,
`arm_produced_nothing` → `empty_diff`.

Addendum offered 3 options and asked me to argue a choice. I rejected "always fork local main"
(would silently drop sibling landings from other pushes — the reason `origin/main` was
preferred originally) and "refuse to dispatch on a missing mission file" (much larger surface:
`leadv2-dispatch-code.sh`, flagged high-churn/needs-care in this repo's own CLAUDE.md; treats
symptom not cause). Implemented instead: `pick_base()` now compares `origin/main`/`main` with
`git merge-base --is-ancestor` and forks from whichever is NOT behind the other — preserves the
original sibling-landings protection AND fixes the addendum's stale-origin scenario. A genuine
divergence (neither ref is an ancestor of the other) forks `main` but logs loudly rather than
guessing silently, since the script's contract is "exit 0 always, never hard-fail dispatch."

Added a `[[ "${BASH_SOURCE[0]}" == "$0" ]]` dispatch guard (existing idiom in this repo, e.g.
`leadv2-dispatch-ledger.sh`) so the function is unit-testable via `source`.

New suite `test-lane-worktree-base-pick.sh`: 5/5 (no-origin case, sibling-landings-preserved
case, the-fix case, diverged-logs-loudly case, plus `bash -n`). Registered in
`EXTRA_SUITE_MAP` under stem `leadv2-lane-worktree` (self-select-by-convention would look for
`test-leadv2-lane-worktree.sh`, which doesn't exist since the suite is named for the behaviour).

## Verification

- `bash -n` on every changed `.sh` file: all OK (listed in report.md).
- No `.py` files changed.
- `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`: selected all 4 of this
  diff's new/changed suites correctly (`test-handoff-artifacts-tracked.sh`,
  `test-handoff-docs-not-leaked.sh`, `test-lane-worktree-base-pick.sh`,
  `test-run-all-carrier-map.sh` — the last because I edited `tests/run-all.sh` itself), plus
  the 4 always-on suites.
- Ran all 8 selected suites individually (not the aggregate wrapper, which the harness's
  `run_in_background` truncates on long-running suites — known issue, avoided by running each
  suite directly): 6 clean, 2 with a single pre-existing failure each
  (`test-lane-worktree-isolation.sh` dispatch-reap case, `test-lane-worktree-resurrect-guard.sh`
  T1 case). Verified both are **pre-existing**: re-ran identically against
  `git show HEAD:plugins/leadv2/scripts/leadv2-lane-worktree.sh` (the file before my edit) and
  got byte-identical failure output. Not touched, not weakened.
- `run-core-offline.sh` (the always-on curated suite) was not run to completion in this
  session — it is documented elsewhere in this repo as routinely exceeding 10 minutes and is
  unrelated to any file this diff touches; the 8 targeted suites above are the actual
  regression coverage for this change.

## Off-limits compliance

- `main` never touched — all commits on the lane branch.
- `.gitignore` blanket rule not deleted, extended by one line.
- Diff (`git diff --stat` on both commits) touches only: `.gitignore`, `tests/run-all.sh`,
  `plugins/leadv2/scripts/leadv2-lane-worktree.sh`, two new test files under
  `plugins/leadv2/scripts/tests/`, `docs/handoff/HANDOFF-DOCS-INVISIBLE-IN-LANES-01/report.md`,
  and the 275 retroactively-tracked `docs/handoff/**` authored docs. Verified zero overlap with
  `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` (explicit grep, zero
  hits; those paths show only as unstaged working-tree churn from other concurrent sessions in
  `git status`, never staged by me).
- Both commits made on the lane branch, nothing left uncommitted (`git status --short` clean
  except the same pre-existing unrelated `docs/leadv2/*` / `docs/LEAD_V2_STATE.md` churn noted
  above, which I did not stage).

## Left alone / not done

- `run-core-offline.sh` full run (see Verification above — bounded by session time, not
  believed to be affected by this diff since it touches none of that suite's carrier files).
- No attempt to fix the two pre-existing `lane-worktree-isolation.sh` /
  `resurrect-guard.sh` failures — out of scope for this task, confirmed pre-existing.

DELIVERABLE_COMPLETE
