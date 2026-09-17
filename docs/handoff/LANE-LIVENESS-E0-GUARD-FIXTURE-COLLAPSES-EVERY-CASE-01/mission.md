# LANE-LIVENESS-E0-GUARD-FIXTURE-COLLAPSES-EVERY-CASE-01

Standing rules for this lane: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them
first; they are not repeated here.

## Two red suites, one observed cause

- `plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh` — exit 1, pass=13 fail=3, ~204s.
- `plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh` — exit 1, pass=3 fail=14.

Every failing case returns the same verdict:

```
{"verdict":"unknown:contradictory_rows","source":"e0_contradiction_guard","reason":"worktree_is_project_root"}
```

Subject: `plugins/leadv2/scripts/leadv2-lane-liveness.sh:977-985,997` — the E0 contradiction
guard fires *before* log_path / stream resolution ever runs, so the assertions about liveness
sources never reach their subject. Cause class: `never_reaches_subject`.

## What was already established — do not re-derive

The cause is **the fixture, not a guard misclassification**. In
`test-lane-verdict-three-states.sh` the fixture writes the registry row's `worktree: "${repo}"`
(lines `116`, `575`, `587`) and then invokes the liveness resolver with
`LEADV2_PROJECT_ROOT="$1"` set to that same `$repo` (lines `94-95`, `149`, `156`). Worktree and
project root are therefore the identical string **by construction**, which is exactly the
contradiction E0 exists to catch. No case in either suite varies them to a genuine sub-worktree.

So the guard is behaving correctly and the fixture is asserting against a shape it accidentally
made illegal.

## What to do

1. Re-run both suites yourself and confirm the verdict above before changing anything. If what
   you observe differs from this text, trust your observation and say so in the report.
2. Fix the fixtures so each case registers its row with a real lane worktree path distinct from
   `LEADV2_PROJECT_ROOT` — the shape a live lane actually has. The assertions about
   `set_log_path`, stamped `log_path` and stream liveness must then reach their subject.
3. If any case genuinely needs `worktree == project root` (that is the shape E0 rejects), keep
   it and assert the E0 verdict **explicitly**, so the suite documents the contradiction instead
   of tripping over it.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A suite that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do not weaken or bypass the E0 guard in `leadv2-lane-liveness.sh`. It is not the defect here.
  If you come to believe it is, stop and say so in the report with your evidence; do not edit it.

## Controls

These are **two independent claims** (one per suite), so they need **two** negative controls, each
run, with both outputs pasted. Apply each mutation inside the fixture body in the lane worktree —
not in a scratch copy: this suite family is sensitive to *where* the tree lives, and a detached
worktree under `/private/tmp` was measured to give a different result (26/3) from the registered
lane worktree (29/0) at the same commit. Before running a control, assert that the text you are
mutating is actually present, or the control can rot into a permanent verdict that proves nothing.

## Deliverable

`docs/handoff/LANE-LIVENESS-E0-GUARD-FIXTURE-COLLAPSES-EVERY-CASE-01/report.md` — the observed
before/after counts for both suites with their boundary (counts, ceiling, platform, commit), both
controls with pasted output, and any case you chose to leave red with its cause.
