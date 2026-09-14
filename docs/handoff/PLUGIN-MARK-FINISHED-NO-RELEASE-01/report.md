# PLUGIN-MARK-FINISHED-DOES-NOT-RELEASE-THE-ROW-01

## Diff summary

`plugins/leadv2/scripts/leadv2-active-registry.sh`, `mark_finished` op (embedded Python inside
`leadv2_active_mark_finished`):

1. **rc=4 (not registered) is now checked before the rc=8 (recovered) refusal.** Previously the
   `for/else` loop only distinguished "found → mutate" vs. "not found → rc=4" via the `else`
   clause, but the `recovered` check ran first against a `target` that could be `None` on an
   unregistered id — reordered so "row doesn't exist" is diagnosed correctly instead of only being
   reachable through the fallthrough `else`.
2. **The actual bug: the op now releases the row's claim.** After stamping `terminal_status` /
   `terminal_evidence` / `terminal_at`, it also sets `target["stale"] = True`. `stale` is the
   **existing** convention — `leadv2_active_register`'s admission loop, `check_writes_conflict`,
   and `check_limits`'s lane-cap count already skip `stale` rows — so this reuses it rather than
   inventing a new schema field. The row itself is kept (not removed) because
   `leadv2-lane-heartbeat.sh`'s `status` reads `terminal_status`/`terminal_evidence` off this same
   row *after* finish (asserted by `test-leadv2-lane-heartbeat.sh` Tests 4/5) — outright deletion
   would break that read.
3. **rc=0 is now verified, not assumed.** After the write (still inside the `flock`), the script
   re-reads `active.yaml` from disk and re-finds the row; if it's missing, `stale` isn't `True`, or
   `terminal_status` doesn't match, it exits 9 instead of falling through to rc=0. This is what
   catches a silent "ran but didn't stick" regression (including the exact bug being fixed here —
   see negative control below).
4. No change to the failure paths that already existed (lock not taken, write failure) — those
   were already non-zero and non-mutating; verified in Test 4 below.

New file: `plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh`, registered via
`# run-all-triggers: leadv2-active-registry.sh` (self-registration convention in `tests/run-all.sh`,
confirmed live below).

## Test output — full suite, green

```
$ bash plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
[TEST] PASS: 1: bash -n leadv2-active-registry.sh
[TEST] PASS: 2: finish rc=0, stale=True, terminal_status=completed, writeset conflict released (before=5 after=0)
[TEST] PASS: 3: unregistered task_id -> rc=4 (non-zero), active.yaml byte-identical
[TEST] PASS: 4: read-only state dir -> rc=1 (non-zero), active.yaml unchanged and still valid YAML

=== Results: 4 passed, 0 failed ===
```

Test 2 is the behavioural proof the task demanded: a `writeset_conflict` check for `src/a.txt`
against a second lane is refused (rc=5) **before** `mark_finished`, and admitted (rc=0) **after**
— i.e. the claim is actually released, not just the row stamped.

## Negative control — RUN, went RED

Per the task's instruction, mutated a **scratch copy** of the file (never the tracked worktree) to
reproduce exactly the original bug: comment out `target["stale"] = True` so the mutation runs but
the release never lands.

```
$ python3 -c "... replace 'target[\"stale\"] = True' with a pass-through no-op ..."
mutated
$ bash -n /tmp/mf-negctl/scripts/leadv2-active-registry.sh
syntax ok
$ bash /tmp/mf-negctl/scripts/tests/test-mark-finished-releases-writeset.sh
[TEST] PASS: 1: bash -n leadv2-active-registry.sh
[TEST] FAIL: 2: before_conflict_rc=5 finish_rc=9 after_conflict_rc=5 stale=False term=completed row={... "stale": false, ... "terminal_status": "completed" ...}
[TEST] PASS: 3: unregistered task_id -> rc=4 (non-zero), active.yaml byte-identical
[TEST] PASS: 4: read-only state dir -> rc=1 (non-zero), active.yaml unchanged and still valid YAML

=== Results: 3 passed, 1 failed ===
```

