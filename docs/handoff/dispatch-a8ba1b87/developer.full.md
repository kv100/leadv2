verdict: APPROVE
next_action: review_round_2

# DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01 — developer report

## 1. What changed

Added a `# run-all-triggers: <stem> [<stem>...]` header (per `scan_suite_triggers()` in
`tests/run-all.sh`) to each of the 12 suite files that carry the 16 stem→suite mappings
named in the mission, all under `plugins/leadv2/scripts/tests/`:

| Suite file | Header added |
|---|---|
| test-lane-liveness-authoritative.sh | `leadv2-lane-liveness.sh` |
| test-lane-liveness-lies.sh | `leadv2-lanes-snapshot.sh leadv2-active-registry.sh` |
| test-lane-liveness-sentinel.sh | `leadv2-lane-liveness.sh` |
| test-lane-registry-self-deadlock.sh | `leadv2-dispatch-code.sh` |
| test-dispatch-terminal-deregisters-lane.sh | `leadv2-dispatch-ledger.sh` |
| test-dispatch-ledger-partial-close.sh | `leadv2-dispatch-code.sh` |
| test-dispatch-ledger-task-id.sh | `leadv2-dispatch-code.sh leadv2-dispatch-ledger.sh` |
| test-t-core-dispatch-ledger.sh | `leadv2-dispatch-ledger.sh` |
| test-status-surface-close-phase.sh | `leadv2-status-surface.sh` |
| test-status-surface-cwd.sh | `leadv2-status-surface.sh leadv2-state-path.sh` |
| test-status-surface-handle-identity.sh | `leadv2-status-surface.sh` |
| test-broad-status-relay-scope.sh | `leadv2-single-lead-beat-loop.sh leadv2-beat-owner.sh` |

12 files → 16 mappings (2 files carry 2 stems each). All 16 source scripts and all 12
suite files verified present on disk before writing headers.

**Deviation from the mission's mapping table (flagged, not silently fixed):** the mission
listed `leadv2-single-lead-beat.sh -> tests/test-broad-status-relay-scope.sh`. That script
does not exist:
```
$ find plugins/leadv2/scripts -maxdepth 1 -iname "*single-lead-beat*"
plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh
```
Per §6.5 (unrecognized-entity rule) I did not invent a near-name silently — I used the real
file, `leadv2-single-lead-beat-loop.sh`, since a header naming the wrong stem would be
exactly the "does nothing, looks like it works" trap this task exists to close.

**Second discrepancy, also flagged:** the mission states the 18th (non-16) mapping named a
suite that does not exist, `test-lanes-snapshot.sh`. That file DOES exist on disk, tracked
in git since commit `3d6b1f31` / `9451c0fc` (2026-08-17, SUPERVISOR-DELETE-01), currently
carries no `run-all-triggers` header, and is not part of the 16 named in this mission — left
untouched per "not yours to create/fix" scoping. Not investigated further (out of the
16-item scope); noting it here so it isn't lost.

Commits on this lane (`worktree-DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01`):
- `44055d6b` — the 12-file header addition (16 mappings)
- `18d53bb3` / `a2c22a73` — negative-control probe (remove header, then restore it) on
  `test-lane-registry-self-deadlock.sh`, kept as separate commits per "prefer new commits,
  never amend"; final state is byte-identical to `44055d6b`'s version of that file.

## 2. Sweep — suites with NO header at all (item 2 of the mission)

Walked the four suite directories `scan_suite_triggers()` scans
(`plugins/leadv2/scripts/tests`, `.claude/scripts/tests`, `plugins/leadv2/tests`, `tests`)
for `test-*.sh` files lacking `^# run-all-triggers:`:

```
TOTAL=387 NOHEADER=267
```

`.claude/scripts/tests` does not exist in this worktree (repos without `plugins/leadv2/`
fall through to it per the run-all.sh comment; not applicable here).

267 of 387 suites (69%) select on nothing but their own filename stem via the fallback
`add_suite "${ROOT}/.../test-${stem}.sh"` convention-match — the same class of darkness one
level down, exactly as the mission predicted. This is a large, repo-wide finding, NOT fixed
in this task per the mission's explicit scope limit ("FIX only the 16 above ... unless a
swept suite is trivially the same shape"). None of the 267 were "trivially the same shape"
as the 16 (the 16 all had a real prior EXTRA_SUITE_MAP row measured on a divergent branch;
the 267 have no such prior evidence of a real gap — asserting one for each would be
unverified). Full list of 267 file paths is in the raw sweep output (reproducible via the
command below); omitted here for length — ask if the enumerated list is wanted.

Reproduce:
```bash
for d in plugins/leadv2/scripts/tests .claude/scripts/tests plugins/leadv2/tests tests; do
  [[ -d "$d" ]] || continue
  find "$d" -maxdepth 1 -type f -name 'test-*.sh' | sort | while read -r f; do
    grep -q '^# run-all-triggers:' "$f" || echo "NOHEADER $f"
  done
done
```

## 3. Acceptance — CI selection proof (item 1)

Used `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed` (the runner's own
non-executing selection-proof seam) after appending a throwaway comment line to each source
script (reverted with `git checkout --` immediately after each probe). Three different
source scripts, verbatim:

