# Mission — a worker that ends its turn WAITING is treated as finished; fix both sides

Repo: ~/Projects/leadv2. **Board-level blocker: this is why lanes deliver `wip` stubs.**

## Measured 2026-08-23 — mechanism, not theory

Lane `b7bcf98a`'s stream (`docs/handoff/dispatch-b7bcf98a/developer.stream.jsonl`)
contains a normal completion record: `"subtype":"success"`, `is_error:false`,
`num_turns:32`, `duration_ms:447225`. The worker's final result text is, verbatim:

> `Standing by for the background test result — no further action until it completes.`

The worker did not crash and was not quota-killed. **It ended its turn waiting on its
own backgrounded test run.** The lane read a clean exit, `pc_stop_gate_autocommit`
committed the half-finished tree as
`wip(<sig>): auto-checkpoint on worker exit (STOP-GATE)`
(`leadv2-dispatch-product-close.sh:1563`), and the e2e gate then failed the lane.

`git log --since="7 days ago" main | grep -c "wip("` = **15**. Commit `4077109`, the one
that left `run-core-offline.sh` red on main for three days, says in its own message
"worker died at acceptance wait" — the same shape: waiting, not dying.

Why the existing recovery never fires: `pc_dwr_resume_once`
(`leadv2-dispatch-product-close.sh:605`) requires
`_pc_lane_outcome == "died-with-work"` (L621). A clean `success` exit never matches, so
the one-shot resume is skipped and the checkpoint path runs instead.

## Fix BOTH halves

### A. Prevention — a mission contract line for every arm

`_spawn_worker_body` (`leadv2-dispatch-code.sh:3207-3228`) already prepends
`_LEADV2_EVIDENCE_CONTRACT_MISSION` to every arm's mission at one site. Add a second
contract constant beside it in `leadv2-helpers.sh` (next to the existing one at L63-64,
same `readonly` + `[[ -z ... ]]` guard shape) and prepend it at the same site, so all
four arms (glm/kimi/sonnet/codex) get it with no per-arm drift.

Its content must require, in the worker's own words-to-follow:
- never end a turn while a job you started is still running;
- run verification (test suites, builds) in the FOREGROUND with an explicit timeout;
- if a job must run detached, you must wait for and report its result in the SAME turn
  before finishing;
- "standing by" / "waiting for" / "will report when it completes" as a final message is
  a protocol violation, not a completion.

Placement invariant is load-bearing: prepend AFTER compute_sig/classify/router, exactly
like the existing two lines, or sig8 changes and dedup breaks. Order: pin line, then
contracts, then mission body.

### B. Recovery — recognise the parked exit as resumable

A clean-exit worker whose final result text says it is waiting, AND whose declared work
is incomplete (no deliverable/summary artifact), must NOT go down the checkpoint+gate
path. Make it eligible for the existing one-shot `pc_dwr_resume_once` (a distinct
outcome value beside `died-with-work` is fine — do not silently widen
`died-with-work` itself, other callers read it). Keep the once-per-lane marker
semantics exactly as they are: still exactly one resume attempt, never a loop.

If the resume also comes back parked, THEN fall through to today's behaviour, but the
checkpoint commit message must say `parked-on-background-job`, not
`auto-checkpoint on worker exit` — the current wording is what made three sessions read
"crashed" when the worker was waiting.

## Off-limits
- Do not remove or weaken the STOP-GATE checkpoint itself. It is the safety net that
  preserved tonight's work; it just fires on the wrong classification.
- Do not touch the e2e gate or any test's assertions.
- Do not touch main's unrelated uncommitted files (another session owns them):
  no stash/reset/clean.

## Verify (real pasted output)
1. A test proving the contract text reaches the mission for each of the four arms
   (resolve-only is fine: `LEADV2_DISPATCH_SPAWN=0`), and that sig8 is byte-identical
   with and without it.
2. A test replaying a stream whose final record is a clean `success` with a
   "standing by"-shaped result AND no deliverable: assert one resume attempt, and that
   a second such exit does NOT loop.
3. A positive control: a genuine `died-with-work` exit still resumes exactly as today.
4. A negative control: a clean `success` WITH a deliverable does NOT trigger a resume.
5. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Two
   failures are known-pre-existing and NOT yours to fix here: `deferred-GLM ladder
   (V3-GLM-LADDER-01)` and `fanout classifier/runner guard`. Name them and move on.

## Deliverable
`docs/handoff/WORKER-PARKED-ON-BG-01/report.md` — changed lines with file:line, the five
verifications with pasted output, `git diff --stat`. **Run your verification in the
foreground; do not end your turn waiting on a background job — that is the very bug you
are fixing.** End with DELIVERABLE_COMPLETE.
