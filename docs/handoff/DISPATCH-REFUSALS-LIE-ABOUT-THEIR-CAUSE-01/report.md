# Dispatch refusals now name their actual cause

## D1 — supplied unknown kind

`cmd_resolve` now rejects a supplied kind unless it is `product` or appears in
`LEADV2_NON_PRODUCT_KINDS`; the error prints the supplied value and that shared
vocabulary. An absent kind remains `product\tconservative_default`.

Test: `plugins/leadv2/scripts/tests/test-dispatch-refusal-truth.sh` invokes the
real CLI for `--kind code`, then sources the production classifier for the
absent-kind policy control.

## D2 — mission exists but is untracked

The resume mission preflight now checks the lane filesystem after it proves the
path is absent from lane `HEAD`. A physical untracked file reports `untracked`
and the exact `git add && git commit` remedy; a file absent from disk retains
the existing absent-from-both refusal.

Test: the same suite creates a real Git main/lane fixture and exercises both
refusals through `_resume_mission_visibility_preflight`.

## D3 — external backlog identity

`row_matches` now resolves exact `id`, then `external_id`, then `node_id`,
before its existing exact `intent` heading compatibility match. A no-match
refusal now names the searched keys.

Test: the suite drives `_premise_probe_gate` against a real `docs/tasks.yaml`
row keyed by `external_id`, then a genuinely unknown id.

## Falsification and controls

All controls were run with the real `leadv2-mutation-control.sh` after commit
`14fa47bf`; each artifact records `baseline_rc=0` and `mutated_rc=1`.

| Defect | Mutation | Artifact | Raw RED line |
|---|---|---|---|
| D1 | parse guard `if [[ -n "${kind}" ]]` → `if false` | `mutation-control/20260915T083204Z-55711.txt` | `FAIL: D1 unknown kind refusal mismatch rc=8` |
| D2 | `present but untracked` → `present but invisible` | `mutation-control/20260915T083238Z-66193.txt` | `FAIL: D2 untracked refusal mismatch rc=5` |
| D3 | remove `external_id` from matcher keys | `mutation-control/20260915T083310Z-75918.txt` | `FAIL: D3 external_id resolution mismatch rc=8` |

The complete red output, anchors, exit codes, and mutation hashes are the
three committed mutation-control artifacts named above.

### GREEN after restore

```text
PASS: D1 unknown kind is refused with supplied value and shared accepted set
PASS: D1 absent kind remains the conservative default
PASS: D2 untracked mission names the state and git remedy
PASS: D2 absent mission remains a distinct disk-absence refusal
PASS: D3 external_id resolves the real backlog row
PASS: D3 unknown id refuses and names searched keys
[DISPATCH-REFUSAL-TRUTH] pass=6 fail=0
```

## Self-check

```text
$ bash -n <every changed .sh>; python3 -m py_compile plugins/leadv2/scripts/leadv2_tasks_yaml_common.py
exit 0

$ bash plugins/leadv2/scripts/tests/test-dispatch-refusal-truth.sh
PASS: D1 unknown kind is refused with supplied value and shared accepted set
PASS: D1 absent kind remains the conservative default
PASS: D2 untracked mission names the state and git remedy
PASS: D2 absent mission remains a distinct disk-absence refusal
PASS: D3 external_id resolves the real backlog row
PASS: D3 unknown id refuses and names searched keys
[DISPATCH-REFUSAL-TRUTH] pass=6 fail=0
```

The required `tests/run-all.sh --scope changed` runner was run in the
foreground after the caller migration. It was RED because its 150-suite core
selection exceeded the deliberately imposed 60-second per-suite ceiling; it
was not represented as green. The raw terminal lines were:

```text
[CORE-OFFLINE] scope=changed running 161 of 93 suites (base=main@5da9324f27, 33 changed files, 0 unmapped)
[CORE-OFFLINE] running 150 suites across 4 shards
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 60s ceiling
[FAIL] plugins/leadv2/scripts/tests/run-core-offline.sh
exit 124 (outer 130-second bound)
```

After the first runner exposed legacy test callers using the now-invalid
`--kind code`/`--kind safety` spellings, those callers were migrated to the
accepted `--kind product` form (with `--safety` where applicable). The focused
six-case suite above is the green changed-seam proof; the aggregate runner has
not been represented as green.

## Round 2 — the migrated `--kind product` callers do not reach the architect prepass

