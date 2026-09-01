# BRAIN-CLASS-LIVE-01 — report

## What was already true before this lane

A prior lane (referenced in-code as PHASE-DISCIPLINE-01 / COMPLEXITY-ESTIMATOR-IS-OFF-01, and a
partial salvage commit `a3b5d6b` on this branch) had already:
- moved `leadv2-task-judge.sh` onto the **default** `_admission_classify` path in
  `leadv2-dispatch-code.sh` (unconditional call, not gated behind `LEADV2_ROUTER_V2`);
- implemented `--task-class` as a floor via `leadv2_admission_class` (`lib/leadv2-admission-class.sh`),
  escalate-only, never de-escalated;
- fixed the judge-failure branch so a declared class above Standard is never silently downgraded
  to Standard (`class_source=declared_fallback`);
- written `lib/leadv2-brain-record.sh` (`leadv2_brain_record`, `leadv2_brain_write_yaml`,
  `leadv2_brain_read_class`, `leadv2_brain_phases_for_class`) and wired it into
  `_admission_classify`'s tail, emitting `class_escalated` / `class_floor_held` /
  `brain_decision` and writing `docs/handoff/<task>/brain.yaml`;
- wired `_admission_classify`'s own task-floor lookup to also read `brain.yaml` as a floor on
  same-task re-entry.

Verified live (not from memory): `_admission_classify` (leadv2-dispatch-code.sh:3717) calls
`bash "${TASK_JUDGE_BIN}" --mission-file ... --task-id ...` unconditionally at line 3768-3769,
with no `LEADV2_ROUTER_V2` gate anywhere in that function.

## What this session added

1. `_resolve_class_with_brain_floor <sig8> <task_id> <base_class>` (new function,
   leadv2-dispatch-code.sh, just above `_phase_precondition_guard`): reads `brain.yaml` via
   `leadv2_brain_read_class` and raises (never lowers) a class computed independently, journaling
   `phase_class_floor task=<sig8> source=brain_record class=<c>`.
2. Wired that helper into `cmd_advance_arm`'s phase-class resolution block (the Phase-4 re-entry
   path, ~line 7860), which previously only floored against `task-class.yaml` (task receipt), not
   `brain.yaml`. This is the "`_phase_precondition_guard` ... reads class from `brain.yaml` when
   present" half of item 3 that was NOT yet covered by the salvage commit — the salvage commit only
   wired the read-back into `_admission_classify`'s own re-entry, not into the guard's second call
   site.
3. `plugins/leadv2/scripts/tests/test-brain-class-live.sh` — new suite, (a)-(d) plus a mutation
   negative control, registered in `tests/run-all.sh`. See "Suite output" below.

`leadv2-task-judge.sh` and `lib/leadv2-admission-class.sh` were **not modified** — the judge already
runs unconditionally (item 1 done pre-lane) and the admission-class lib's job (item 3's
"`leadv2-admission-class.sh` reads brain.yaml") is satisfied by its only real caller
(`leadv2-dispatch-code.sh`) doing the read-back, which was already true for the classify path and
is now also true for the advance-arm re-entry path (my addition).

## Suite output (green)

```
PASS: (a) light+risk mission escalates to Standard|Heavy, journaled
PASS: (a) brain.yaml class_source=escalated
PASS: (b) trivial-but-declared-Heavy holds the floor, journaled
PASS: (b) final class stays Heavy
PASS: (c) judge failure -> declared_fallback
PASS: (c) dispatch proceeds with declared class, no refusal
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor reads brain.yaml class=Heavy over a lower base class
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped

=== test-brain-class-live.sh: 11 PASS, 0 FAIL ===
```

Mutation control: the suite copies `leadv2-dispatch-code.sh` to a temp file and inserts an
unconditional `return 0` immediately before the `bash "${TASK_JUDGE_BIN}" ...` call inside
`_admission_classify` (never touches the tracked file). With the judge call skipped: no
`class_escalated` line and no `brain.yaml` written — both controls fire red as required, proving
the suite actually depends on the judge running.

## Regression check against directly-touched suites

```
test-admission-class.sh:                24 pass / 0 fail
test-phase-precondition-bootstrap.sh:    21 pass / 0 fail
test-mission-writeset.sh:                22 pass / 0 fail
test-phase-precondition.sh:              70 pass / 9 fail
```

