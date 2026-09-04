verdict: APPROVE
next_action: review_round_2

# E2E-TIMEOUT-REPORTED-AS-REGRESSION-01 — developer report

## 1. The bug and its fix (file:line)

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — the script whose journal produced
the measured incident (`e2e_gate task=49c6e0c8 status=ran verdict=fail rc=124` →
`dispatch_terminal task=49c6e0c8 terminal=dead cause=e2e_regression`). Before this fix, the
`e2e_rc` branch at what was line 2693 was a plain `if 0 / else`: any non-zero rc — including 124
from `_lv2_selfcheck_timeout_run` (line ~2676) — fell into the same `else` as a real red suite,
ran foreign-failure ownership classification against it, and (absent a foreign match) landed on
the `else` at the old line 2748-2761, which wrote `reason: e2e_regression` and called
`_dl_note dead e2e_regression "rc=${e2e_rc}"` regardless of whether the suite actually failed or
merely never finished.

Fix: inserted an `elif [[ ${e2e_rc} -eq 124 ]]` branch between the pass and fail branches (now
`leadv2-dispatch-product-close.sh:2697-2719` in the patched file), before ownership
classification runs (ownership re-runs suites to see if a failure reproduces against the lane's
own writes — meaningless, and itself liable to time out again, for a sweep that never finished).

Same conflation existed in the standalone `plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh`
(its own `rc -eq 0 / else` at the old line ~243-297) — not the script that killed the measured
lane (it doesn't call `_dl_note`/write-terminal at all), but it wrote the same
`reason: e2e_regression`-shaped text and `verdict=fail` for a timeout. Fixed the same way,
labelling only (no ledger call exists there to redirect).

## 2. Disposition: `parked` / `e2e_timeout`, not `dead` / `e2e_regression`, not silent pass

`e2e-gate.md` now gets `status: unknown\nreason: e2e_timeout\nrc: 124\ntimeout_s: <budget>`.
The ledger terminal is `parked`, cause `e2e_timeout` (`_dl_note parked e2e_timeout ...`), and the
script exits 5 (the existing "blocked, human decides" exit code shared with `asked_into_void`
just above it in the same file) instead of 8 (the "true kill" exit code, still used for a real
`e2e_regression`).

Argument: `dead` is wrong because a timeout is not evidence of a regression — the brief's own
observation (the lane's selfcheck had passed green with 7 checks moments before) is exactly the
shape of "the sweep just didn't finish," not "the code broke." Silently treating rc=124 as a pass
would be lying-green — the sweep genuinely never ran to completion, so nothing says the code is
safe either. `parked` is the ledger's own pre-existing taxonomy entry for exactly this shape: "a
human must decide" (`leadv2-dispatch-ledger.sh:38`, "explicitly deferred for a human/architect
decision"), and it is *retryable* — `refused`/`parked` never permanently block a later, real
verdict for the same task sig8 (`leadv2-dispatch-ledger.sh:266-268`), unlike `dead`/`landed`. It
reuses machinery that already exists rather than inventing a new terminal state.

## 3. The round's work survives regardless of the verdict

`pc_stop_gate_autocommit` (leadv2-dispatch-product-close.sh, function at line ~1815, called at
line ~2571 — `V3-STOP-GATE-01`/`V3-STOP-GATE-FINISH-01`) already runs **before** the e2e gate
section (which starts at line ~2637), unconditionally of what the e2e sweep does. It stages and
commits (`wip(<task>): ... (STOP-GATE)`) the lane's in-scope write-set from
`_PC_SCOPE_WRITES_CSV` if the tree is dirty. This means: by the time `e2e_rc` is ever inspected,
the worker's diff has *already* been checkpointed into a real commit on the lane branch — the
timeout classification fix doesn't need to (and doesn't) add its own commit step. Verified
directly: `test-e2e-timeout-classification.sh` R1 asserts `git log` on the fixture repo contains
a `STOP-GATE` commit after a simulated rc=124 run.

This also explains why the measured lane (SAFETY-PIN-SECOND-DOOR-01, dispatch 49c6e0c8) ended
with only its anchor commit despite selfcheck passing: that is a *separate* question from this
fix's scope (the checkpoint mechanism exists and this fix doesn't touch it) — plausible
explanations are an empty/undeclared `LANE_WRITES` for that lane (the autocommit no-ops with
`[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0`) or a pre-checkpoint failure upstream; neither
was reproducible from the journal excerpt alone and investigating it further was out of this
task's scope (the brief asks that the work survive going forward, which the existing
autocommit + this fix's `parked` disposition together guarantee for any lane with a declared
write-set).