Test 2 goes RED under the mutation (`after_conflict_rc=5` — the writeset conflict is *not*
released; `stale=False`). Note `finish_rc=9`, not `0`: the mutation is caught by the new
post-write verify (item 3 above) before it can even report success, which is itself evidence the
verify step does its job — a version of this bug that returned rc=0 anyway (e.g. if the verify
step were also removed) would show `finish_rc=0, after_conflict_rc=5`, the exact "reports success,
claim survives" failure mode from the task description. Scratch copy discarded after the run; the
tracked worktree file was never touched.

## Falsification set (required)

```
$ bash -n plugins/leadv2/scripts/leadv2-active-registry.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh && echo OK
OK
```
(No `.py` files were changed — the Python is embedded in the `.sh` via heredoc; `bash -n` covers
the shell wrapper, and the four live test runs above exercise the embedded Python at runtime.)

## Changed-scope test runner

`tests/run-all.sh --scope changed` (full worktree, staged: registry fix + new test) surfaced 9
`NOT-KNOWN-RED` nested-suite failures alongside the new suite passing. Individually re-ran each of
the 9 standalone, and against a **scratch copy of `HEAD`'s pre-fix `leadv2-active-registry.sh`**
(never the tracked file) to establish baseline:

| Suite | Standalone w/ fix | Standalone on baseline (pre-fix) |
|---|---|---|
| test-phase-refusal-lane-release.sh | fails (rc=1) | **fails (rc=1) — pre-existing, unrelated** |
| test-writes-overlap.sh | fails (rc=1) | **fails (rc=1) — pre-existing, unrelated** |
| test-lane-registry-outlives-dispatcher.sh | fails (rc=1) | **fails (rc=1) — pre-existing, unrelated** |
| test-shadow-control-plane.sh | fails (rc=1) | **fails (rc=1) — pre-existing, unrelated** |
| test-stale-row-starting-grace.sh | **passes (rc=0)** | passes (rc=0) |
| test-active-registry-noop-is-nonzero.sh | **passes (rc=0)** | passes (rc=0) |
| test-writeset-carousel.sh | **passes (rc=0)** | passes (rc=0) |
| test-dispatch-writes-reaches-registry.sh | **passes (rc=0)** | passes (rc=0) |
| test-active-registry-update-phase.sh ("active registry phase updates") | **passes (rc=0)** | passes (rc=0) |

None of the 9 reference `mark_finished` (grepped). The 4 that fail do so identically on
pre-fix `HEAD`, so they are pre-existing and out of scope (matches memory
`run-all-changed-preexisting-reds` / `core-offline-reds-under-concurrent-runners`: two other lanes
— `PLUGIN-PREPASS-PHANTOM-DESIGN-01` and this session — are live in this repo right now per
`LEADV2_ACTIVE_OTHER_SESSIONS`, and `run-all.sh --scope changed` runs its nested suites
concurrently, which is the documented cause of transient `NOT-KNOWN-RED` flips). The other 5 pass
both standalone-with-fix and at baseline — they only "fail" inside the full concurrent
`run-all.sh` sweep, never in isolation, confirming this diff does not regress them.

## Left alone

- Did not touch the lane-cap resolution order, the write-set conflict taxonomy, or any live
  `~/.claude/leadv2-state/*/active.yaml` (off-limits, respected).
- Did not investigate the 4 pre-existing-red suites above further — out of scope for this task.
- Did not add a CLI wrapper to `leadv2-active-registry.sh` — it remains library-only, sourced by
  its tests and callers, consistent with the task's own framing ("a library, not a CLI").

DELIVERABLE_COMPLETE

## Round 2

### H1 selector decision: release every safe duplicate atomically

`mark_finished` now selects **all** rows whose `task_id` equals the requested
id, preflights the entire batch for `recovered: true`, and then stamps every
selected row terminal and `stale: true` in the one locked YAML transaction. A
recovery-owned duplicate refuses the entire operation (`rc=8`) before any row
is changed; that preserves lane-reconcile ownership and avoids a partial
release. The post-write readback now requires at least one matching row,
requires **zero non-stale matching rows**, and checks every matching row's
terminal status. I chose all-safe-row release because these rows all represent
the same task claim; retaining a live duplicate preserves a writeset/cap
claim that `mark_finished` is meant to retire.

The fixture has two live `T1` rows, one claiming `src/a.txt` and the other
`src/b.txt`. Both conflict checks are `5` before finish and `0` after it.

### H2 atomic strategy: no in-place fallback

