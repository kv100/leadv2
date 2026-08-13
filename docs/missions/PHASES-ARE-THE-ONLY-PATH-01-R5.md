# PHASES-ARE-THE-ONLY-PATH-01 — fix round 5 (plugin repo ~/Projects/leadv2)

Round 4 is `f91fd70` in worktree `d4d014e1`. Reviewed: two blocking findings. Full report:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-review-r4.md`.
Continue from `f91fd70`. Scope is exactly B1 and B2. Nothing else.

## B1 — BLOCKING. The review ledger is self-attestable.
The review check requires a ledger row whose `diff_hash` equals `sha256(review.diff)`. Whoever
writes `review.diff` can compute that hash and hand-append
`{"diff_hash":"<hash>","verdict":"PASS","reviewer":"self-forged"}` to
`code-review-ledger/<slug>.jsonl`. Reproduced live in this worktree — `assert` then reports review
satisfied. The new G5a/G5b tests only cover a WRONG hash and a WRONG verdict, never the
correctly-hashed self-forge, which is the case that matters.

**We are not trying to defeat a determined attacker — there is no signing here and none is wanted.
The bar is: a worker cannot satisfy its own review phase from inside its own run.** Achieve that
with provenance, not cryptography. Choose and implement:
- constrain `reviewer` to a known set (the values `record-review` actually writes — find them, do
  not invent a new vocabulary), and reject rows whose reviewer is outside it;
- require the row to have been written by a DIFFERENT process than the one asserting — e.g. the
  row's timestamp must precede the assert and the ledger entry must carry the run-id/handle of a
  review invocation, not of the build worker;
- and make the ledger append path go only through `record-review`, so a raw append is detectable.
State in your report exactly which property you enforced and what it does NOT stop. Do not claim
unforgeability.

Add tests: correctly-hashed row with an unknown `reviewer` → review NOT satisfied. Correctly-hashed
row written by the asserting run itself → review NOT satisfied. Legitimate `record-review` row →
satisfied.

## B2 — BLOCKING. `LEADV2_REQUIRE_PHASES=0` is no longer a full disable.
Round 4 removed the pre-C4 early return that short-circuited before any subprocess. Mode `0` now
always shells out to `phase-record.sh assert` and can still refuse (exit 3 → 1) on config errors or
a refused waiver. `=0` is the documented rollback and the emergency kill switch; it must be
byte-identical to pre-C4 behaviour and must never refuse for any reason.

Restore the early return at the top of the guard, before any subprocess call. Add a test: `=0` with
a deliberately broken phases.yaml and a refused waiver still proceeds, journals nothing, spawns.

## Non-blocking — do these only if they cost nothing
Artifact path resolution allows paths outside `PROJECT_ROOT`; the deploy ancestor check fails
closed but has no positive-pass test. `_sha256` already fails closed on missing/dir/unreadable —
confirmed, leave it.

## Honesty requirement
`test` / `live_verify` / `e2e` remain self-attestable: the artifact is a file the worker wrote and
the only check is that it still hashes the same. The code already says so. Keep that disclosure
and make sure the phase's recorded status reflects it — a self-attested phase must not read as
equivalent to an independently-proven one on the status surface.

## Base / write set
Worktree `d4d014e1`, on top of `f91fd70`. Do not rebase.
`leadv2-phase-record.sh`, `leadv2-dispatch-code.sh`, `tests/test-phase-precondition.sh`,
and `leadv2-dispatch-code.sh`'s review-recording path if B1 needs it. Nothing else.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of both test runs (against `f91fd70`
and after). Every new test must fail against `f91fd70`.
