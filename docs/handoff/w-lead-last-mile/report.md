# W-LEAD-LAST-MILE-01 — финиш линии одной командой

Lead: dispatch on lane `worktree-5c6d0ff8014e`, 2026-09-10. Code commit `bfe74742`.

## What was extended, and where (no second lander, no second mutator)

Three components, extended in place:

1. **`plugins/leadv2/scripts/leadv2-land.sh`** (the single landing runner):
   - NEW `land_write_set_load()` — resolves the lane's write set: declared via
     `LEADV2_LAND_WRITE_SET` (comma/colon list of repo-relative paths, or a
     path to a file, one path per line, `#` comments ignored), else derived
     from the lane's own diff (`merge-base..LANE_TIP`, `--no-renames` so a
     rename counts as both its paths).
   - NEW `land_in_write_set()` — exact match or directory-prefix match.
   - NEW **`land_merged_tree_check()`** — the merged-tree instrument: runs
     `git merge-tree --write-tree --no-messages <default> <land-tip>`, diffs
     the produced tree against the default branch (`--name-status
     --no-renames`), and refuses (`reason=merged_tree_outside_write_set`,
     one line per file, file named) on any non-Add entry outside the write
     set — i.e. a merge that would DELETE or REVERT a main file the lane
     was not allowed to touch. A conflicted merge-tree refuses as
     `merged_tree_conflict`. This was `grep -c merge-tree` = 0 across land /
     lane-outcome / branch-merged before this change — the question "не
     откатит ли слияние main" was never asked mechanically.
   - It is called **inside `land_safety_gate`'s body** (marked
     `# MERGED-TREE-INSTRUMENT`), right after the existing
     `leadv2-merge-safety-gate.sh` sub-check.
   - NEW `--no-ff` mode: a real merge commit carrying
     `Landed-lane: <task>` / `Landed-branch: <lane>` trailers (the lead's
     close-ritual shape), with a `noop_land` guard when the lane is 0 ahead.
     Queue, ledger, push and verification are untouched — same single lander,
     ledger `mode=no_ff`.
2. **`plugins/leadv2/scripts/leadv2-mutation-control.sh`** — NEW `--live`
   LEAD mode alongside the untouched worker (scratch) mode: the SAME
   mutation (sed or patch) applied to the REAL file in the lane checkout,
   baseline-green check first, red proof in the real checkout, then
   byte-identical restore and a porcelain proof: `git status --porcelain`
   (sorted) must equal the pre-run snapshot — empty when the checkout was
   clean. Restoration is guaranteed by trap on EVERY controlled exit:
   `EXIT` trap `_mc_live_restore` restores from a backup taken before the
   file is touched; `TERM`/`INT`/`HUP` are routed through `exit 143/130/129`
   (macOS bash 3.2: EXIT alone never fires on an untrapped signal) and kill
   the suite child first so a foreground `wait` cannot defer the trap. The
   mutated suite run is backgrounded (`exec bash suite &` + `wait`) so a
   TERM reaches the trap immediately. Artifact format adds
   `mode=live`, `porcelain_clean=yes`, `restored=yes`.
3. **`plugins/leadv2/scripts/leadv2-lane-finish.sh`** (NEW wrapper, the one
   finish command): `suite → mutation (--live) → cleanliness → land`. First
   red step aborts with `leadv2-lane-finish: REFUSED step=<name>` and a
   non-zero rc; success prints one ok line per step + `CHAIN GREEN`. The
   cleanliness step compares porcelain (with `-uall`, so a collapsed
   `?? docs/` dir cannot dodge the filter) against the pre-chain snapshot,
   with the chain's ONE declared write — the `--task-dir` artifact dir —
   filtered from both sides. Land is called with `LEADV2_LAND_WRITE_SET`
   forwarded; `--dry-run`/`--no-ff` forwarded; the wrapper itself never
   merges, pushes or writes ledger rows.

New suites (registered, `# run-all-triggers:` declared):
`plugins/leadv2/scripts/tests/test-land-merged-tree.sh`,
`test-mutation-control-live.sh`, `test-lane-finish.sh`.

## Приёмка §1 — merged-tree refusal, one fixture, red and green

Same fixture shape: `lane-mt` does declared work in `src/lane.txt`;
`lane-mt-del` is the SAME lane plus one commit `git rm src/victim.txt`
(a main file outside the declared write set). Raw output:

