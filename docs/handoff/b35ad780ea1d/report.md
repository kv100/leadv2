# LANE-MERGE-SILENTLY-REVERTS-MAIN-01 + writing half of RECORD-THE-LANDING-DONT-INFER-IT-01

Commit: `5b0293b0` (lane `b35ad780ea1d`)

## What landed

1. **Merged-tree regression gate** (`leadv2-deploy-merge.sh`, before the
   ff-only merge): probes `git merge-tree --write-tree main <branch>` and
   diffs the tree the merge would actually LAND against main. A path that
   diff changes while **no lane commit ever named it** (`git log --name-only`
   — merge commits emit no patch, so content dropped by a wholesale
   mid-flight merge resolution stays unnamed) is a silent revert of main →
   refuse: `exit 1`, reverted list on stderr, `merge-blocker.flag` written,
   no merge.
2. **`--allow-main-regression`**: deliberate override — prints the FULL list
   of what the merge reverts, then proceeds.
3. **Landed-lane/Landed-branch trailers**: the landed commit is amended
   (idempotently, before the push) to carry `Landed-lane: <task-id>` and
   `Landed-branch: <branch>`. Slitness is WRITTEN at landing time, not
   derived — the strict three-level blob/patch-id slitness test is NOT
   weakened (1-of-6 measurement, 2026-09-06).

## Finding: the previous gate never ran once