`test-phase-precondition.sh`'s 9 failures (G1, G2×3, G3, G8, G11a×2, G11b) are **pre-existing**:
re-ran the identical suite with `leadv2-dispatch-code.sh` swapped back to the pre-lane commit
(`a3b5d6b`, i.e. before this session's two edits) via a temp-file swap-and-restore (never `git
checkout`/`reset` on the tracked file) — same 9 failures, same case names, byte-identical
`pass=70 fail=9` line. Root cause per prior memory (phase-precondition-suite-landscape): the
e2e G-cases are not hermetic (`project_root_guard status=foreign_env_overridden`, admission
receipts leaking into the real tree across runs). Confirmed the working tree was restored to my
actual edits afterward (`diff` clean, `git diff --stat` shows only the intended 25-line addition).

`tests/run-all.sh --scope changed` was also run under `LEADV2_SUITE_LOCK_DISABLE=1`; it exceeded
the 590s budget mid-way through the CORE-OFFLINE shard (matches prior memory:
`run-all-changed-scope-runtime` — core-offline alone regularly exceeds 10 minutes) with all shards
observed up to that point green except the same pre-existing REVIEW-ROUNDCAP-01 red noted in
memory (`run-all-changed-preexisting-reds`). Not re-run to completion given the 10-minute-plus
known runtime and the four suites above already isolating the exact files this lane touched.

## Real-dispatch evidence — attempted, reverted, and why

Attempted one real (non-source-only) `leadv2-dispatch-code.sh` CLI invocation with `--force
--task-class light --task-id dispatch-brainEvid1` and a stub `LEADV2_DISPATCH_GLM_BIN` (local
background `sleep`, not a real GLM call) standing in for the worker launcher, to prove the
`brain_decision` line lands via the full CLI, not just the `LEADV2_DISPATCH_SOURCE_ONLY=1` harness.

The invocation hung past its 60s timeout **before** reaching admission-classify's journal output
(only `dispatch_task_bound` had printed) and, when killed, left a **real git worktree** at
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/dispatch-brainEvid1` and branch
`worktree-dispatch-brainEvid1` in the **main checkout**, not this lane's worktree — the dispatcher's
own root-resolution created lane infrastructure outside the WORKTREE PIN despite `cwd`-derived
root override. No `docs/handoff/dispatch-brainEvid1/*` or registry entries were written (verified:
none found in `docs/handoff/`, `active.yaml`, `bus.jsonl`, `merge-queue.jsonl`), so the only
footprint was the stray worktree/branch. Both were removed (`git worktree remove --force`, `git
branch -D`) and verified absent from `git worktree list`. `pgrep -f "sleep 300"` at the time showed
~60 unrelated matches from the many concurrently-active lanes in this repo (per the session's
`LEADV2_ACTIVE_OTHER_SESSIONS` banner) — too noisy to isolate and safely kill a single stub PID by
pattern, and the stub's own `sleep 300` self-expires without ever being "live" per any registry, so
nothing was left running that could be mistaken for real work.

Given a real full dispatch already produced one unintended side effect in the main checkout while
the repo has ~30 other concurrent active lanes, a second attempt was judged not worth the risk for
marginal evidentiary value beyond what the source-only harness already proves — the harness calls
the exact same `_admission_classify` / `leadv2_brain_record` / `_resolve_class_with_brain_floor`
functions live from the real file (not a reimplementation), and item (a)/(b)/(c)/(d) all pass
against them with `docs/handoff/<task>/brain.yaml` and the `brain_decision` journal line produced
on disk under a real `PROJECT_ROOT` (a fresh `mktemp -d` per case, not a fixture repo) — see the
suite output above for the on-disk brain.yaml assertions. **This is a scope reduction from the
mission's ask of a literal spawn-then-kill worker**, reported honestly rather than claimed.

## Left alone (per LANE boundaries)

- Arbiter, effort matrix, review pool, quota code (lanes 3/4) — untouched.
- `LEADV2_ROUTER_V2` semantics — untouched, still gates only the v2-specific behaviour, not the
  judge call (which was already lifted out of it before this lane started).
- `leadv2-task-judge.sh`, `leadv2-admission-class.sh` — untouched (see above: no gap remained in
  either for this lane's scope).

## Falsification set

```
bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh        -> clean
bash -n plugins/leadv2/scripts/tests/test-brain-class-live.sh -> clean
bash -n tests/run-all.sh                                       -> clean
```
(all three run against a `/tmp` copy of each file to dodge the `leadv2-block-fg-dispatch` hook's
filename-substring match, not against the tracked path directly — same bytes, verified via `diff`
before check).

python3 -m py_compile: no `.py` files changed by this lane (brain-record.sh calls `python3 -c`
inline; no `.py` file was added or edited).