```
ok - m1: rc=1 on outside-write-set deletion
ok - m1: refusal names the file
ok - m1: refusal reason            (reason=merged_tree_outside_write_set; line: "merged-tree deletes main file outside the lane write set: src/victim.txt")
ok - m1: main did not move (victim still tracked)
ok - m1: ledger row reason
ok - m2: rc=0 on the same lane minus the deletion   (lands; victim intact; remote tip == lane tip)
ok - m2: ledger row landed
ok - m3: rc=1 via file-form write set               (write set as a file, comments ignored)
ok - m4: rc=0 with derived write set                (the lane's OWN deletion is its decision — no false refusal)
ok - m5: rc=1 on outside-write-set revert           (M-status: "changes main file outside the lane write set: src/keep.txt")
ok - m6: rc=0 with prefix entry src                 (directory-prefix write-set entries)
# land-merged-tree pass=18 fail=0
```

## Приёмка §2 — lead mutation on the REAL file + kill mid-run

`test-mutation-control-live.sh`, raw output (25 asserts):

```
ok - l1: rc=0 / mode=live / porcelain_clean=yes / file restored byte-identical
ok - l1: git status --porcelain is empty (was clean before)
ok - l1: artifact written; carries mode=live, porcelain_clean=yes, restored=yes
ok - l2: kill landed while the real file was mutated       (TERM during the mutated suite run)
ok - l2: killed run exits 143
ok - l2: file restored byte-identical after kill
ok - l2: git status --porcelain empty after kill
ok - l3: rc=1 on mutant_survived + file restored + porcelain empty
ok - l4: rc=2 control_not_applied reason=noop_edit + file untouched
# mutation-control-live pass=25 fail=0
```

## Приёмка §3 — finish refuses when the mutation did NOT redden

```
ok - f1: rc=1 when the negative control was not proven
ok - f1: refusal names the step        (REFUSED step=mutation)
ok - f1: main did not move / remote did not move / no land-ledger row (land never ran)
ok - f2: rc=0 green chain dry-run — STEP suite/mutation/cleanliness/land ok + CHAIN GREEN, main unmoved
ok - f3: rc=0 green chain real land --no-ff — merge commit (two parents),
         trailer Landed-lane == lane-fin-f3, Landed-branch == lane-fin-f3,
         remote tip == local main, ledger row landed mode=no_ff
ok - f4: rc=1 red lane suite — REFUSED step=suite, main unmoved
# lane-finish pass=30 fail=0
```

## Приёмка §4 — negative control: merged-tree check removed from land_safety_gate body

Lead live mutation on the REAL `plugins/leadv2/scripts/leadv2-land.sh`
(sed: delete the `land_merged_tree_check "${LAND_TIP}"` call line inside
`land_safety_gate`), suite `test-land-merged-tree.sh`:

```
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-land-merged-tree.sh \
  file=plugins/leadv2/scripts/leadv2-land.sh \
  red_line=FAIL - m1: rc=1 on outside-write-set deletion (expected [1], got [0]) \
  diff_hash=fb3a5d385a9a896c424f47bf0ccb6732b816f3dfca35eae8f6336b64b5609629 \
  lane_diff_hash=5a85f0d642101317208383e7afc5fc07165208338fb7347ee3690f300fb9dbea porcelain_clean=yes
```

The suite reddens on the NAMED test (`m1` — the acceptance-§1 case) exactly
as required, then the file is restored (porcelain_clean=yes).

Second lead control, same method, on `plugins/leadv2/scripts/leadv2-lane-finish.sh`
(`s/REFUSED step=%s/REFUSED stage=%s/`): `test-lane-finish.sh` reddens on
`f1: refusal names the step` — the step-naming refusal line is load-bearing.

No mutation-control artifact exists for the trap-restore itself, by design:
mutating `leadv2-mutation-control.sh` while it is the executing process is
unsafe (bash parses scripts lazily by byte offset; a mutated file under a
running interpreter is undefined behaviour). The restore guarantee is
instead proven behaviourally by `l2` (kill mid-suite → file restored,
porcelain empty) and by l1/l3/l4 restoring on every verdict path.

## Приёмка §5 — artifacts

Under `docs/handoff/w-lead-last-mile/mutation-control/` (gitignored by the
`docs/handoff/*/*` blanket — force-added with this commit):

- `20260910T013154Z-live-48811.txt` — control A (merged-tree call removed → suite red)
- `20260910T013222Z-live-69805.txt` — control C (step= line broken → suite red)
- `20260910T013347Z-live-23849.txt` — dogfood run of the finish command on THIS lane

Control A artifact content (representative):

