# SHADOW-CONTROL-PLANE-01 — fix round

**Authorship note.** The worker completed the work and committed after every step, then died at
07:14:59Z with `cause=transport_gone_app_server_absent` before writing this report. Everything below
is reconstructed from the artifacts it committed under `fix-round/` and `mutation-control/`, plus a
guarding-suite sweep the lead ran afterwards. Where a claim is the lead's own measurement rather than
the worker's, it says so.

## 1. The failing leg — it was the test, and the fix was incomplete in the same place

`writer: real collector -> lanes-snapshot -> state-path` failed with
`AssertionError: {'data': '', 'ok': False}`. Cause: **the registry was never initialized**, so a
direct snapshot probe reports `registry_error` and the assertion receives empty data. After
initializing through the sourced registry API, the real collector passes.

Committed as `d747b5f0 test(shadow-control-plane): initialize registry before collector snapshot`.
The leg was not deleted to improve the number. Suite now **PASS=15 FAIL=0**.

## 2. The nine dangling symlinks — removed, with a paired control

`git ls-files plugins/leadv2/scripts/docs/leadv2/` listed nine tracked files, every one a symlink
into `/tmp/leadv2-pc-e2e-tPnsnK/state/leadv2/` — a temp directory from a 2026-09-04 E2E run that no
longer exists. `fix-round/deletion.txt` enumerates all nine with `dangling=true`.

**Paired control** (`fix-round/deletion-green.txt`): a real registry round-trip — register, list,
unregister — was exercised **with the nine links present and again with them absent**, and passed
both times (`deletion-control: present register/list/unregister checked`). Nothing depended on them.

Committed as `7ca0bcd6 fix(shadow-control-plane): remove nine dangling fixture links with registry
control`.

## 3. The stray directory stops being created — before/after on the real writer

The writer was identified as `leadv2-status-collector.sh` passing its own cwd as `PROJECT_ROOT`,
with `leadv2-state-path.sh` failing to resolve that to the owning worktree root. Running the real
collector from `plugins/leadv2/scripts` in a fresh tree (`fix-round/before-after.txt`):

    before:  nested_docs_lexists=True   walk_count=1   snapshot_exists=True  lanes_ok=True
    after:   nested_docs_lexists=False  walk_count=0   snapshot_exists=True  lanes_ok=True

The stray `plugins/leadv2/scripts/docs/` is gone **and the collector still does its job** — the
snapshot is still written and lanes still resolve. A fix that stopped the directory by breaking the
collector would have shown `snapshot_exists=False`.

The 42 of 267 lane worktrees that already carry the nested path were deliberately NOT cleaned: other
lanes are live in some of them.

## 4. Mutation control — both colours, anchored inside the fix

`mutation-control/20260906T071138Z-80181.txt`:

    suite       plugins/leadv2/scripts/tests/test-shadow-control-plane.sh
    file        plugins/leadv2/scripts/leadv2-state-path.sh
    anchor      /^LINK_ROOT=.*git -C/d          (deletes the resolution line itself)
    baseline_rc 0
    mutated_rc  1
    red_line    FAIL: test -L .../repo/docs/leadv2/active.yaml

The mutation removes the `git -C ... rev-parse --show-toplevel` resolution — the fix's load-bearing
line — rather than being inserted at an arbitrary line number, so the red is caused by the thing
under claim and not by a syntax error elsewhere.

## 5. CI selects the new suite

`fix-round/selection.txt`:

    [SELECT] .../plugins/leadv2/scripts/tests/test-shadow-control-plane.sh

## 6. Guarding-suite sweep — lead's own measurement

`leadv2-state-path.sh` has **twenty** guarding suites and `leadv2-status-collector.sh` two, found by
their `# run-all-triggers:` headers. All 23 were run against this branch. **18 clean green.**

Two reported no summary line and were checked by hand — both green, in formats a
`pass=N fail=N` grep does not match:

    test-state-path-worktree-identity   ALL PASS
    test-landed-at-spawn                [LANDED-AT-SPAWN-01] passed=12 failed=0

**Three are red, and all three are red identically on clean main** — each baselined by running the
same suite in a detached worktree at `main`, so none is caused by this branch:

    suite                                  this branch    clean main
    test-lane-truth-batch-01               15 / 1         15 / 1     (allowlisted, tests/known-red-suites.txt:35, red since 2026-09-02)
    test-status-surface-cwd                 4 / 3          4 / 3
    test-collector-sees-registered-lane     4 / 1          4 / 1

`tests/known-red-suites.txt` was not touched and did not grow.

## What this branch does not claim

The three pre-existing reds are not fixed here and are not this task's remit; they are stated so the
next reader does not mistake a red sweep for a regression. `test-collector-sees-registered-lane`
guards a file this branch changed, so its baseline was the one worth checking most carefully — it is
identical, 4/1, with and without this branch.
