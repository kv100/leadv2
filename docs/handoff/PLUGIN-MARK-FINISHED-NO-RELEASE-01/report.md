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

## Round 3

### Branch traced before the fix

The successful-but-unreleased path was the stale-only terminal loop at
`plugins/leadv2/scripts/leadv2-active-registry.sh:1001-1006`. It selected the
correct `dispatch-2c6e1405` task id, but only stamped terminal fields and
`stale: true`. The measured row was already `stale: true`, so this path could
return `0` while retaining its material `writes` claim. The dispatch-time
overlap reader can inspect that claim once liveness has resolved the row as
alive; it does not treat the row's stale flag as a substitute for an absent
claim.

### Fix and live-shape fixture

`mark_finished` now removes both supported claim keys, `writes` and the
legacy `write_set`, for every matching non-recovery-owned duplicate at
`leadv2-active-registry.sh:1001-1008`. Its post-write readback now refuses
with `rc=9` if any matching row remains live, lacks the requested terminal
status, or still carries either claim key (`:1169-1192`). The terminal
tombstone remains, so PULSE-01 status reads are preserved.

Test 2 copies the live row shape into a fixture, including:

```
session_id: s-20260915T030041Z-1-62617
task_id: dispatch-2c6e1405
phase: spawning
stale: true
dead_at: '2026-09-15T08:25:42Z'
updated_at: '2026-09-15T08:27:14Z'
lane_events: [{at: '2026-09-15T08:25:42Z', event: reconciled_dead}]
```

It retains the supplied `writes` string verbatim, invokes the real
`leadv2-writes-overlap.sh` with a fixture liveness result, and re-reads
`active.yaml` after `mark_finished`. The observed dispatch-time result is a
conflict before finish and no conflict after finish; the re-read also requires
that neither claim key remains. Test 3 retains the duplicate-row property;
Test 4 retains the unregistered non-zero property; Test 5 retains the
atomic-write corruption property.

### Focused regression, restored green

```
$ bash -n plugins/leadv2/scripts/leadv2-active-registry.sh
$ bash -n plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
$ timeout 120 bash plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
[TEST] PASS: 1: bash -n leadv2-active-registry.sh
[TEST] PASS: 2: copied live stale/dead/spawning dispatch row loses material writes claim (overlap before=hit after=clear)
[TEST] PASS: 3: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)
[TEST] PASS: 4: unregistered task_id -> rc=4 (non-zero), active.yaml byte-identical
[TEST] PASS: 5: forced os.replace rc=1 and forced yaml.dump rc=1 leave active.yaml byte-identical

=== Results: 5 passed, 0 failed ===
```

### Negative controls — all RUN via `leadv2-mutation-control.sh`

#### 1. Restore stale-only release — RED, then restored green

Artifact: `mutation-control/20260915T085645Z-live-86290.txt`.

```
suite=plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
file=plugins/leadv2/scripts/leadv2-active-registry.sh
anchor=s/target.pop("writes", None)/target["writes"] = target.get("writes")/
mode=live
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 2: before=[task=CANDIDATE other=dispatch-2c6e1405 paths=plugins/leadv2/scripts/leadv2-orphan-reaper.sh] finish_rc=9 after=[task=CANDIDATE other=dispatch-2c6e1405 paths=plugins/leadv2/scripts/leadv2-orphan-reaper.sh] released=False
porcelain_clean=yes
restored=yes
```

Restored suite line:

```
[TEST] PASS: 2: copied live stale/dead/spawning dispatch row loses material writes claim (overlap before=hit after=clear)
```

#### 2. Restore first-match-only release — RED, then restored green

Artifact: `mutation-control/20260915T085745Z-live-21919.txt`.

```
suite=plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
file=plugins/leadv2/scripts/leadv2-active-registry.sh
anchor=s/targets = \[s for s in sessions if s.get("task_id") == task_id\]/targets = [next(s for s in sessions if s.get("task_id") == task_id)]/
mode=live
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 3: before_a/b=5/5 finish_rc=9 after_a/b=0/5 released=False
porcelain_clean=yes
restored=yes
```

Restored suite line:

```
[TEST] PASS: 3: two duplicate rows released (before a/b=5/5, after a/b=0/0, rows=2 stale=True)
```

#### 3. Restore a truncating direct write — RED, then restored green

Artifact: `mutation-control/20260915T085818Z-live-43634.txt`.

```
suite=plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh
file=plugins/leadv2/scripts/leadv2-active-registry.sh
anchor=s|os.replace(tmp_path, yaml_path)|with open(yaml_path, "w", encoding="utf-8") as _trunc: yaml.dump(data, _trunc, default_flow_style=False, sort_keys=False)|
mode=live
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 5: replace_rc=1 replace_intact=0 dump_rc=4 dump_intact=0
porcelain_clean=yes
restored=yes
```

Restored suite line:

```
[TEST] PASS: 5: forced os.replace rc=1 and forced yaml.dump rc=1 leave active.yaml byte-identical
```

### Required falsification set and changed-scope runner

The shell syntax checks and focused five-property suite above are the required
falsification set. No standalone Python files changed; the embedded Python
writer is executed by the focused fixture.

Raw bounded changed-scope command and terminal result:

```
$ LEADV2_SUITE_LOCK_WAIT_S=1 LEADV2_RUN_ALL_SUITE_TIMEOUT_S=30 timeout 180 bash tests/run-all.sh --scope changed
[CORE-OFFLINE] FATAL lock_timeout file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-05b67577.lock wait_s=1 holder=pid=68139 host=UA-K-VLASENKO-LT-2.local since=2026-09-15T09:02:12Z
[SUITE-TIMEOUT] tests/test-status-surface-bash32.sh exceeded 30s ceiling (killed by run-all; counted as a blocking failure with a named cause)
[TEST] FAIL: Test 1: expected rc=0, got rc=1
[TEST] FAIL: Test 2b: control did not behave as expected (baseline_rc=1 mutated_rc=1 mutant_is_red=1 restored_rc=1)
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/test-codex-session-runner.sh exceeded 30s ceiling (killed by run-all; counted as a blocking failure with a named cause)
CHANGED_SCOPE_RC=124
```

The changed-scope runner did not reach a green terminal verdict: its first
core-offline attempt was lock-refused by a stale holder record, and the bounded
run then timed out after reporting the named unrelated failures above. The
focused regression completed green after all mutations; no live registry file
was read or edited by this work.

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

## Round 3 completion

The Round 3 evidence above is the final append-only result: the stale-only
success path was replaced with material write-claim removal, the copied live
shape is green, all three live mutation controls went red and restored, and
the changed-scope runner's non-green bounded result is recorded verbatim.

DELIVERABLE_COMPLETE