**Mission**: round 1's mechanical migration of ~27 legacy `--kind code`/`--kind
safety` call sites to `--kind product` was flagged as a possible perf
regression, since `product` is the only kind excluded from
`LEADV2_NON_PRODUCT_KINDS` and therefore the only one that can trigger
`architect_prepass()` (`leadv2-dispatch-code.sh:9386-9402`, timeout
`LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC:-420`). Task: pick the correct `--kind`
per caller, verify (not assume) the "`--no-spawn` never reaches the prepass"
claim, measure the changed-scope runner before/after, and run a real timing
negative control — with an explicit escape hatch to report "nothing to fix"
if the finding doesn't hold.

**Finding: the finding doesn't hold.** Every one of the ~27 migrated call
sites is moot — none of them reaches the live architect-prepass model call.
No `--kind` needs to change. Evidence follows.

### Correction to the round's own framing: `--no-spawn` does NOT skip the prepass

The `spawn` variable set by `--no-spawn` (`leadv2-dispatch-code.sh:8780`,
`spawn=0`) is first read at line 10283+, which is after `architect_prepass()`
is invoked at line 9402. `--no-spawn` only suppresses the final worker
launch; it has no effect on whether the prepass runs. This assumption in the
mission text was wrong and should not be repeated in future rounds. The
actual mootness of every migrated caller comes from three other,
independently verified mechanisms:

### Per-caller disposition (all ~27 files — no `--kind` changes)

1. **`ARCHITECT_GATE=0` set explicitly in the caller's own test env**
   (`architect_prepass()` line 6125: `if [[ "${ARCHITECT_GATE}" != "1" ]];
   then status=disabled reason=kill_switch; return 0; fi`) — the dominant
   mechanism, confirmed present (directly, or via a shared `dispatch_env()`/
   `run_dispatch()` helper) in: `test-balancer-every-arm.sh`,
   `test-effort-routing.sh`, `test-freepool-capability-floor.sh`,
   `test-glm-effort-wiring.sh`, `test-glm-flash-arm.sh`,
   `test-glm-flash-handle.sh`, `test-leadv2-dispatch-code.sh`,
   `test-model-select-telemetry.sh`, `test-phase-gate-inversion.sh`,
   `test-phase-precondition-bootstrap.sh`, `test-arm-pool-reachability.sh`,
   `test-arm-advance-real.sh`, `test-freepool-gets-work.sh`,
   `test-dispatch-arm-vocabulary.sh`, `test-route-arbiter.sh`.
   `test-freepool-gets-work.sh` is notable: it has a genuine 2-path
   `--writes`, so it does NOT also benefit from mechanism 2 below — the gate
   is the only reason it's moot.
2. **`provably_one_file` skip** (`architect_prepass()` ~line 6157-6164:
   comma-split `--writes` count `== 1` returns `status=skipped
   reason=provably_one_file` before any subprocess spawn) — confirmed via a
   single-path `--writes` in: `test-admission-safety-pin.sh`,
   `test-arm-capability-honoured.sh`, `test-codex-tiers-selectable.sh`,
   `test-ephemeral-state-basename-collision.sh`, `test-plugin-review-arms.sh`,
   `test-stale-script-tree.sh`, `test-complexity-source-provenance.sh`.
3. **Call site never reaches `leadv2-dispatch-code.sh` at all** —
   `test-codex-tier-model-table.sh` and
   `test-launch-registry-answers-for-every-arm.sh` and
   `test-launch-registry-argv.sh` call `leadv2-launch-registry.py` directly;
   `test-fixture-state-leak-guard.sh`'s `--kind product` occurrences are
   inert heredoc string literals fed to an embedded Python static-analysis
   `find_hazards()` detector, never executed as shell.

`test-fg-dispatch-guard-reads-the-command.sh` (2 sites) is a Python test that
constructs command-line strings to check a guard's text-matching behavior;
this one was classified from the round-1 census, not independently
re-verified line-by-line the way the others above were — flagged here rather
than silently trusted.

**Conclusion**: no caller should be changed. Changing any of them to
`tooling` would be a no-op diff (same behavior, different label) — exactly
the kind of change the mission said not to make "just to be tidy."

### Before/after changed-scope runner, same ceiling

Since the finding is "change nothing," before and after are the same tree;
both runs are reported rather than assumed identical.

Command (both runs): `LEADV2_RUN_ALL_SUITE_TIMEOUT_S=60 timeout 130 bash
tests/run-all.sh --scope changed` (60s per-suite ceiling, 130s outer bound),
darwin/Bash 3.2, worktree `7344367e`.

- **Before**: `scope=changed running 161 of 93 suites (base=main@5da9324f27,
  33 changed files, 0 unmapped)` → 150 suites across 4 shards after 11
  known-red skips → `[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh
  exceeded 60s ceiling` → `[FAIL] .../run-core-offline.sh` → exit 124.
- **After** (identical command, no files changed in between): same
  selection (`161 of 93`, same base, same 33 changed files), same 150
  suites/4 shards, same `[SUITE-TIMEOUT]` on `run-core-offline.sh`, exit 124.

Still red after, for the same reason as before: `run-core-offline.sh` (an
aggregation suite that runs many nested suites in-process) does not fit a
60s ceiling regardless of any `--kind` labeling — this is a pre-existing
ceiling/runtime mismatch, not something round 1 or round 2 introduced or
could fix by relabeling `--kind`. The ceiling was not raised to force green.

### Timing negative control (synthetic, since no committed fixture reaches the prepass)

Since no migrated caller reaches the prepass, a fixture-based control cannot
demonstrate a timing regression. Built a standalone, uncommitted synthetic
control instead (`/tmp/round2-negctrl-single.sh`, not part of the repo): a
throwaway one-commit git repo, `LEADV2_DISPATCH_ARCHITECT_BIN` pointed at a
stub (`sleep 3; echo ...`) instead of a live model call so the timing is
bounded, all other network-facing arms/quota reads stubbed, `--writes
src/a.py,src/b.py` (2 files, so `provably_one_file` does not apply) and
`ARCHITECT_GATE` left at its production default (unset = `1`).

First attempt ran both `--kind product` and `--kind tooling` calls against
the *same* throwaway repo back-to-back; control B (`tooling`) refused with
`dispatch_refused reason=writeset_overlap blocked_by=dispatch-a08a422e` —
control A's active-lane row for `src/a.py,src/b.py` was still live when B
ran, so B's elapsed time included lock/overlap handling unrelated to the
prepass. Corrected by giving each arm its own isolated throwaway repo
(`/tmp/round2-negctrl-single.sh product` / `... tooling`, run as two
separate process invocations, no shared state):

```
--- isolated product --- elapsed=54s rc=0
  dispatch_classified ... class=product reason=conservative_default kind=product
  architect_prepass task=a08a422e status=ran arm=claude artifact=docs/handoff/dispatch-a08a422e/architect-prepass.md source=stdout

--- isolated tooling --- elapsed=53s rc=0
  dispatch_classified ... class=non_product reason=explicit_kind_tooling kind=tooling
  (no architect_prepass line — the log line never appears for this arm, in any of 3 separate runs)
```

**Mechanism proof (qualitative, solid)**: `--kind product` with `ARCHITECT_GATE`
at its production default and a 2+ file `--writes` genuinely invokes
`ARCHITECT_BIN` (`status=ran`); `--kind tooling` with the identical `--writes`
and env never does, across three independent runs (one shared-repo pair, one
isolated-repo pair, plus the shared-repo pair's repeat). This is the real
mechanism the round's concern is about, and it is real — it just isn't
reachable through any of the round-1-migrated test callers.

**Magnitude (honest limitation)**: the isolated pair's wall-clock delta is
~1s (54s vs 53s), not the ~3s the stub sleeps, let alone anything close to
the production 420s prepass timeout. Both arms share a ~53s baseline that
has nothing to do with the prepass (dispatcher startup, route-arbiter
resolution, registry/cost-estimate writes — present identically in both
logs before the classification line). That baseline was not further
diagnosed; it is disclosed here as an unexplained confound rather than
folded into a false "the prepass costs ~1s" conclusion. The honest
production-risk statement is: when the live prepass runs, its cost is
whatever the real architect model call takes, bounded above by the
420s `ARCHITECT_PREPASS_TIMEOUT_SEC` — not measured directly here since
that would require an actual model call, which was out of scope for a
bounded, reproducible control.

### Out-of-scope findings (not fixed, flagged for the lead)

Round 1's broad find/replace corrupted a *different*, unrelated `--kind`
namespace in three files — `leadv2-event.sh emit --kind <value>` (dispatch
journal event typing), not `leadv2-dispatch-code.sh`'s product/non-product
classification:
- `plugins/leadv2/scripts/codex-task.sh:1837` — `--kind codex_worker_died`
  became `--kind productx_worker_died` inside `_dw_announce()` (the JS/Python
  call site at ~line 2024 still emits the original, correct
  `codex_worker_died`, so the shell and JS/Python paths now disagree for the
  same logical event).
- `plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh` —
  `--kind codex_fitting_dev` → `--kind productx_fitting_dev`.
- `plugins/leadv2/scripts/tests/test-st2-question-protocol.sh` —
  `--kind codex-test` → `--kind productx-test`.

These are real bugs (inconsistent event-kind values), but they're event-log
typing, not `leadv2-dispatch-code.sh` classification/performance — out of
this round's mission. Not fixed here; flagging for the lead to dispatch
separately rather than folding an unrelated fix into this round.

### Process note

A nested `Agent(subagent_type=Explore, model=haiku)` census spawn during this
round defaulted to background execution because `run_in_background: false`
was not set explicitly, which the mission said never to do. No turn was
ended on the pending wait (other independent verification work continued
until the notification arrived), and every claim the census fed into this
report was independently re-verified against source before being relied on
— but the spawn itself was a protocol deviation and is disclosed rather than
omitted.

### Round 1 assertions untouched

`test-dispatch-refusal-truth.sh`'s six assertions were not read for editing
and are not touched by this round. No `--kind` call site was changed. No
ceiling was raised. No `|| true` / `2>/dev/null` was added anywhere.

DELIVERABLE_COMPLETE