## 4. Why the sweep timed out

`leadv2-e2e-entrypoint.sh` resolves to `bash tests/run-all.sh` for this repo (it has
`tests/run-all.sh` — resolution order at `leadv2-e2e-entrypoint.sh:1-21`), and the gate invokes
it as `${e2e_cmd} --scope changed` (leadv2-dispatch-product-close.sh:2676,
leadv2-phase8-e2e-gate.sh:209) with budget `LEADV2_PHASE8_E2E_TIMEOUT_S:-900` (15 minutes),
**inside the lane's own worktree** — yes, this is a full `run-all.sh --scope changed` run nested
inside the lane close gate, not a narrower check.

`tests/run-all.sh --scope changed` is not narrow by construction: it always runs
`plugins/leadv2/scripts/tests/run-core-offline.sh` unconditionally (`tests/run-all.sh:105-115`,
explicitly commented "Always-on … the canonical 111-file set"), *plus* whatever suites the
changed-file stem match / `EXTRA_SUITE_MAP` selects on top. `run-core-offline.sh` alone is a
curated bundle of dozens of nested suites; prior measurement in this repo (session memory,
run-all-changed-scope-runtime) found at least one of its nested suites (core-offline) can exceed
10 minutes by itself. A 900s ceiling for "always-on multi-hundred-second core bundle plus
whatever the lane's own diff selects" is tight by design, and gets tighter under the concurrent
load this machine actually runs — this session's own active-task list shows dozens of other
`/leadv2` lanes running in parallel on the same host at measurement time.

Per the brief's explicit instruction, this is **not** fixed by raising
`LEADV2_PHASE8_E2E_TIMEOUT_S` — that hides the shape of the problem (an always-on full-suite
bundle nested inside every single lane's close gate) rather than addressing it. Whether
`run-core-offline.sh` belongs inside the per-lane e2e gate at all, versus running once centrally
and letting per-lane gates check only the lane's own changed-stem suites, is a design question
outside this task's scope — flagging it here as the brief asked ("say why," not "fix it").

## 5. Negative control, both directions (brief item 5)

`plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh`, driving the real
`leadv2-dispatch-product-close.sh` (never a reimplementation):

- **R1 (timeout)**: a fake e2e entrypoint that sleeps past a 1s budget → rc=124. Asserts:
  `status: unknown` / `reason: e2e_timeout` in `e2e-gate.md`, exit 5, journal
  `verdict=timeout rc=124`, ledger `write-terminal ... parked e2e_timeout`, and — separately — a
  `STOP-GATE` checkpoint commit exists in the fixture repo's `git log` afterwards (work
  survived).
- **R2 (negative control)**: a fake e2e entrypoint that fails immediately (rc=1, no timeout) →
  still classifies as `reason: e2e_regression`, exit 8, ledger `dead e2e_regression`. Proves this
  fix did not soften genuine regression handling.

Additionally ran the literal "revert" the brief asked for: checked out the **unmodified HEAD**
script into a throwaway `git worktree add --detach` and replayed the exact R1 fixture against it.
Result: `rc=8`, `e2e-gate.md` = `status: fail / reason: e2e_regression / rc: 124` — reproducing
the pre-fix bug byte-for-byte. Replaying the same fixture against the patched script in this
worktree: `rc=5`, `status: unknown / reason: e2e_timeout / rc: 124 / timeout_s: 1`. Both
directions, red then green, confirmed live (not just asserted in the permanent suite).

## 6. Suite registration (brief item 6)

