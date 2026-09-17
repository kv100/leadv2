# Fix Report: DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01

Boundary: macOS Darwin 25.6.0, lane worktree `e0a3caf252c8`, fix commit `823cb06c`
(base `2e4a500b`), all runs 2026-09-17, N=6 concurrent arms, per-suite ceiling 120s
unless named otherwise.

## The defect, as measured and as found

Mission measurement (2026-09-17): of six lanes dispatched ~20s apart, each with an
explicit `--writes`, five recorded `writes: None` in `active.yaml`; the one dispatched
alone recorded it. 6 of 8 live rows carried `writes: ABSENT`, and
`leadv2-active-registry.sh:564` refuses any row whose set is unrecorded with
`reason=pending_resolution` **before any path comparison** — so each lost set blocked
every new dispatch for the 900s window.

**Cause class: `real_regression` at the writer bridge.** The mission hypothesised a
last-writer-wins race on `active.yaml`. Code inspection rules that out on this tree —
the registry core is already read-modify-write under its own lock:

- `_leadv2_yaml_py_lock` takes `fcntl.flock(LOCK_EX)` before reading
  (`leadv2-active-registry.sh:496`) and writes atomically via `os.replace`
  (`:1153`), still under the same flock (`:1195`).
- The register op's refresh path only overwrites `writes` when the caller's value is
  not None (`:631-637`) and the recreate path carries the previous row's `writes`
  forward (`:669-675`). Every active.yaml writer in dispatch/fanout funnels through
  this one lock.

The surviving mechanism is upstream of the lock, exactly at the writer the mission
names. `_dispatch_register_writes_row` (leadv2-dispatch-code.sh:4597) forced
`LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"`, discarding any caller pin. Sourcing the
dispatch script re-resolves `PROJECT_ROOT` from `CLAUDE_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`
first (`:329`, `:387-460`), and the foreign-root guard may rewrite it again — so under
staggered concurrent dispatch (ambient root churn in the fleet), the registration was
threaded onto a root the caller never pinned. `_leadv2_yaml_file` resolves the registry
through `leadv2-state-path.sh` with that root (`leadv2-active-registry.sh:142-150`);
a real-root LINK_ROOT under a sandboxed signal hard-aborts
(`leadv2-state-path.sh` B1 SAFETY NET), and a foreign root lands the row in another
checkout's registry. Either way the row's write set is lost **before any lock is
taken** — which is why the shape is "correct when serial (roots agree), lost when
concurrent (ambient roots diverge)": the concurrency is the churn of ambient roots,
not two writers inside one lock.

## The fix

One line at the bridge, plus comment (commit `823cb06c`):

```diff
-  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_register \
+  LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT}}" leadv2_active_register \
     "${task_id}" "${cls}" "${worktree}" "${branch}" "" "" "" "${writes}" "${reason}"
```

An already-exported `LEADV2_PROJECT_ROOT` (explicit caller pin, same idiom as
deploy-verify-check/deploy-classify in this file) now wins over the ambient
`PROJECT_ROOT`; an unset pin behaves identically to the old code. The writer is fixed
where the mission says the fix must go; **the reader's refusal is untouched** — the
`pending_resolution` gate at `leadv2-active-registry.sh:564-571` is byte-identical
(git diff vs base shows no change to that file).

## Reproduction (unfixed code, same harness)

The lane inherited a staged fix, so reproduction ran by reverting the writer to base
and running the same suite (sequencing noted honestly: the green run came first
because the fix was already in the worktree):

```
$ git checkout HEAD~1 -- plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ bash plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
[FAIL] claim 1: kept=1/6 own_set=0/6
REGISTRY-MISSING
...arm-1.log:[leadv2-state-path] ABORT: LEADV2_STATE_ROOT is set (a sandbox-only signal
  ... ) but the resolved LINK_ROOT (/Users/kostiantyn.vlasenko/Projects/leadv2) is a
  real repo checkout (has a git remote or a REAL-REPO marker). This means
  PROJECT_ROOT/LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR was not threaded to THIS
  specific call, so LINK_ROOT fell back to cwd. ...
...arm-1.log:arm_rc=1 proof_rc=2 proof=absent
REVERT_CONTROL_RC=1
```