`leadv2-merge-safety-gate.sh` (commit `57de5a5b`, "Wired into
leadv2-deploy-merge.sh (final backstop)") is committed **100644**, so both
`[[ -x ]]` call sites — `leadv2-deploy-merge.sh:128` and the T11 merge in
`leadv2-dispatch-product-close.sh:4073` — silently skipped it on every run.
A gate that existed only in a commit message. Replaced in deploy-merge by
the inline probe above.

## Write set compliance

Only `plugins/leadv2/scripts/leadv2-deploy-merge.sh` (modified) and
`plugins/leadv2/scripts/tests/test-merge-does-not-regress-main.sh` (new)
plus this report. Off-limits files untouched. No runtime-state paths in the
diff.

## Green run (final, after restore)

    $ bash plugins/leadv2/scripts/tests/test-merge-does-not-regress-main.sh
    Merge made by the 'ours' strategy.
    ok - case 1: refused rc=1, names fileX.txt
    ok - case 1: merge-blocker.flag written
    ok - case 1: origin/main untouched, fileX.txt still there
    Merge made by the 'ours' strategy.
    ok - case 2: override prints the full revert list
    ok - case 2: proceeded past the gate (terminal deploy-override BLOCK, rc=1)
    ok - case 2: landed commit carries Landed-lane/Landed-branch trailers
    ok - case 2: override landed the lane AND really reverted fileX (honest override)
    ok - case 3: clean lane not refused
    ok - case 3: reached the terminal deploy-override BLOCK (rc=1)
    ok - case 3: fileX.txt SURVIVED the landing (no silent revert)
    ok - case 3: trailers on the clean landing too
    test-merge-does-not-regress-main: 11 passed, 0 failed
    SUITE_RC=0

## Red run A — probe check removed from the function body

(`return 0` inserted as the first statement of `lv2_probe_main_regressions`)

    $ bash plugins/leadv2/scripts/tests/test-merge-does-not-regress-main.sh
    Merge made by the 'ours' strategy.
    FAIL - case 1: expected rc!=0 + MERGE_REFUSED naming fileX.txt, got rc=1: From /var/folders/.../origin
     * branch            main       -> FETCH_HEAD
    From /var/folders/.../origin
     * branch            main       -> FETCH_HEAD
    Already up to date.
    Updating ee8a962..6af2bc0
    Fast-forward
     fileX.txt     | 221 ----------------------------------------------------------
     lane_file.txt |   1 +
     2 files changed, 1 insertion(+), 221 deletions(-)
     delete mode 100644 fileX.txt
     create mode 100644 lane_file.txt
    To /var/folders/.../origin.git
       ee8a962..7f3136d  main -> main
    OK
    [migration-apply] no migrations in 7f3136df4b8396016b99f4eb2654d86a5d9af14b — no-op
    BLOCK: .claude/leadv2-overrides/deploy.sh not found — run leadv2-init or create it
    FAIL - case 1: merge-blocker.flag missing or wrong:
    FAIL - case 1: origin/main moved or lost fileX.txt
    Merge made by the 'ours' strategy.
    FAIL - case 2: expected ALLOW-MAIN-REGRESSION list naming fileX.txt, got: From /var/folders/.../origin
     * branch            main       -> FETCH_HEAD
    From /var/folders/.../origin
     * branch            main       -> FETCH_HEAD
    Already up to date.
    Updating 8276235..e504ae7
    Fast-forward
     fileX.txt     | 221 ----------------------------------------------------------
     lane_file.txt |   1 +
     2 files changed, 1 insertion(+), 221 deletions(-)
     delete mode 100644 fileX.txt
     create mode 100644 lane_file.txt
    To /var/folders/.../origin.git
       8276235..6f6e3ed  main -> main
    OK
    [migration-apply] no migrations in 6f6e3ed007941114b63c22429399b099f565b26a — no-op
    BLOCK: .claude/leadv2-overrides/deploy.sh not found — run leadv2-init or create it
    ok - case 2: proceeded past the gate (terminal deploy-override BLOCK, rc=1)
    ok - case 2: landed commit carries Landed-lane/Landed-branch trailers
    ok - case 2: override landed the lane AND really reverted fileX (honest override)
    ok - case 3: clean lane not refused
    ok - case 3: reached the terminal deploy-override BLOCK (rc=1)
    ok - case 3: fileX.txt SURVIVED the landing (no silent revert)
    ok - case 3: trailers on the clean landing too
    test-merge-does-not-regress-main: 7 passed, 4 failed
    SUITE_RC=1

Note what the red run shows in passing: without the check the silent revert
REALLY happens (fileX.txt deleted on origin, exit path clean).

## Red run B — trailer write removed

(`if false` replacing the idempotence check guarding the amend)

    $ bash plugins/leadv2/scripts/tests/test-merge-does-not-regress-main.sh
    Merge made by the 'ours' strategy.
    ok - case 1: refused rc=1, names fileX.txt
    ok - case 1: merge-blocker.flag written
    ok - case 1: origin/main untouched, fileX.txt still there
    Merge made by the 'ours' strategy.
    ok - case 2: override prints the full revert list
    ok - case 2: proceeded past the gate (terminal deploy-override BLOCK, rc=1)
    FAIL - case 2: trailers missing from landed commit: merge main mid-flight (wholesale resolution)
    ok - case 2: override landed the lane AND really reverted fileX (honest override)
    ok - case 3: clean lane not refused
    ok - case 3: reached the terminal deploy-override BLOCK (rc=1)
    ok - case 3: fileX.txt SURVIVED the landing (no silent revert)
    FAIL - case 3: trailers missing: lane work
    test-merge-does-not-regress-main: 9 passed, 2 failed
    SUITE_RC=1

After each red run the good file was restored from a byte-identical backup
(`cmp`-verified) before the next step.

## Falsification set

- `bash -n` both changed shell files: OK (before staging and after restore).
- `python3 -m py_compile`: no Python files changed (n/a).
- `bash tests/run-all.sh --scope changed` (after commit, so the suite is
  tracked and discoverable — C5 skips untracked suites):

      [CORE-OFFLINE] scope=changed running 4 of 95 suites (base=main@b94ca7be56, 2 changed files, 0 unmapped)
      plugins/leadv2/scripts/tests/test-merge-does-not-regress-main.sh (scope-selected ad-hoc)
      test-merge-does-not-regress-main: 11 passed, 0 failed
      [CORE-OFFLINE] suites passed=4 failed=0 missing=0 known_red_skipped=0
      run-all: 7 passed, 0 failed, scope=changed
      RUN_ALL_RC=0

  (7 suites: core-offline shard incl. the new suite + old
  test-leadv2-merge-safety-gate, 3 status-surface suites, and
  test-deploy-merge-blocker-gate 27/27 — the pre-existing deploy-merge
  e2e stays green with the new gate and trailers in place.)

## Residual risks (honest)

- A revert baked into a **rebase-replayed** commit names the path and is
  trusted — at probe time it is indistinguishable from a deliberate edit.
  Caught: the wholesale mid-flight-merge resolution shape (all five measured
  incidents). Documented in the script comment.
- The T11 merge in `leadv2-dispatch-product-close.sh` still calls the dead
  100644 gate (`[[ -x ]]` never true) — out of this lane's write set. That
  landing path is still ungated.
- The old gate file itself (`leadv2-merge-safety-gate.sh`) is left as-is
  (out of write set); its suite remains green because the file is unchanged.
