# LANE-LIVENESS-E0-GUARD-FIXTURE-COLLAPSES-EVERY-CASE-01 — lane report

Boundary for every count below: macOS Darwin 25.6.0, bash 3.2, lane worktree
`worktree-55de339ac133`, before-commit `e6e2d0182d4f123a85b3f61102d0e8f30e670233`,
fix-commit-1 `fae0f13e7f0ba04b286e9bb4486a234f1fd458d3` (worktree-shape fix),
fix-commit-2 `60628b0a` (hermeticity fix; final HEAD). The census's 120 s
per-suite ceiling applies; `test-lane-truth-batch-01.sh` exceeds it (lane-rules
"Measurement hygiene") and its wall time is reported as a time, not a failure.

Two defects were found and fixed, both fixture-side; the E0 guard in
`leadv2-lane-liveness.sh` was never touched.

## Suite 1 — test-lane-verdict-three-states.sh

- **Reproduction**: `bash plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`
- **Observed before** (commit `e6e2d018`, wall 20 s, rc=1): **3 pass / 14 fail of 17 checks**
  (passes: Test 3a, 3b — registry-unreadable; Test 12 — passed only *accidentally*,
  its loose `unknown:*` matcher swallowed the E0 verdict). Every failure the same
  verdict: `{"verdict":"unknown:contradictory_rows","source":"e0_contradiction_guard","reason":"worktree_is_project_root"}`.
- **Cause class**: `never_reaches_subject` — the E0 contradiction guard
  (`plugins/leadv2/scripts/leadv2-lane-liveness.sh:977-985`, verdict emitted at
  `:997`) lands *before* every rung the suite exists to exercise, because the
  fixture registered `worktree: "${repo}"` (`_fixture_row`, old line 116) while
  the resolver was invoked with `LEADV2_PROJECT_ROOT="$repo"` (`_verdict`/
  `_json_field`). Worktree and project root were the identical string **by
  construction** — exactly the shape E0 rejects. The guard is correct; the
  fixtures were asserting against an illegal shape.
- **Fix** (fixture-only; the guard is untouched):
  - `_fixture_row` now derives `lane_wt="${repo}/.claude/worktrees/${tid}"` and
    registers that — the per-task worktree shape a live lane has. All rungs
    (pid, E3 commit-age, E4 deliverable, stream freshness) now reach their
    subject. Commit-age semantics are unchanged: an unborn-HEAD fixture still
    yields `commit_age_s → None` (git resolves the subdir to the same repo).
  - **Test 13** (two rows for one task_id) flipped deliberately: with the
    worktree fixed it would trip E0's *other* reason, `multiple_rows`
    (leadv2-lane-liveness.sh:974). The pre-E0 expectation — E4 reaching a
    dispatch pointer on a non-last row through last-row-wins — is superseded by
    the recorded decision in the code: **D2-M5 / D2-SINGLE-LIVENESS-VERDICT
    #14/#15, plugins/leadv2/scripts/leadv2-lane-liveness.sh:966-999** ("E0
    contradiction guard, evaluated before any other rung … no lower rung may
    promote past it"). The case (renamed
    `test_13_multi_row_registry_is_explicit_e0_contradiction`) now asserts that
    verdict explicitly — `unknown:contradictory_rows` +
    `source=e0_contradiction_guard` + `reason=multiple_rows` — while keeping the
    deliverable setup, proving real finished evidence was present and E0 still
    refuses to promote past it. The new behaviour is the thing guarded.
  - **New Test 14** (`test_14_worktree_is_project_root_is_explicit_e0_contradiction`)
    registers the illegal `worktree == project root` shape *deliberately* and
    asserts `reason=worktree_is_project_root` explicitly, so any future fixture
    regression collapses loudly on a positive assertion instead of silently
    blinding every rung below E0.
- **Observed after** (commit `fae0f13e`/`60628b0a`, wall 35 s, rc=0): **18 passed /
  0 failed of 18 checks** — the original 17 plus Test 14. Test 12 now passes for
  the right reason (its subject, the unreadable dispatch dir, is what it resolves).
- **Harness-env check** (the env `run-core-offline.sh` gives a suite: scrubbed
  `LEADV2_*`/`CLAUDE_*`/`GIT_CONFIG*`/`PROJECT_ROOT`, sandboxed `HOME`, private
  `TMPDIR`, retained `PYTHONUSERBASE`): rc=0, `[TEST] RESULTS: 18 passed, 0 failed`.

