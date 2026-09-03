# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — round 4: the gate now fails silently instead of loudly

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01`

LANE_WRITES: plugins/leadv2/config/freepool-arm.yaml,plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh,plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh,plugins/leadv2/scripts/tests/test-worker-output-gate.sh,plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh,tests/run-all.sh,docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/

Full report: `docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/review-r3.md`. HEAD is `510524f` —
that commit was made by the lead after the round-3 worker died with the work uncommitted.

**Confirmed real by an independent reviewer who reproduced each one — keep them all:** the
empty-diff crash fix (C-1), the production call-shape test (C-3), both single-source violations
removed, and the bash-3.2 sweep. Gate 12/0, model-liveness 6/0, arm-capability 4/0.

## [Critical] C-2 — the gate now returns a silent PASS instead of a loud crash

Live-tested: with a committed file that fails `bash -n`, in a repo that has **no `origin/main`
ref**, the gate returns `rc=0`. It reports success on broken committed code.

That is the original defect wearing new clothes. Round 3 replaced "crashes and is read as
`parse_error`" with "silently passes", and a silent pass is the worse of the two — a crash at least
stopped the close.

Lane worktrees frequently have no `origin/main`, so this is the common case, not an edge one.

Make the missing-ref case explicit: if the committed range cannot be resolved, the gate must say so
and must not report a pass. Then add a control: a repo with no `origin/main`, a committed file that
fails `bash -n`, and an assertion that the gate does **not** return 0. Mutate the fix out and show
RED.

## [High] the ranking claims evidence that does not exist

`freepool-arm.yaml` says the new ranking comes from a "round-3 bash-3.2 editing bakeoff". Only
`bakeoff/round2/` exists on disk, it ran the same trivial task, and 4 of 5 candidates still emitted
byte-identical output.

So the config asserts a provenance it does not have. Either run the discriminating bakeoff and put
its output on disk under `bakeoff/round4/`, or change the yaml comment to say plainly that the
ranking is by latency. A configuration file that cites evidence nobody can open is the same disease
as a test that asserts nothing.

If you run it: use a task where a weak model plausibly fails — editing a real shell function under
bash-3.2 constraints — and rank on `bash -n`-clean, behaviourally-correct output.

## [High] `report.md` still says "Pending execution"

The "Final falsification set" section was never replaced before the commit. Fill it in with what
actually ran, or delete the section. A report that describes work as pending, in a commit that
claims it is done, is how a round gets misread as finished.

## [Medium] two process items

- The round-3 brief was not in the lane. Briefs now land in the lane's own
  `docs/handoff/<TASK-ID>/` — this file is there. Keep round-4's artifacts beside it.
- `.gitignore:40` hides `docs/handoff/*/*`. Commit artifacts with `git add -f <file>`, one file at
  a time. Do not edit `.gitignore`.
- Item 8 (`--scope changed` on a `freepool-arm.yaml`-only change) was traced statically but the
  live run stalled on a lock held by another orchestrator in this shared worktree. Re-run it and
  paste the real output.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); **no mutation of a scratch copy** — `test-freepool-model-liveness.sh` prints
  "(scratch copy)" and the reviewer had to redo it against production to know it was real. Mutate
  production.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set before committing and paste the runs.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

The gate refusing to return 0 on committed-broken code with no `origin/main`, held by a
mutation-proven control; the ranking either backed by a discriminating bakeoff on disk or honestly
labelled as latency-ordered; `report.md` with no "pending" section; `--scope changed` proven live;
and `report.md`'s first line naming the model each role will actually run, with the per-role
selector timings.