**Proof 1 — `leadv2-lane-liveness.sh`:**
```
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh
run-all: 20 selected, scope=changed, select_only=1
```

**Proof 2 — `leadv2-dispatch-code.sh`:**
```
[SELECT] .../plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh
run-all: 39 selected, scope=changed, select_only=1
```

**Proof 3 — `leadv2-status-surface.sh`:**
```
[SELECT] .../plugins/leadv2/scripts/tests/test-status-surface-close-phase.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-status-surface-cwd.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-status-surface-handle-identity.sh
run-all: 8 selected, scope=changed, select_only=1
```

## 4. Negative control (item 2, mandatory)

**Confound found and corrected:** `run-all.sh`'s `--scope changed` self-selects any changed
`test-*.sh` file regardless of header content ("A changed test suite must select itself even
when its matching production file did not change in this run"). A naive negative control —
delete the header, touch the source, run `--scope changed` — still shows the suite selected,
because deleting the header is itself a diff to the test file. That would have produced
exactly the false "proof" this task's brief warns about (four such incidents cited
2026-09-04). Isolated it by:
1. Committing the header-removed state first (so the test file is *not* "changed" relative
   to the next probe's baseline),
2. running one throwaway `--scope changed` invocation to advance the runner's own
   last-checked-SHA state file (`$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha`)
   past that commit,
3. only then touching the *source* script and re-running.

Suite used: `test-lane-registry-self-deadlock.sh` (stem `leadv2-dispatch-code.sh`).

**Header removed, source touched — NOT selected (verbatim):**
```
run-all: 38 selected, scope=changed, select_only=1
```
(grep for `test-lane-registry-self-deadlock.sh` in the `[SELECT]` list: no match — compare
to Proof 2's 39-selected run, which includes it.)

**Header restored (commit `a2c22a73`), source touched again — selected (verbatim):**
```
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh
run-all: 39 selected, scope=changed, select_only=1
```

38 → 39 with the header present/absent, isolated from the self-selection confound: the
header, and only the header, drives selection here.

## 5. Running the 16 suites (item 3)

```
GREEN test-lane-liveness-lies.sh
GREEN test-lane-liveness-sentinel.sh
GREEN test-dispatch-terminal-deregisters-lane.sh
GREEN test-t-core-dispatch-ledger.sh
GREEN test-status-surface-close-phase.sh
GREEN test-status-surface-handle-identity.sh
GREEN test-broad-status-relay-scope.sh
RED test-lane-liveness-authoritative.sh
RED test-lane-registry-self-deadlock.sh
RED test-dispatch-ledger-partial-close.sh
RED test-dispatch-ledger-task-id.sh
RED test-status-surface-cwd.sh
COUNT: green=7 red=5 total=12
```

(12 files run, covering all 16 mappings — the two multi-stem files each ran once.)

**Findings — NOT fixed, NOT added to `tests/known-red-suites.txt`, list only shrinks per
constraint:**

1. `test-lane-liveness-authoritative.sh` — `[TEST] FAIL: D6 -- degradation ladder dropped a
   lane`:
   ```
   AssertionError: ('expected 1 lane token + +2 drop counter, got',
   ['1·?·0s', '+2', '|', 'Test', 'in', '.../ladder-repo', '|', 'cc 29%·7d/9h27m', ...])
   ```
2. `test-lane-registry-self-deadlock.sh` — `passed=14 failed=1`:
   ```
   [TEST] FAIL: (c) probe-read file set changed:
   ```
3. `test-dispatch-ledger-partial-close.sh` — all 5 sub-cases fail at setup, not assertion:
   ```
   - 4: setup — first dispatch or process-death wait failed (rc=3)
   - 5: setup — first dispatch or process-death wait failed (rc=3)
   - 6: setup — first dispatch or process-death wait failed (rc=3)
   - 7/missing: setup — first dispatch or process-death wait failed (rc=3)
   - 7/malformed: setup — first dispatch or process-death wait failed (rc=3)
   ```
4. `test-dispatch-ledger-task-id.sh` — `5 passed, 9 failed`:
   ```
   [TEST] FAIL: F4: no --task-id collision (got name=[], want OPS-42)
   [TEST] FAIL: F4b: identity lookup (got name=[], want 'Totally unrelated record')
   ```
5. `test-status-surface-cwd.sh` — `4 passed, 3 failed`:
   ```
   [TEST] FAIL: cwd-invariance: supervisor row differs by cwd (root='' home='' tmp='')
   ```

All 5 failures are pre-existing suite content (fixture/assertion logic), untouched by this
task — the only edit made to any of these 5 files was the one-line header comment. Not
established against clean `main` (out of the 30-tool-call budget for this lane; flagging
per "establish whether it fails on clean main too before touching it" — I did not touch
their content, so this is moot for THIS task, but worth a follow-up lane).

## 6. Self-check (falsification set)

```
$ /bin/bash -n <each of the 12 changed suite files> tests/run-all.sh
OK (all 13 files)
```
No Python files changed — `py_compile` step not applicable.

```
$ git status --short
 M docs/LEAD_V2_STATE.md   # lead-owned, not touched by this lane, left alone
```
(clean otherwise; all lane work committed)

DELIVERABLE_COMPLETE
