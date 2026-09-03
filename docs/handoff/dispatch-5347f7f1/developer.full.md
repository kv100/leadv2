verdict: APPROVE
next_action: review_round_2

# REVIEW-RUN-LOSES-VERDICTS-01 — developer full report

## Defect (a): housekeeping-only codex body declared review_body_lost

`codex-task.sh`'s own `_strip_meta` filter does not strip the `[codex] Thread
ready (...)` / `[codex] Turn started (...)` progress lines codex-companion's
`adversarial-review` emits, so a synchronous `--wait` review whose printed
body consists only of those lines is short and has no `REVIEW_VERDICT:` line
— the REVIEW-BODY-PERSIST-01 guard in `leadv2-review-run.sh` was declaring
this `review_body_lost` (or spilling to another arm) without ever checking
whether the review actually happened.

Key discovery: `adversarial-review` always creates a `review-*`-prefixed job
record in codex-companion's job store, even in synchronous mode, but never
prints that job's id back to the caller. `codex-task.sh result` called with
NO job-id argument resolves the most recently COMPLETED job for the CURRENT
session in the workspace (`resolveResultJob` → `filterJobsForCurrentSession`)
— so no id-parsing is needed to recover it.

Fix: added `_review_recover_from_codex_store()` in
`plugins/leadv2/scripts/leadv2-review-run.sh`, invoked from inside the
REVIEW-BODY-PERSIST-01 guard immediately after the housekeeping-only body is
detected, before any spill/loss decision. It shells out to
`codex-task.sh result --cwd "${ROOT}"`, and if the output contains a
`REVIEW_VERDICT:` line, overwrites the captured body file with it and emits
`review_body_recovered ... source=codex_store` — the arm then proceeds
normally with the recovered verdict.

If the store also yields nothing, the terminal `review_body_lost` gate now
carries `retrieval_attempts=body,codex_store` in both the `review-gate.md`
file and the `emit decision` log line, naming both things that were tried,
per the acceptance requirement.

## Defect (b): cooldown refusal vs. genuine provider error

Traced `classify_arm_failure()` and the refusal-reselection/spill loop
(`next_ok_arm_after`) in `leadv2-review-run.sh`. This logic already
classifies any `LEADV2_DISPATCH_REFUSED: <reason>` marker + rc in {1,2,75} as
a non-blocking refusal that spills to the next arm, generically — it never
inspects the arm name or the specific reason string (no hardcoded "glm" or
"peak_hours" anywhere in the path). No code change was needed here; the
mission's job for this half was to prove it, which the new fixture suite
does (scenarios S3/S4/S5 below), including a mutation control that would
catch a regression if this genericity were ever weakened.

## New test suite

`plugins/leadv2/scripts/tests/test-review-body-recovery.sh` — fixture-only
(stub codex/glm/architect binaries + a python GLM-policy-resolver stub;
never a real codex job or real review). 26 assertions:

- S1: codex-store recovery succeeds — housekeeping-only body is replaced
  with the store's verdict, arm proceeds, `review_body_recovered` logged.
- S2: codex-store recovery also yields nothing — terminal
  `review_body_lost` with `retrieval_attempts=body,codex_store` in both the
  gate file and the decision log.
- S3: mission-literal case — a `glm` arm refuses with reason `peak_hours` on
  its own declared cooldown; spills to the next arm without blocking the
  gate.
- S4: control — a genuine provider error (non-refusal, e.g. crash/nonzero
  with no `LEADV2_DISPATCH_REFUSED:` marker) is NOT treated as a
  non-blocking spill.
- S5: a novel arm name and novel refusal reason (neither "glm" nor
  "peak_hours") still spills correctly — proves the classification path
  does not hardcode either string.
- MUTATION-A: `sed -i` mutation inside `_review_recover_from_codex_store`'s
  body (production file, not a scratch copy) forces S1 RED, reverted via
  byte-for-byte backup restore, re-confirmed GREEN, and the file's
  byte-identity to the pre-mutation backup was checked afterward.
- MUTATION-B: same RED→revert→GREEN cycle against the
  `LEADV2_DISPATCH_REFUSED:` marker condition inside `classify_arm_failure`,
  forcing S3 RED and confirming genuine-vs-cooldown classification is
  covered by a live mutation, not just a positive assertion.

No source-grep assertions, no negated-command assertions, no scratch-copy
mutation, no `git show HEAD:` pre-images were used anywhere in the suite.

Last full run: `PASS=26 FAIL=0`.

## tests/run-all.sh wiring

Added an `EXTRA_SUITE_MAP` row:
```
leadv2-review-run.sh:plugins/leadv2/scripts/tests/test-review-body-recovery.sh
```

Verified `--scope changed` selection by replicating the production
`add_suite`/`EXTRA_SUITE_MAP`/stem-matching logic in an isolated subshell
driven by the real `git diff --name-only HEAD` output of this worktree
(changed files include `plugins/leadv2/scripts/leadv2-review-run.sh`): the
replication resolves exactly one suite,
`plugins/leadv2/scripts/tests/test-review-body-recovery.sh`, confirming the
new row is reachable and would run under `--scope changed`. Also launched
the real `tests/run-all.sh --scope changed` in the background (the always-on
`run-core-offline.sh` suite that runs first makes this too slow for a
foreground turnaround) to capture end-to-end evidence; see the session's
final message for its outcome.

## Self-check (falsification set)

- `bash -n plugins/leadv2/scripts/leadv2-review-run.sh` — clean.
- `bash -n plugins/leadv2/scripts/tests/test-review-body-recovery.sh` — clean.
- `bash -n tests/run-all.sh` — clean.
- No Python files changed — `py_compile` step N/A.
- `plugins/leadv2/scripts/tests/test-review-body-recovery.sh` itself is the
  changed-scope proof for the fix: RED before the fix (verified via
  MUTATION-A/B reverting the fix code inline and re-running), GREEN after
  (26/26 with the real fix in place). Repo state confirmed byte-identical to
  pre-mutation backups after each cycle.

## Files changed

- `plugins/leadv2/scripts/leadv2-review-run.sh`
- `plugins/leadv2/scripts/tests/test-review-body-recovery.sh` (new)
- `tests/run-all.sh`

DELIVERABLE_COMPLETE