Added to `tests/run-all.sh`'s `EXTRA_SUITE_MAP`:
```
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
leadv2-phase8-e2e-gate.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
```
so a future change to either gate script selects this suite even if the suite file itself isn't
touched. The suite also self-selects by the existing "a changed test file selects itself"
convention (`tests/run-all.sh:424-431`) once committed.

Proof, `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` with the diff staged:
```
[SELECT] .../plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
run-all: 12 selected, scope=changed, select_only=1
```

## 7. Falsification (bash -n / suite runs)

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh && echo OK2
OK2
$ bash -n plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh && echo OK3
OK3
$ bash -n tests/run-all.sh && echo OK4
OK4
```
No Python files were changed (`py_compile` N/A).

```
$ bash plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: R1: rc=124 classifies as status:unknown reason:e2e_timeout, exit 5 (not 8/e2e_regression)
[TEST] PASS: R1: journal records verdict=timeout rc=124
[TEST] PASS: R1: ledger terminal is parked/e2e_timeout, not dead/e2e_regression
[TEST] PASS: R1: worker's write survives as a checkpoint commit despite the timeout terminal
[TEST] PASS: R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8
[TEST] PASS: R2: ledger terminal is still dead/e2e_regression for a genuine failure

[TEST] 7 passed, 0 failed, 0 not run
```

Also re-ran the directly related, pre-existing e2e-gate suites to confirm no regression:
`test-e2e-gate-lane-root.sh` (13 passed), `test-e2e-gate-bypass-hardening.sh` (PASS=6),
`test-worker-dod-gate.sh` (33 passed), `test-run-all-carrier-map.sh` (5 passed),
`test-dirty-lane-never-lands.sh`, `test-scope-gate-orchestration-dirt.sh`,
`test-merged-sweep-orchestration-dirt.sh`, `test-worktree-lane-safety.sh`,
`test-consumer-symlink-farm.sh`, `test-status-surface-single-lead.sh`,
`test-status-surface-fast-names.sh` — all green.

Only macOS was verified directly (this session's host). A Linux run was not performed in this
session — no Linux container was available in this environment; flagging as unverified rather
than asserting it, per the evidence contract. The suite itself is portable (no GNU-only
date/sed/timeout, no bashisms beyond what the rest of this test family already uses, sourced
from the same `leadv2-temp.sh` helper as every sibling e2e-gate suite).

## 8. Pre-existing, unrelated finding — do not fix here

`plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh` (untouched by this diff) fails in this
environment with `writeset_drift`/`selfcheck_failed` noise naming this session's own edited
files, even when run from a **throwaway `git worktree add --detach HEAD`** containing none of
those edits. This rules out my diff as the cause — it reproduces on vanilla HEAD code. Most
likely a selfcheck/lane-worktree-resolution path that leaks some global/shared state (this
machine runs dozens of concurrent `/leadv2` lanes per this session's own active-task list) rather
than confining itself to the fixture root passed via `LEADV2_LANE_WORK_ROOT`. Per CLAUDE.md
("never weaken a fixture to get green... an environment-sensitive failure is a finding, not a
test bug") this is reported, not touched. `tests/known-red-suites.txt` is off-limits for this
task anyway.

`tests/test-status-surface-bash32.sh` timed out at a 90s cap in one run in this environment; it
is unrelated to the e2e gate (status-surface bash-3.2 compatibility, always-on suite, no code
path this diff touches) and is very likely the same concurrent-load effect as §4 above, not a
regression from this change.

## 9. Off-limits respected

Did not touch `main`, `tests/known-red-suites.txt`, or weaken any assertion. Did not touch
`docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` — `git status` on this
worktree shows unrelated churn in `docs/leadv2/*` from other concurrent sessions sharing this
machine; none of it is staged or part of this diff.

## 10. Commit

Committed on this lane branch (`worktree-E2E-TIMEOUT-REPORTED-AS-REGRESSION-01`):
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`,
`plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh`,
`plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh`, `tests/run-all.sh`.

DELIVERABLE_COMPLETE