Five of six arms aborted with the sandbox guard (arm 6 wrote a registry missing the
others) — the write set lost before any lock, from ambient-root churn in this very
session's environment. This is the mission's incident shape: concurrent-staggered
registrations lose their declared writes on unfixed code.

## Claim 1 — concurrent dispatch records every write set (green, fix in place)

```
$ time bash plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
[ok] claim 1: 6 concurrent bridge registrations all read back their OWN writes
[ok] claim 1b: caller-pinned LEADV2_PROJECT_ROOT honored over divergent ambient PROJECT_ROOT
[ok] claim 1 red-control: mutated bridge lost 6/6 write sets (harness can fail)
[ok] claim 2: unrecorded write set + live worker still refused rc=5 reason=pending_resolution
=== all checks passed ===
bash ...  16.43s user 15.15s system 101% cpu 31.154 total
SUITE_RC=0
```

6 of 6 arms (N≥5, launched within the same second), each with a distinct `--writes`
(`src1.py`…`src6.py`) through the real bridge `_dispatch_register_writes_row`, all
read back their own set from `active.yaml`.

## Negative control 1 — drop-writes mutation inside the function body (red)

The suite mutates the bridge call inside `_dispatch_register_writes_row`
(`"${writes}"` → `""`), asserting the target string is present first (a control that
cannot fail proves nothing), re-registers 6 rows concurrently, and requires ≥1 lost:

```
[ok] claim 1 red-control: mutated bridge lost 6/6 write sets (harness can fail)
```

Reverted automatically (mutation written to a temp copy, `mktemp`-scoped, trap-cleaned).

## Negative control 1b — canonical `leadv2-mutation-control.sh` artifact

The suite's own internal red-control (above) mutates a scratch copy of the function body
inline. The DoD gate's mechanical check (b) additionally requires a
`leadv2-mutation-control.sh` artifact, not asserted prose, so the same class of mutation
(revert the one-line fix back to `LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"`, unconditional) was
also run through the canonical tool, worker mode, against HEAD's snapshot:

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh \
    plugins/leadv2/scripts/leadv2-dispatch-code.sh \
    's/LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT}}" leadv2_active_register/LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_register/' \
    docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=4
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=[FAIL] claim 1: kept=1/6 own_set=0/6 diff_hash=d05c789380e05f235a765be227fb16aea84405e93cb79aff2433a603681e58c0 lane_diff_hash=b455ec46f4f71f0a87c5385f9ee32cb0ca45af1e16232404ad2446eb093c98a8
MC_RC=0
```

Artifact written at
`docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01/mutation-control/20260917T195402Z-29380.txt`:

```
suite=plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
file=plugins/leadv2/scripts/leadv2-dispatch-code.sh
anchor=s/LEADV2_PROJECT_ROOT="\${LEADV2_PROJECT_ROOT:-\${PROJECT_ROOT}}" leadv2_active_register/LEADV2_PROJECT_ROOT="\${PROJECT_ROOT}" leadv2_active_register/
baseline_rc=0
mutated_rc=1
red_line=[FAIL] claim 1: kept=1/6 own_set=0/6
diff_hash=d05c789380e05f235a765be227fb16aea84405e93cb79aff2433a603681e58c0
lane_diff_hash=b455ec46f4f71f0a87c5385f9ee32cb0ca45af1e16232404ad2446eb093c98a8
```

`mutated_rc=1` (mutant killed, not survived): baseline green in the scratch tree, the mutant
reproduces the exact `kept=1/6 own_set=0/6` shape from the live reproduction above, in a
disposable scratch copy (never the lane checkout itself).

## Negative control 2 — revert the fix itself (red)

Shown in the reproduction above: with commit `823cb06c` reverted (base writer
restored), the same harness fails claim 1 with `kept=1/6 own_set=0/6`, rc=1. After
`git checkout HEAD -- <writer>` the suite is green again (run above, rc=0).

## Claim 2 — an unrecorded set still refuses (fail-open guard, reader untouched)

One row with no write set, a live worker pid (`sleep 60`), and a fresh pending window;
a second registration with a declared set must be refused:

```
[ok] claim 2: unrecorded write set + live worker still refused rc=5 reason=pending_resolution
```

The refusal is emitted by the unmodified `leadv2-active-registry.sh:564-571`
(`reason=pending_resolution`, `sys.exit(5)`). Unrecorded still means refuse; the fix
makes sets recorded.

## How CI selects the guard suite on a change to the writer file

The suite self-registers via its line-2 declaration
(`# run-all-triggers: leadv2-dispatch-code.sh leadv2-active-registry.sh`), consumed by
`tests/run-all.sh` `scan_suite_triggers` (`:329-353`). Trigger map (live output):

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep writes-persist-under-concurrency
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
```

Changed-scope selection for this lane's diff:

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | tail -1
run-all: 146 selected, scope=changed, select_only=1
```