## Suite 2 — test-lane-truth-batch-01.sh

- **Reproduction**: `bash plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh`
- **Observed before** (commit `e6e2d018`, wall 276 s, rc=1): **pass=13 fail=3 of
  16 checks** — the 3 fails being Row 1's two liveness assertions and the Row 1
  mutation-gate HEAD check, all with the same
  `unknown:contradictory_rows / e0_contradiction_guard / worktree_is_project_root`
  JSON. Same cause class: **`never_reaches_subject`**. Two fixture sites stamped
  `worktree == LEADV2_PROJECT_ROOT`:
  `leadv2_active_register "FOO-123" "Standard" "$repo" "main"` (3rd arg is
  `worktree`, leadv2-active-registry.sh:1277) and
  `run_dispatch_liveness_gate`'s `--worktree "$gate_root"` with
  `LEADV2_PROJECT_ROOT="$gate_root"`.
- **Fix 1 — worktree shape** (fixture-only, commit `fae0f13e`): both sites
  register a per-task worktree (`$repo/.claude/worktrees/foo-lane`,
  `$gate_root/.claude/worktrees/gate-lane`). Behaviour probe before committing
  (scratch copy of the gate, distinct worktree) — all three gate scenarios
  resolved correctly: direct dispatch `alive/log_fresh`; MUT-HEAD
  `alive … raw_log_path=docs/handoff/dispatch-89291c44/developer.stream.jsonl,
  pid_source=lead_durable`; pulse.md mutant `starting:13/registered_no_stream`.
- **Observed after fix 1, standalone** (rc=0): **pass=16 fail=0**, wall ~290 s.
- **Second defect, found by the changed-scope runner** (`run-core-offline.sh
  --scope changed` at `fae0f13e`): **pass=15 fail=1**, rc=1 —
  `[TEST] FAIL: Row 1 mutation gate HEAD must resolve stamped stream alive`,
  got `{"lane":"MUT-HEAD","verdict":"unknown:yaml_unreadable",…
  "reason":"registry_unreadable"}`. Reproduced deterministically (3/3 runs) under
  a faithful reconstruction of the runner's suite env (scrubbed env + sandboxed
  `HOME` + retained `PYTHONUSERBASE`; the first repro attempt that omitted
  `PYTHONUSERBASE` over-failed 5 checks — PyYAML import — and was discarded as
  unfaithful). Standalone the same bytes were green, so:
  - **Cause class**: `environment_dependent`. Instrumented gate run showed the
    dispatch under the harness env REFUSEs:
    `[leadv2-routing-config] REFUSE: tenant routing yaml exists but no canonical
    registry found to merge against (tenant=…/dispatch-gate-MUT-HEAD/.claude/ref/
    leadv2-routing.yaml)` → `[leadv2-dispatch-code] REFUSE: unresolvable routing
    config`, so the gate never registers (state tree empty). Mechanism: the
    suite's scratch plugin copies `scripts/` + `workflows/` but **not `config/`**
    (test-lane-truth-batch-01.sh:27-28 pre-fix), so
    `lib/leadv2-routing-config.sh`'s plugin-local canonical candidate
    (`…/config/leadv2-routing.yaml`, leadv2-routing-config.sh:58-61) is missing
    and the resolver falls through to `${LEADV2_CANONICAL_ROOT:-$HOME/Projects/
    leadv2}` — ambient host state that exists under a real HOME but not under
    the runner's sandboxed HOME. Standalone passed by borrowing the host's
    canonical checkout. Under the harness, Row 2 and MUT-MUTANT were also
    passing **for the wrong reason** (liveness's dispatch-glob + stream fallback
    needs no registry), which is why only MUT-HEAD reddened.
  - **Fix 2** (fixture-only, commit `60628b0a`): `cp -a
    "${REAL_PLUGIN_DIR}/config" "$PLUGIN_DIR/"` so the routing resolver's
    canonical registry lives inside the fixture. Comment in the suite documents
    the mechanism.
- **Observed after fix 2**:
  - standalone (rc measured unpiped): **pass=16 fail=0**, rc=0;
  - harness-env reconstruction: **pass=16 fail=0**, rc=0;
  - changed-scope runner at `60628b0a`: `[CORE-OFFLINE] suites passed=3 failed=0
    missing=0 known_red_skipped=0`, runner rc=0.
