# C5 — GATE-DISCOVERS-246-UNTRACKED-SUITES-01: suite discovery refuses untracked suites

Lane branch: `worktree-C5-UNTRACKED-DISCOVERY` · baseline commit `f206d3ed` · 2026-09-09.

Deliverables: `plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh` (the admission
contract) + `plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh` (the
control suite) + `run-all-wiring.patch` (the finding — see §5). **The wiring is NOT
applied in this lane**: `tests/run-all.sh` is B2's file; the mission forbids taking it.

## 1. The measurement, re-derived (my numbers win, and they agree)

Taken 2026-09-09 against the main checkout (`~/Projects/leadv2`), read-only:

```
$ git ls-files .claude/scripts/tests | wc -l
       0
$ ls .claude/scripts/tests/test-*.sh | wc -l
     246
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | wc -l
     894
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -c '^[-a-z0-9._]*:\.claude/scripts/tests/'
0
$ grep -l "^# run-all-triggers:" .claude/scripts/tests/test-*.sh | wc -l
       0
```

246 `test-*.sh` files, none tracked, none in the trigger map (882 at B6 merge →
894 now, growth from other lanes, none of it from the untracked tree). C1's
producer fix removed nothing — confirmed, the 246 are all still there.

Admission lib against both trees (tracked set before vs after — property 3):

```
$ bash plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh --root <worktree> 2>/dev/null | wc -l
     532            # worktree (no .claude/scripts/tests present): 532 admitted, 0 refused
$ bash plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh --root <main> 2>err | wc -l ; grep -c 'UNTRACKED-SKIP.*not tracked' err
     532 ; 247      # main: SAME 532 admitted + 246 refused by name + 1 count line
$ tail -1 err
suite-discovery: [UNTRACKED-SKIP] 246 suite file(s) refused: not tracked by git (stage or commit to admit; run directly while authoring) — GATE-DISCOVERS-246-UNTRACKED-SUITES-01
```

Nothing tracked stops running: 532 admitted in both trees, byte-identical sets.

## 2. Selection proof — the suite registers itself (stateless oracle)

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | wc -l
     895                                        # was 894 before this lane: +1, nothing removed
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -n 'leadv2-suite-discovery:'
802:leadv2-suite-discovery:plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh
```

Map rows 894 → 895: the only delta is this lane's own row. `--scope changed`
selects the suite on any change to the lib (header: `# run-all-triggers:
leadv2-suite-discovery`).

## 3. Negative controls (E2E-KILLRATE-01) — both run, red then green

Both mutations are declared in the suite header and land INSIDE
`leadv2_suite_is_admitted`'s function body (never top level). Artifacts from
`leadv2-mutation-control.sh` live in `mutation-control/` (this directory).

**M1 — the symptom (gate disabled → untracked executes again):**

```
$ plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
    plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh \
    's|1) return 1 ;;  # c5-mut-1: untracked -> refused|1) return 0 ;;|' \
    docs/handoff/C5-UNTRACKED-DISCOVERY/
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh file=plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh red_line=FAIL: case1 rc=1 (expected 0) diff_hash=cfc0f413343c189f40bbd0b910b73d6e89d70b490aa47f8855a8fb2f025bb60f lane_diff_hash=49dffba18ceb39484334859c8640fa0393e20bb85ada05013929381f5ca8f15d
```

Red because the planted poison suite EXECUTES (marker present, run-all rc=1)
— the exact original symptom, reintroduced.

**M2 — the guard (refuse everything → the green that runs nothing):**

```
$ plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh \
    plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh \
    's|0) return 0 ;;  # c5-mut-2: tracked -> admitted|0) return 1 ;;|' \
    docs/handoff/C5-UNTRACKED-DISCOVERY/
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh file=plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh red_line=FAIL: case1 [RUN] rows = 0 (expected 2) diff_hash=d30f3142de96fb25c9b15a95d2963fa520bf4fbf66ac345d64fd367479816268 lane_diff_hash=49dffba18ceb39484334859c8640fa0393e20bb85ada05013929381f5ca8f15d
```

Red because tracked suites stop running — counted as 0 `[RUN]`/`[SELECT]`
rows and vanishing tracked trigger rows. A green that ran nothing is what
this control exists to catch.

**Green baseline** (no mutation): 28/28 assertions pass — full output in §6.

## 4. Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh && echo SYNTAX-OK
SYNTAX-OK
$ bash -n plugins/leadv2/tests/test-discovery-refuses-untracked-suites.sh && echo SYNTAX-OK
SYNTAX-OK
```