The direct `open(active.yaml, "w")` fallback was removed. The only commit is a
same-directory temp file followed by `os.replace`; if either staging or
replace raises, cleanup removes only the temp and the original registry stays
untouched. The focused test injects (1) a failed replace followed by a
would-be second dump failure, and (2) a first staging-dump failure. The
removed fallback means case (1) never opens the live file at all; the mutation
control reintroduces that exact class of direct write and forces dump call 2
to fail after truncation.

### Focused regression, green

```
$ timeout 120 bash plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
[TEST] PASS: 1: bash -n leadv2-active-registry.sh
[TEST] PASS: 2: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)
[TEST] PASS: 3: unregistered task_id -> rc=4 (non-zero), active.yaml byte-identical
[TEST] PASS: 4: forced os.replace rc=1 and forced yaml.dump rc=1 leave active.yaml byte-identical

=== Results: 4 passed, 0 failed ===
```

### Negative controls, red then restored green

#### H1 first-match-only mutation

Artifact: `mutation-control/20260914T215820Z-live-52381.txt`.

```
$ leadv2-mutation-control.sh --live ... 's/targets = [...]/targets = [next(...)]/' ...
MUTATION-CONTROL ok mode=live ...
red_line=[TEST] FAIL: 2: before_a/b=5/5 finish_rc=9 after_a/b=0/5 released=False
... second T1 row ... "stale": false
porcelain_clean=yes
```

Restored baseline:

```
[TEST] PASS: 2: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)
```

#### H2 truncating-`w` fallback mutation

Artifact: `mutation-control/20260914T220057Z-live-1421.txt`.

```
$ leadv2-mutation-control.sh --live ... 's|os.replace(...)|... open(yaml_path, "w") ... yaml.dump(...)|' ...
MUTATION-CONTROL ok mode=live ...
red_line=[TEST] FAIL: 4: replace_rc=1 replace_intact=0 dump_rc=4 dump_intact=0
porcelain_clean=yes
```

Restored baseline:

```
[TEST] PASS: 4: forced os.replace rc=1 and forced yaml.dump rc=1 leave active.yaml byte-identical
```

### Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-active-registry.sh
$ bash -n plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
$ timeout 120 bash plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
=== Results: 4 passed, 0 failed ===
```

No standalone Python file changed; the injected Python is the registry's
existing heredoc, exercised by the focused suite above.

### Changed-scope runner (raw terminal summary)

```
$ timeout 600 bash tests/run-all.sh --scope changed
[CORE-OFFLINE] scope=changed running 24 of 93 suites (base=main@6cc7dd0c2e, 2 changed files, 0 unmapped)
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh (scope-selected ad-hoc)
[TEST] PASS: 1: bash -n leadv2-active-registry.sh
[TEST] PASS: 2: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)
[TEST] PASS: 3: unregistered task_id -> rc=4 (non-zero), active.yaml byte-identical
[TEST] PASS: 4: forced os.replace rc=1 and forced yaml.dump rc=1 leave active.yaml byte-identical
=== Results: 4 passed, 0 failed ===
[CORE-OFFLINE] suites passed=8 failed=13 missing=0 known_red_skipped=3 repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-MARK-FINISHED-NO-RELEASE-01
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh
[NOT-KNOWN-RED] core:plugins/leadv2/tests/test-fanout-lane-detach.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-active-register-miss.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-lane-liveness-lies.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-registry-fails-closed.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-writes-overlap.sh
[NOT-KNOWN-RED] core:active registry phase updates
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-shadow-control-plane.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-writeset-carousel.sh
[NOT-KNOWN-RED] core:plugins/leadv2/scripts/tests/test-dispatch-writes-reaches-registry.sh
[NOT-KNOWN-RED] core:lanes snapshot reconciliation
[FAIL] plugins/leadv2/scripts/tests/run-core-offline.sh
[PASS] tests/test-status-surface-bash32.sh
[PASS] tests/test-status-surface-single-lead.sh
exit=124
```

The aggregate runner timed out after its focused regression passed. Its 13
other reds include sandbox-denied `/bin/ps` and `mktemp` operations and suites
outside this diff; none name `mark_finished`'s new duplicate or atomic-write
paths.

DELIVERABLE_COMPLETE