- One honest flake, not hidden: the first control-2 attempt at `60628b0a` was
  rejected `control_not_applied reason=baseline_not_green baseline_rc=1` even
  though the baseline printed `pass=16 fail=0` — the suite's EXIT-trap
  `rm -rf "$tmp"` raced a lingering background writer and failed
  (`rm: …/lane-truth.XXX: Directory not empty`), flipping rc to 1. A clean
  unpiped standalone run immediately after was rc=0 with no such line, and the
  control retry (below) took a green baseline. Cause: a transient trap-vs-
  background-writer race in the suite's teardown, observed once in ~8 runs;
  left as-is (not this lane's subject) and named here.

## Negative controls

Two independent claims (one per suite), two controls, both re-run with
`leadv2-mutation-control.sh --live` **at the final HEAD `60628b0a`** (both
artifacts carry the same `lane_diff_hash=59c1762c…`, binding them to the
committed lane; earlier artifacts from `fae0f13e` — `lane_diff_hash=c378d522…` —
are kept in the same dir and superseded). The mutation is applied to the real
file in the registered lane worktree (not a scratch copy; this suite family is
sensitive to where the tree lives), the suite is proven red, and the file is
restored byte-identical (`porcelain_clean=yes`, `restored=yes`). Anchor text
asserted present exactly once before each run (`grep -F -c … → 1`; note `grep`
here is ugrep — a `${` in a quoted BRE pattern false-zeros, hence `-F`).

### Control 1 — three-states (mutation: `_fixture_row` worktree back to `"${repo}"`)

Mutant diff hash `80e924b3…` (one line:
`local lane_wt="${repo}/.claude/worktrees/${tid}"` → `local lane_wt="${repo}"`).

```
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh file=plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh red_line=[TEST] FAIL: Test 1: verdict=unknown:contradictory_rows (must match finished_unlanded:<age>s, never dead:*) diff_hash=80e924b32af5fdec2974e7c567b708e14fb63bdefdb39005782ca4f31b28ce4f lane_diff_hash=59c1762ca190d180da9eec6f2fefcf6e993ee9023b71a56eaee8d14f271905da porcelain_clean=yes
```

Artifact: `mutation-control/20260917T030426Z-live-43164.txt`
(`baseline_rc=0`, `mutated_rc=1`; the red line is the exact E0 collapse the
suite showed before the fix).

### Control 2 — batch-01 (mutation: both fixture worktrees back to the project root)

Mutant diff hash `35d25244…` (two lines: `foo_lane_wt="$repo"` and
`local gate_wt="$gate_root"`; patch regenerated against `60628b0a` via
`git diff`, 2 hunks, both anchors asserted).

```
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh file=plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh red_line=[TEST] FAIL: Row 1: lane with set_log_path resolves alive via real stream diff_hash=35d25244d155044ddcd12b3a02e1a29e500065484b7a01c52e97ad2dc6e0b131 lane_diff_hash=59c1762ca190d180da9eec6f2fefcf6e993ee9023b71a56eaee8d14f271905da porcelain_clean=yes
```

Artifact: `mutation-control/20260917T032235Z-live-52518.txt`
(`baseline_rc=0`, `mutated_rc=1`). The mutation that collapses the fixtures'
worktrees back onto the project root re-creates the E0 blindness and the suite
goes red on Row 1's real-stream assertion — the control proves the suite now
depends on the honest shape.

## Falsification set

- `bash -n plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh` → clean
  (silent, rc 0). `bash -n plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh`
  → clean (echoed "bash -n OK").
- No Python files changed → `py_compile` N/A.
- Changed-scope runner (base `1b545001`, changed = exactly the two suites):
  - red at `fae0f13e` (before fix 2): `[LANE-TRUTH-BATCH-01] pass=15 fail=1`,
    `[CORE-OFFLINE] suites passed=2 failed=1 …`, runner rc=1;
  - green at `60628b0a`:
    `[CORE-OFFLINE] SHARD_RESULT idx=0..3 + serial all pass`, final line
    `[CORE-OFFLINE] suites passed=3 failed=0 missing=0 known_red_skipped=0`,
    runner rc=0.

## Left red

Nothing. Both suites green for the reasons they assert — standalone AND under
the core-offline harness env. No assertion was deleted, loosened, or `|| true`d;
the only assertion *changed* is Test 13, which now guards the recorded E0
decision (quoted above) instead of a pre-E0 expectation the guard deliberately
supersedes, and Test 12's matcher was left exactly as found (it now reaches its
real subject). Named but not fixed (out of subject): the once-observed
EXIT-trap `rm` race in batch-01's teardown described above.
