# D2-UNBLIND-AND-THIRD-STATE-M0M1-01 — fix round 2: rung E4 is green in the fixture and inert in production

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh, docs/handoff/D2-SINGLE-LIVENESS-VERDICT/

M0 and M1 are merged as `8161030c`. M0 is verified and correct — I checked it with the mirror:
`developer.full.md` is now addable and a sibling `other.txt` in the same directory stays ignored, so
the allowlist is scoped rather than a blanket unblind. Your suite is 13/0 over ten consecutive runs,
and I wrote two independent negative controls of my own — one blinding `deliverable_age_s`, one
blinding its call site inside `resolve()` — and both bite (`baseline_rc=0`, `mutated_rc=1`, red line
`verdict=dead:no_log_artifact`). None of that needs redoing.

**But the rung does nothing on the live path, and I can show it.**

## The measurement

Immediately after the merge, on `main`, against three real lanes — two of which had **running
workers at that moment**:

```
D2-UNBLIND-AND-THIRD-STATE-M0M1-01         dead:no_log_artifact
D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01         dead:no_log_artifact
D1-HARDEN-THE-WRITER-M1M3-01               dead:no_log_artifact
```

That is not merely "the third state is missing". The function says **dead** about lanes whose
workers are alive. This is the verdict that cost twelve lanes in one evening, still being emitted
after the fix that was supposed to remove it.

## The cause

`resolve()` builds `lane_dir = os.path.join(root, "docs", "handoff", tid)` and rung E4 searches that
directory for `*.full.md` / `*.summary.md`.

But a lane addressed by its **founder task id** does not keep its deliverable there. Measured:

```
docs/handoff/D2-UNBLIND-AND-THIRD-STATE-M0M1-01/   -> brain.yaml, cost-estimate.yaml, task-class.yaml
docs/handoff/dispatch-472ac5b9/                    -> admission-receipt.yaml, arm-registered, lane-mission.md, phases.d, ...
```

The reports live under `docs/handoff/dispatch-<sig8>/`. E4 looks under `docs/handoff/<tid>/`. For
every lane the lead actually names — and the lead names lanes by founder id, that is what
`--task-id` takes — the rung searches a directory the deliverable is never written to.

Your fixtures pass because they construct `dispatch-`shaped ids. The production caller uses the
other shape. **A test that only exercises the shape production does not use is the thing this whole
wave exists to stop.**

## Your task

1. Make E4 resolve the lane's real handoff directory rather than assuming `tid` names it. A founder
   id must reach the same deliverable as its `dispatch-<sig8>` id. Pick the resolution you can
   defend — the registry row already carries the lane's identity, and there is an existing
   attempt/sig plumbing — but do not silently glob across all of `docs/handoff/`: attributing
   another lane's report to this one would be a false `finished_unlanded`, which is the mirror
   mistake and just as bad.
2. If the directory genuinely cannot be resolved, that is **`unknown:`**, not `dead:`. An
   unresolvable location is a check that could not look, and the brief is explicit that such a case
   is first-class unknown and never coerced to dead.

## The fixtures that were missing

Add cases using a **founder-shaped** lane id (`SOME-TASK-NAME-01`), not only `dispatch-<sig8>`:

- founder-shaped id whose deliverable exists under its dispatch directory → `finished_unlanded:*`;
- founder-shaped id with no deliverable anywhere → still `dead:*`, so the fix was not achieved by
  making every lane look finished;
- a lane whose handoff directory cannot be resolved at all → `unknown:*`.

## Prove it — and prove it the way that would have caught this

Two things, and the second is the one that matters:

1. Ten consecutive suite runs, all counts pasted. Ten, not five — a defect elsewhere in this repo
   tonight appeared twice in thirteen runs and five clean runs would have proven nothing.
2. **A live check, not a fixture.** After your change, run

   ```
   bash plugins/leadv2/scripts/leadv2-lane-liveness.sh --project-root <repo> --lane <a real lane with a live worker>
   ```

   against a lane that actually has a running worker, and paste the verdict. If it still says
   `dead:*`, you are not done regardless of what the suite says. That single command is what
   exposed this round; make it part of your acceptance.

Negative controls, one per changed function body, through the real tool
(`leadv2-mutation-control.sh`, `baseline_rc=0` / `mutated_rc=1`). One is mandatory: **revert the
directory resolution to `docs/handoff/<tid>`** and show the founder-shaped case goes red. Without an
assertion catching that return, this exact regression comes straight back.

## Constraints

- Do NOT touch `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh`, or `tests/run-all.sh` — held
  by another session. Registration stays in `run-core-offline.sh`.
- Do NOT rename `alive`, `starting:*`, `silent:*`, `dead:*` or `child` — the merged reap funnel
  matches those as literals at `leadv2-dispatch-ledger.sh:981`, `:1380`, `:1409`, and that funnel is
  what rescues unlanded work.
- Do NOT edit consumers. The zero-consumer-edit property is why M1 was safe to merge.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.
- Commit the resolution fix and the new fixtures separately.

## Report

Ten suite count lines, the live-lane verdict with the lane name, each control's exit code with its
`baseline_rc`/`mutated_rc` pair and red line, and the commit shas. Nothing else.
