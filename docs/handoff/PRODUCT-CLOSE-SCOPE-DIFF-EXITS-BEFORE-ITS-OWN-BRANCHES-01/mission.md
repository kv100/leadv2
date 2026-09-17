# PRODUCT-CLOSE-SCOPE-DIFF-EXITS-BEFORE-ITS-OWN-BRANCHES-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

Three red suites, all owned by `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`.
**They do not share one cause.** Two share one; the third is separate. Do not fix them as one.

## Cause 1 — the silent-arm probe is fooled by the lane's own bootstrap commit

Suites: `test-lane-diff-single-repo.sh` (rc=1, 4 pass / 1 fail, case `C5-registered-arm-silent`)
and `test-dispatch-product-close-exit-trap.sh` (rc=1, 6 pass / 2 fail, case `Test (a)`).

`test-lane-diff-single-repo.sh:213` asserts the journal line carries
`terminal=no_work` **and** `cause=arm_produced_nothing`. Observed instead:

```
review_gate task=... status=blocked reason=no_work terminal=no_work cause=empty_diff ...
```

Traced: `pc_silent_arm_probe` (`leadv2-dispatch-product-close.sh:2260`) sees the arm registered,
then its commits-ahead check (`:2333-2339`) reads `commits_ahead=1` — which is the lane
worktree's **own bootstrap commit** from `leadv2-lane-worktree.sh ensure`, not production — and
concludes "not silent", `return 1`. Control falls through to `pc_scope_diff`'s default branch
(`:3568`, `_pc_terminal="no_work"; _pc_cause="empty_diff"`), emitted at `:3637`, exit at `:3641`.

`test-dispatch-product-close-exit-trap.sh:103,116` fails for the same upstream reason: Test (a)
runs with `REVIEW_ON=0` and expects the `review_gate_disabled` landed path (`:4136-4188`), but
`pc_scope_diff` exits at `:3641` before `REVIEW_ON` is ever consulted. Observed:
`expected exit 0, got rc=5`, `row is not 'landed'`, `cause=empty_diff`.

The probe must not count the lane's own bootstrap commit as production.

## Cause 2 — Face 4: the foreign-repo pre-scan never populates on the normal path

Suite: `test-stop-gate.sh` (rc=1, 12 red→green / 1 fail, case `foreign-repo-journaled`, ~256s).

`test-stop-gate.sh:323` requires the journal to contain
`stop_gate_skipped_foreign_repo task=sghsig001`. Reproduced directly: with a write set naming one
in-scope path and one path resolving into a sibling git repo, the journal shows

```
stop_gate_autocommit task=sghsig001 files=1
dispatch_terminal task=sghsig001 terminal=landed cause=review_gate_disabled
```

— **no `stop_gate_skipped_foreign_repo` line at all**, and the foreign file is silently dropped
from scope. `:2818` emits that line only when `PC_STOP_GATE_FOREIGN_REPOS` is non-empty; the array
is populated at `:3163`, inside the `CROSS_REPO_DIFF` branch of `pc_scope_diff`, which the normal
path does not take. A file silently dropped from a write set is the serious half of this bug —
the missing journal line is only how the suite notices.

## Not in this lane

`test-report-only-gate.sh` was assigned to this group by the census. That assignment is **wrong**:
its failing assertions (`:436-437`, `:449-451`, `:457`) are about lines written by
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` (`:9111`, `:9113`, `:4832`, `:4879-4885`), and its
`run_dispatch()` (`:384`) invokes that script, not product-close. It belongs with the
`leadv2-dispatch-code.sh` group. Do not touch it here.

Likewise the census label "product-close waits for worker exit" resolves to
`test-no-work-terminal.sh` (`run-core-offline.sh:460`), which another lane already owns.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A suite that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do not touch `leadv2-dispatch-code.sh` — another lane holds it.

## Controls

Two independent causes, so **two** negative controls, each run, both outputs pasted. Apply each
mutation inside the function body **in the lane worktree**, never in a scratch copy: this suite
family was measured to give different results in a detached worktree than in a registered lane
worktree at the same commit. Assert the text you mutate is present before running, or the control
can rot into a permanent verdict that proves nothing.

## Deliverable

`docs/handoff/PRODUCT-CLOSE-SCOPE-DIFF-EXITS-BEFORE-ITS-OWN-BRANCHES-01/report.md` — before/after
counts per suite with their boundary (counts, ceiling, platform, commit), both controls with
pasted output, and any case left red with its cause.
