# LANE-TRUTH-BATCH-01-MUTATION-GATE-HEAD-STILL-RED-01 — lane report

## Verdict (one sentence)

**NOT REPRODUCED — the "Row 1 mutation gate HEAD" case is green at every clean tree
tested, including a byte-exact export of `79d0986f`, the very commit the mission
measured red 4/4; the historical defect was fixture-side (`never_reaches_subject`
/ `environment_dependent`: the gate's dispatch registration never happened inside
the fixture) and was already fixed before this lane started by
`fae0f13e` (per-task worktree shape) + `60628b0a` (hermetic `config/` copy),
landed by lane `LANE-LIVENESS-E0-GUARD-FIXTURE-COLLAPSES-EVERY-CASE-01` — so this
lane changed zero code and the assertion now passes for the right reason.**

Boundary for every count in this report: macOS Darwin 25.6.0, bash 3.2, per-suite
ceiling 400 s (mission's own ceiling; the suite exceeds the census 120 s), rc
measured unpiped.

## Why this lane exists vs what is on record

The mission was cut in `e9cdf0fc` from an observed `dead:no_log_artifact` verdict
and states the red was measured 3× on main and 1× at lane HEAD `79d0986f`. But
`79d0986f` is the E0-guard lane's report commit (2026-09-17 06:26), and that
lane's report — committed in the very same tree — already documents this suite's
Row 1 chain as **diagnosed and fixed fixture-side**:

- `fae0f13e` (05:08): the gate fixture registered `worktree == project root`,
  the exact shape the E0 contradiction guard refuses, so the gate's registration
  rung never executed ("never reaches subject"); fixture now registers a per-task
  worktree.
- `60628b0a` (06:03): the scratch plugin copied `scripts/` + `workflows/` but not
  `config/`, so under the runner's scrubbed env the routing resolver fell through
  to ambient `$HOME/Projects/leadv2` and dispatch REFUSED (unresolvable routing
  config) — registration never happened and only MUT-HEAD reddened (15/1).
  Fixture now copies `config/` (tracked, 15 files — self-contained in any
  checkout).

Both commits are ancestors of `79d0986f` (verified: `git merge-base --is-ancestor`).
Per lane-rules order-of-work step 1 ("if it does not reproduce, say so and stop —
a fix for a failure you never saw is a guess"), this lane stopped after
falsification and produced the evidence below instead of "fixing" green code.

## Evidence 1 — the case does not reproduce, at two commits, two envs

| # | tree | env | rc | pass/fail | wall |
|---|------|-----|----|-----------|------|
| R1 | lane worktree `d46831ad` (clean) | plain shell | 0 | 16/0 | not recorded, < 400 s |
| R2 | byte-exact `git archive` export of **`79d0986f`** (mission's claimed-red HEAD) | plain shell | 0 | 16/0 | not recorded, < 400 s |
| R3 | lane worktree `d46831ad` | faithful `run-core-offline.sh` suite env (denylist scrub `LEADV2_*`/`CLAUDE_*`/`GIT_CONFIG*`/`DRY_RUN`/`GIT_*`/`PROJECT_ROOT`, private TMPDIR, empty sandboxed HOME, retained PYTHONUSERBASE) | 0 | 16/0 | 99 s |

R2 refutes the mission's "identical every time at `79d0986f`": on the committed
bytes of that commit the case passes. The mission's red observations are consistent
only with pre-`60628b0a` fixture bytes (its "on main" measurements) or with
non-committed on-disk state in whatever worktree hosted the `79d0986f` measurement
(same shape as the recorded `suite-red-check-worktree-vs-blob` incident: on-disk
bytes ≠ blob).

Command (R1/R3): `bash plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh`
R2: `git archive 79d0986f plugins/leadv2 | tar -x -C /tmp/probe79` then the same
command from the export. R3 wraps the suite in the reconstruction script shown in
`artifacts/harness-env-run.sh`.

## Evidence 2 — the disk-look determination the mission demanded

Verbatim fixture function (sed-extracted from the suite, not re-implemented),
one MUT-HEAD gate scenario, then the disk listed at the paths the gate computes
(full raw output: `artifacts/muthead-probe.out`):

- Registry row the gate reads (`docs/leadv2/active.yaml` ≡ `state/active.yaml`
  inside the scratch gate root):
  `task_id: MUT-HEAD … log_path: docs/handoff/dispatch-89291c44/developer.stream.jsonl`
  — the registration DOES happen at HEAD, and the row points exactly where the
  fixture stamps.
- What is on disk (`find …/docs/handoff -mindepth 1`):
  `dispatch-89291c44/developer.stream.jsonl` (38 bytes, the fixture's stamp) plus
  `dispatch-89291c44/admission-receipt.yaml`, `phases.d/` stamped by dispatch
  itself, and `MUT-HEAD/{brain,cost-estimate,task-class}.yaml`.
- Liveness verdict for lane MUT-HEAD:
  `{"verdict":"alive","age_s":2,"reason":"log_fresh","raw_log_path":"docs/handoff/dispatch-89291c44/developer.stream.jsonl","pid_source":"lead_durable","pid_identity":"verified",…}`

**Determination: fixture and gate now agree.** The fixture stamps precisely the
stream the registry row names; the gate resolves it alive via `log_fresh`. The
historical defect was in the fixture (registration never happened → the gate was
*correctly* reporting a lane it could not see), not in the gate's lane-named
lookup. The production gate was never touched by this lane.

## Evidence 3 — the assertion is load-bearing (negative control)

Claim: "without the fixture's hermetic `config/` copy, under the harness env, the
exact case returns red at the mission's 15/1 boundary."

Manual control (preliminary, wall 12 s — dispatch refuses fast without config):
target asserted present exactly once (`grep -cF` = 1, `test-lane-truth-batch-01.sh:37`),
line commented out, suite run under the harness env:

```
[TEST] FAIL: Row 1 mutation gate HEAD must resolve stamped stream alive
  got: {"lane":"MUT-HEAD","verdict":"unknown:yaml_unreadable","age_s":null,"source":"handoff",
        "log_path":null,"raw_log_path":null,"pid":null,"pid_alive":null,"reason":"registry_unreadable",…}
[LANE-TRUTH-BATCH-01] pass=15 fail=1      (rc=1)
```

then reverted (`git checkout --`), tree verified byte-identical to HEAD (empty
`git diff --stat`). Rung note: the mission's paste shows the sibling terminal rung
`dead:no_log_artifact`; the control here stops at `unknown:yaml_unreadable /
registry_unreadable` — both are the same "registration never happened → no
registry row → handoff ladder" family; which rung terminates the ladder depends on
how far dispatch got before refusing (whether `docs/handoff/<lane>` exists yet).

Machine-backed control via `leadv2-mutation-control.sh --live` (same sed, same
harness env, applied to the real lane file and restored by the tool):
**`MUTATION-CONTROL ok mode=live … red_line=[TEST] FAIL: Row 1 mutation gate HEAD
must resolve stamped stream alive … porcelain_clean=yes`** (rc=0, wall 121 s) —
artifact `mutation-control/20260917T091803Z-live-48459.txt`, bound to report
commit `b9c05c3b` (`lane_diff_hash=39568b4c…`). The tool refuses an empty lane
diff, which is why the control ran after the report commit.

## Self-check (falsification set)

- Shell files changed by this lane: **none** in production code (`git diff
  --name-only 68849682..HEAD` = report + artifacts only); `bash -n` run on the
  two committed probe scripts instead — both clean (`bash -n` rc=0).
- Python files changed: none — `py_compile` N/A.
- Changed-scope selection: lane diff is `docs/handoff/<lane>/*` only — no
  production file changed, so no suite selection is owed; the one suite this
  mission names was run four times in full anyway (R1–R3 green, control red).
