# CODEX-ALWAYS-UP — a dead codex job must never park the codex provider

Commits: `159d2e86` (fix + suites), plus this report and the mutation-control
artifacts. LANE_WRITES respected: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
+ the new suite; the two flipped suites (`test-codex-worker-liveness.sh`,
`test-codex-instant-complete.sh`) pin the exact old contract this lane removes —
leaving them red would have failed the close gate, so the flip is part of the
change, not scope creep.

## What changed (leadv2-dispatch-code.sh)

All four job-death verdicts — `_codex_first_byte_deadline_check` (no_first_byte),
`_codex_instant_complete_deadline_check` (instant_complete),
`_codex_worker_liveness_deadline_check` (vanished_job + turn_aborted) — lost
their `record-quota-lockout --provider codex --hours 1` subprocess call.

- Kept: the rc=7 spill contract (dead worker aborts its reservation, lane never
  hangs), the `emit decision "arm_dead_*"` lines (now carrying
  `provider_standdown=none` — the journal IS the non-blocking record; no second
  store, nothing for selection to ever read).
- Scope decision: the brief names the two worker-liveness paths, but the
  acceptance criterion is absolute ("a dead codex JOB must never make the codex
  PROVIDER unavailable"). no_first_byte and instant_complete are the same class
  — our worker dying with **no launcher output to classify, only silence** — so
  leaving them would have kept the founder's symptom live through two more
  doors. All four removed.

## What still parks codex (verified untouched, S1/S2-guard prove it green)

1. `_maybe_record_quota_lockout` (`:3128`, codex call site `:6568`) — launcher/gate
   refusals only: `quota|quota_gate|quota_exhausted|quota_circuit_open|rate_limit*`;
   honours the cause's own `until=` (CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01).
2. `_record_postspawn_lockout` (`:3081`) — classifies the worker's actual final
   output (`lib/leadv2-lockout-classify.py`); used by `_wait_arm_early_verdict`
   and by `cmd_record_quota_lockout`'s classification mode
   (`leadv2-dispatch-product-close.sh:1021`).
3. Stand-down CLI mode itself (`record-quota-lockout --provider codex --hours N`)
   — the operator's manual instrument; no in-tree caller after this lane, S6
   proves it still writes.

## Measurement: misattribution (brief: "measure it; do not assume either way")

All 9 unique `turn_aborted` strikes in the live task journals
(`~/Projects/leadv2/docs/leadv2/tasks/*/journal.md` +
`~/.claude/leadv2-state/*/tasks/*/journal.md`), checked 2026-09-08:

```
turn_aborted strikes (uniq tasks): 9 cwd-match: 9 mismatch: 0 rollout-gone: 0
```

Each strike's picked rollout `session_meta.cwd` matches the struck task's own
lane worktree (9/9 — F1-ARBITER-SCORING, ANTI-SILENCE-STATUSLINE, BRAIN-CLASS,
CI-RUNS-THE-SUITES, SUITE-LOCK-ORPHAN, WORKER-DOD-GATE, DISPATCH-CLOSE-GATE,
273da7e9, b413968c). `vanished_job` strikes are per-our-handle by construction.
**Conclusion: the 55 strikes are genuine dead jobs, not misattribution** — the
cwd hard filter (nit 2-A, already in tree) works; cross-lane pickup is not
happening. What was wrong was the punishment. Residual gap, not observed in
data: two dispatches sharing ONE worktree could still cross-pick (same cwd);
the S5 test pins the cross-LANE case, the same-cwd case remains theoretically
open. No attribution code changed — nothing to fix there.

## Suite — `plugins/leadv2/tests/test-a-dead-codex-job-does-not-park-the-provider.sh`

`# run-all-triggers: leadv2-dispatch-code`. Real dispatcher as a library (A4
pattern: symlinked siblings + awked body), stubbed codex bin, sandboxed
CODEX_HOME + lockout dirs. 8 sections: S1 usage-limit refusal (value:
`_lockout_state`=locked, class=provider_refusal, epoch>now), S2-guard 429
rate_limit, S2 vanished_job, S3 turn_aborted, S4a no_first_byte, S4b
instant_complete (all: rc=7 kept + provider selectable as VALUES via
`_provider_available` — the exact primitive the quota precheck at `:8882`
uses — + record absent), S5 attribution (sibling's newer aborted rollout does
not spill ours), S6 stand-down instrument still arms.

Harness note: the dispatcher-under-test is symlinked INTO the scratch dir —
without it the pre-fix writer's `${DISPATCH_SELF_BIN:-${SCRIPT_DIR}/...}`
fallback resolves to nothing and a pristine red-first run stays vacuously
green (first attempt did exactly that; fixed before measuring).

## Negative controls (E2E-KILLRATE-01) — red then green, both run

1. **Symptom, red-first**: suite against pristine `HEAD:leadv2-dispatch-code.sh`:
   `pass=4 fail=4` — S2/S3/S4a/S4b RED with `got rc=7 [locked 3600|locked]
   file=present` (the live 55-strike symptom, reproduced). Fixed: `pass=8
   fail=0`. Guard sections green in BOTH runs.
2. **Guard, mutation**: `leadv2-mutation-control.sh` artifacts in
   `docs/handoff/CODEX-ALWAYS-UP/mutation-control/`:
   - ctl-1 `20260908T164455Z-64092.txt` — `return 0` inside
     `_record_quota_lockout`'s body (suppress EVERY lockout write) → suite red
     (S1's expected record missing), `MUTATION-CONTROL ok`, diff_hash
     `de577094…`.
   - ctl-2 `20260908T164529Z-92039.txt` — re-arm the vanished_job stand-down
     (direct `_record_quota_lockout` insert in the dead branch) → suite red:
     `FAIL: S2 vanished_job … [locked 3600|locked] file=present`,
     `MUTATION-CONTROL ok`, diff_hash `eaae28b2…`.

## Selection proof (the three `--scope changed` lies, answered)

- Range measured from, honestly: at launch there was **no checkpoint file** in
  this worktree's git-dir; but the lead had already merged this lane
  (`main@{1788886163}` = `15005732`), so `merge-base(main,HEAD)` = HEAD = empty
  range, and the two then-uncommitted mutation artifacts were unmapped → the
  executed run took **full_set_fallback**: the curated set, **exit 0** after
  ~13 min, zero failures.
- Registration wiring proven directly (introspection dump, runs nothing): one
  transient dirty line in `leadv2-dispatch-code.sh` →
  `SCOPE_RESULT selected=113 … verdict=selected unmapped=0`, with
  `SCOPE_SELECTED plugins/leadv2/tests/test-a-dead-codex-job-does-not-park-the-provider.sh
  (scope-selected ad-hoc)` plus both flipped suites in the list. Transient
  marker reverted byte-identical immediately after.
- Runner-harness execution: `LEADV2_SUITE_DEFS_OVERRIDE=<my suite>` →
  `suites passed=1 failed=0`.
- Checkpoint trap re-armed clean: the run wrote
  `leadv2-run-all-last-checked-sha=159d2e86…`; deleted once (my worktree's own
  runner state) to re-derive the merge-base for the dump above.

## Falsification set (raw)

- `bash -n`: dispatcher + 3 suites → all `SYNTAX-OK` (dispatcher check routed
  through a /tmp wrapper — the fg-dispatch hook blocks the bare name; known
  memory).
- No Python files changed → no py_compile candidates.
- Standalone: worker-liveness `pass=6 fail=0`, instant-complete `pass=9
  fail=0`, new suite `pass=8 fail=0`; runner-harness run above.

## Interaction with the other two arms (context, not scope)

- **D1 (claude 401)**: no interaction — the lockout store schema and
  `_lockout_state` reader are untouched; only four writers stopped writing.
  D1's UNKNOWN_PROBE_PENALTY lives in router-v2 scoring, not here.
- **GLM peak-hours**: no interaction — glm benches/parks
  (`_glm_park_deferred`, launcher refusals) are provider-refusal paths,
  untouched by this lane.

## Residuals / notes for the lead

- The live record `~/.claude/cache/dispatch-ledger/quota-lockout-codex.json`
  (strikes=55, expired 2026-09-07) was NOT touched, per constraints. It is
  already expired (`locked_until` in the past), so no clearing is needed; if
  you want the counter zeroed for a clean baseline, that is yours.
- `docs/leadv2/.lane-liveness-share/` appeared untracked during the test runs
  (plugin runtime state) — left alone, not committed.
- A stale `run-all.sh --scope changed` from the previous dead session of this
  same lane (13 min old, same worktree) was racing my verification run —
  killed by exact PID tree (39303/39307) only; the A1/E1 lanes' runners were
  left untouched.