No Python files were changed by this lane, so `python3 -m py_compile` has
nothing to compile — the only artifacts are the two shell files above.
The control-suite green run and the changed-scope runner output: §6.

## 5. The finding: the fix requires two lines in tests/run-all.sh (B2's file)

The mission forbids writing `tests/run-all.sh`, and run-all deliberately
sources nothing from the plugin tree (it must run standalone in scratch
fixture repos). The contract therefore ships as a subprocess lib, and the
wiring is `docs/handoff/C5-UNTRACKED-DISCOVERY/run-all-wiring.patch` —
a 38-line unified diff, verified `git apply --check` clean against
`tests/run-all.sh` at this lane's HEAD. Two sites:

1. `--scope all` selection (`tests/run-all.sh:463`) — the execution vector
   for the 246: the four-root `find` becomes one call to the lib through a
   temp list; a lib failure is `exit 2` (never consume an unproven list).
   Full per-name `[UNTRACKED-SKIP]` output — the nightly sweep is where a
   human reads the whole list.
2. `scan_suite_triggers` (`tests/run-all.sh:338`) — the header walk: a
   trigger header planted on an untracked file would otherwise inject rows
   and reach execution via `--scope changed` (dormant today: 0 of the 246
   carry headers — but it is the same contract hole one `git status` away).
   Wired with `--skip-report=count`: one proportional line, no 246-line spam
   on every invocation.

The control suite applies this exact patch to a scratch COPY of the real
run-all.sh (python asserts each anchor occurs exactly once — drift in
run-all reddens the suite loudly instead of testing a stale carrier), so the
pair that will actually ship — lib + wiring — is what the controls prove.

**Scan-root question (mission §4):** `.claude/scripts/tests` should NOT stop
being a scan root. It is the per-repo fallback root (`run-all.sh:244` falls
back to `.claude/scripts/tests/run-core-offline.sh` in repos without
`plugins/leadv2/`, e.g. persona-engine, m3-market) and `run-core-offline.sh`
resolves suite tokens through it (`:650`). Deleting the root would break
those repos' discovery; the admission filter keeps the root honest instead.
Nothing was deleted: all 246 files remain on disk, now loudly skipped by
name instead of silently executed.

## 6. Control-suite green run + changed-scope runner

Control suite, green (no mutation) — raw:

```bash
PASS: bash -n clean (lib)
PASS: bash -n clean (tests/run-all.sh)
PASS: wiring patch applied (both anchors, exactly once)
PASS: case1 rc=0 (tracked pass, untracked refused)
PASS: case1 poison suite NOT executed (marker absent)
PASS: case1 ran exactly the 2 tracked suites
PASS: case1 alpha ran
PASS: case1 beta ran
PASS: case1 poison absent from stdout
PASS: case1 poison named in [UNTRACKED-SKIP]
PASS: case1 ghost named in [UNTRACKED-SKIP]
PASS: case1 skip count reported (2)
PASS: case2 LIST_TRIGGERS rc=0
PASS: case2 tracked alpha row present
PASS: case2 tracked beta row present
PASS: case2 ghost row refused
PASS: case2 scan-side refusal counted (count mode)
PASS: case2 count mode proportional (no name spam)
PASS: case3 selected exactly the 2 tracked suites
PASS: case3 both tracked suites selected
PASS: case4 lib rc=0 on a git root
PASS: case4 lib lists exactly the 2 tracked suites
PASS: case4 names mode names the refused
PASS: case4 count-mode rc=0
PASS: case4 count mode summary-only
PASS: case4 no --root refused (rc 2)
PASS: case4 bad --skip-report refused (rc 2)
PASS: case4 non-git root refused by name (rc 2)
c5-discovery: PASS=28 FAIL=0
rc=0
```

<!-- CHANGED-SCOPE-RUNNER-OUTPUT -->