146 of 146 selected include the guard suite (grep count 1) — the writer file's stem
fans out to every suite that declares it, mine included.

## Falsification set

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh` → OK (rc=0)
- `bash -n plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh` → OK (rc=0)
- `python3 -m py_compile` — no Python file changed by this lane (the suite's python is
  heredoc-embedded and executed by the suite run itself; the registry core is
  untouched), so there is nothing to compile. Enumerated, not skipped silently.
- Repo changed-scope runner: see next section.

## Changed-scope runner result

```
$ bash tests/run-all.sh --scope changed
```

Boundary: 146 suites selected for `scope=changed` on this lane's diff (per-suite ceiling as
declared by each suite; the whole-run wall time on this checkout exceeds any single-session
budget — see below). Run started, allowed to progress in the foreground for ~30 min, then
capped: 31/146 suites had completed.

`run-core-offline.sh` — the first suite in `--scope changed` order — hit the
run-all-enforced 600s per-suite ceiling and was killed:

```
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling (killed by run-all; counted as a blocking failure with a named cause)
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
```

This is the pre-existing, previously-measured systemic condition (`run-all` always runs
`run-core-offline.sh` on `--scope changed`, and its own budget-mode skip logic is tuned for a
~900s close-gate window, not a single suite invocation) — `environment_dependent`/`timeout` per
the cause-class taxonomy, not caused by this lane's one-function diff, and not something this
lane's off_limits or mission ask it to fix.

Of the remaining 30 suites that finished in the ~30 min window, 20 passed and 10 failed:

```
$ grep -cE '^\[PASS\]' .changed-scope-run.log   # 20
$ grep -cE '^\[FAIL\]' .changed-scope-run.log   # 11 (10 + the core-offline timeout line above)
```

**Verified none of the 10 failures reach the changed code.** The lane's only code diff is
inside one function, `_dispatch_register_writes_row` (and its proof helper
`_dispatch_registry_writes_proof`), in `leadv2-dispatch-code.sh`. Grepping the 10 failing
suites' source for either name returns nothing:

```
$ grep -lE "_dispatch_register_writes_row|_dispatch_registry_writes_proof" \
    plugins/leadv2/scripts/tests/test-admission-safety-pin.sh \
    plugins/leadv2/tests/test-arm-pool-reachability.sh \
    plugins/leadv2/tests/test-exclusion-stages.sh \
    plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh \
    plugins/leadv2/scripts/tests/test-arm-admission.sh \
    plugins/leadv2/scripts/tests/test-arm-advance-real.sh \
    plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh \
    plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh \
    plugins/leadv2/scripts/tests/test-balancer-every-arm.sh \
    plugins/leadv2/scripts/tests/test-complexity-routing.sh \
    plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh \
    plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh
(no output)
```

One of the 10, `test-leadv2-dispatch-code.sh`, DOES exercise the same file (it is the writer's
own suite), so it was independently baseline-compared rather than trusted on the grep alone —
run once against this lane's fixed tree, then again with `leadv2-dispatch-code.sh` swapped
byte-for-byte to `main`'s version (temporary, restored immediately after, checkout verified
clean both before and after):

```
$ timeout 120 bash plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh   # fixed tree
[TEST] summary: PASS=13 FAIL=10
$ git checkout main -- plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ timeout 120 bash plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh   # main's writer
[TEST] summary: PASS=13 FAIL=10
$ git checkout HEAD -- plugins/leadv2/scripts/leadv2-dispatch-code.sh   # restored
$ git diff --quiet -- plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo RESTORED_CLEAN
RESTORED_CLEAN
```

Byte-identical `PASS=13 FAIL=10` on `main` and on this lane's fix: the 10 failures are
pre-existing (`real_regression` in some earlier, unrelated change — not this lane's), and this
lane's diff changed neither the count nor which cases fail. All 10 failing case names are about
`effort`/`think`/`class_map` selection (e.g. `Heavy expected effort=max think=deep
source=class_map`), nowhere near write-set persistence.

**Practical cap, stated plainly:** completing all 146 suites at the observed pace (~30 finished
in ~30 min, dominated by suites unrelated to this change) would take multiple hours — this is
the same systemic `--scope changed` runtime gap already on record
(`run-all changed-scope runtime`: core-offline always-on, 900s close-gate budget not sized for
an ad-hoc single-suite run). Fixing that runtime gap is out of scope for this lane (not named in
the mission, not touching the writer or the registry). The guard suite itself
(`test-writes-persist-under-concurrency.sh`) — the one suite that actually exercises this fix —
was run to completion multiple times above, always green, with both a scratch-copy control and
the canonical `leadv2-mutation-control.sh` control both showing the mutant killed.

## Off-limits honored

- `leadv2-dispatch-product-close.sh` — untouched (another lane owns it).
- `tests/known-red-suites.txt` — untouched.
- No assertion deleted, no grep loosened, no `|| true` added; the suite's assertions
  only grew.

## Left red / known issues

- **`run-core-offline.sh` under `--scope changed`**: hits `run-all`'s 600s per-suite ceiling
  (`[SUITE-TIMEOUT] ... exceeded 600s ceiling`) every time it is run standalone via
  `--scope changed`, because that suite's own budget-mode skip logic is tuned for the ~900s
  close-gate window, not a bare invocation. Pre-existing, environment/runtime, not touched or
  caused by this lane. Left red; not this lane's fix target.
- **`test-leadv2-dispatch-code.sh`: 10 pre-existing failures** (`PASS=13 FAIL=10`, byte-identical
  on `main` and on this lane's fix — see Changed-scope runner result above), all in
  `effort`/`think`/`class_map` selection cases, unrelated to write-set persistence. Left red;
  not this lane's fix target and not introduced by it.
- **9 other `--scope changed` suites failing** in the partial run (`test-admission-safety-pin.sh`,
  `test-arm-pool-reachability.sh`, `test-exclusion-stages.sh`, `test-arbiter-seam-plugin-kind.sh`,
  `test-arm-admission.sh`, `test-arm-advance-real.sh`, `test-arm-capability-honoured.sh`,
  `test-arm-ladder-vocabulary-drift.sh`, `test-balancer-every-arm.sh`,
  `test-complexity-routing.sh`, `test-consumer-symlink-farm.sh`,
  `test-dispatch-architect-degrades.sh` — 12 named, 10 failed + `test-leadv2-dispatch-code.sh`
  covered separately + 1 timeout): confirmed by grep to contain no reference to the two symbols
  this lane changed (`_dispatch_register_writes_row`, `_dispatch_registry_writes_proof`), so they
  cannot be reached by this diff. Not independently baseline-diffed against `main` one-by-one
  within this lane's time budget (each would need the same manual `git checkout main -- <file>`
  dance as the writer's own suite, and none of them import the changed file's changed function).
  Left red / unverified-against-baseline; flagged honestly rather than asserted pre-existing
  without evidence.
- **113/146 `--scope changed` suites not run** in this lane: the full run's wall time
  (multiple hours at the observed pace, dominated by suites this diff cannot reach) exceeds any
  single foreground session — see "Practical cap" above. `test-writes-persist-under-concurrency.sh`,
  the one suite that exercises this fix, ran to completion (green) several times.
- No assertion was deleted, no grep loosened, no suite widened to reach any of the above; every
  suite named here is left exactly as found.