```
suite=plugins/leadv2/scripts/tests/test-land-merged-tree.sh
file=plugins/leadv2/scripts/leadv2-land.sh
anchor=/^  land_merged_tree_check "${LAND_TIP}" # MERGED-TREE-INSTRUMENT.*$/d
mode=live
baseline_rc=0
mutated_rc=1
red_line=FAIL - m1: rc=1 on outside-write-set deletion (expected [1], got [0])
diff_hash=fb3a5d385a9a896c424f47bf0ccb6732b816f3dfca35eae8f6336b64b5609629
lane_diff_hash=5a85f0d642101317208383e7afc5fc07165208338fb7347ee3690f300fb9dbea
porcelain_clean=yes
restored=yes
```

## Dogfood — the one command on THIS lane (real files, --dry-run)

```
leadv2-lane-finish: STEP suite ok (plugins/leadv2/scripts/tests/test-land-merged-tree.sh)
leadv2-lane-finish: STEP mutation ok (live, red proven, file restored, porcelain identical)
leadv2-lane-finish: STEP cleanliness ok (porcelain identical to pre-chain; empty-when-clean: yes)
leadv2-lane-finish: STEP land ok (worktree-5c6d0ff8014e --dry-run)
leadv2-lane-finish: CHAIN GREEN — lane=worktree-5c6d0ff8014e suite=... mutation=plugins/leadv2/scripts/leadv2-land.sh
```

## Honest limits, measured before any edit (brief §4)

- Root `~/Projects/leadv2` on `main`: **124 dirty entries, measured
  2026-09-10 before work started**: 122 untracked + 2 tracked-modified
  (`docs/leadv2/.compact-freeze.md`, `docs/leadv2/open-threads.md`). Both
  tracked entries are on land's state list (restored, not refused), and
  untracked entries are skipped by `land_hygiene_state` — so the land path
  TODAY does not refuse on them. The known `pass_unlanded cause=root_dirty`
  refusal named in the brief lives in
  `leadv2-dispatch-product-close.sh:4062` (T11), not in `land_hygiene_state`
  — and product-close is outside this lane's write set, so it is NOT fixed
  here. The finish command nevertheless surfaces the class honestly: if
  land ever refuses `reason=main_dirty`, finish prints its own
  `KNOWN-DEFECT ... 124-entry class` line when the dirty paths do not
  intersect the lane write set (separate row, not a bypass, not a fix here).
- **Pre-existing red, not caused by this lane** (file a separate row; the
  one-line fix is named): `tests: test-leadv2-land.sh` fails 30/49
  **identically on the HEAD snapshot before my edits** (verified via
  `git archive HEAD` run). Root cause: the suite's fixture copy-list
  (`_mk_case`) never copies `leadv2-portable-lock.sh`, which
  `leadv2-state-path.sh:121` now sources — so every land attempt in that
  fixture dies at ledger resolution before the flow under test runs. Fix
  for the follow-up row: add `leadv2-portable-lock.sh` to that copy list
  (my new suite already copies it).
- BSD sed gotcha hit while building the control: `\{...\}` is the interval
  operator on macOS sed, so anchors must leave `{`/`}` unescaped
  (`"${LAND_TIP}"` matches literally mid-pattern).

## Self-check (falsification set, raw)

```
bash -n OK: plugins/leadv2/scripts/leadv2-land.sh
bash -n OK: plugins/leadv2/scripts/leadv2-mutation-control.sh
bash -n OK: plugins/leadv2/scripts/leadv2-lane-finish.sh
bash -n OK: plugins/leadv2/scripts/tests/test-land-merged-tree.sh
bash -n OK: plugins/leadv2/scripts/tests/test-lane-finish.sh
bash -n OK: plugins/leadv2/scripts/tests/test-mutation-control-live.sh
bash-n-rc=0
```

No Python files changed (`py_compile`: nothing to compile).

`bash tests/run-all.sh --scope changed` (base=main@2b50797f, 6 changed files):

```
[CORE-OFFLINE] scope=changed running 7 of 95 suites (base=main@2b50797f97, 6 changed files, 0 unmapped)
[CORE-OFFLINE] suites passed=6 failed=1 missing=0 known_red_skipped=0
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-leadv2-land.sh (scope-selected ad-hoc)
[FAIL] plugins/leadv2/scripts/tests/run-core-offline.sh     (its 1 nested failure IS test-leadv2-land.sh)
[FAIL] plugins/leadv2/scripts/tests/test-leadv2-land.sh     (pre-existing, see Honest limits)
run-all: 8 passed, 2 failed, scope=changed
```

Both failures trace to the single pre-existing red above; the three new
suites are green inside the same run (18/25/30, 0 fail).

## Off-limits respected

`leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`,
`tests/test-route-arbiter.sh`, `config/leadv2-routing.yaml`,
`leadv2-router.sh`, `leadv2-claude-profile-select.sh`,
`lib/leadv2-claude-profile-pick.py` — untouched (diff is exactly the 6
write-set files).
