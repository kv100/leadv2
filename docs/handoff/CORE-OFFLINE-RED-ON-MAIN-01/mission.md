# Mission — main's test suite is RED and it is blocking every lane

Repo: ~/Projects/leadv2. **Top priority: this blocks the whole board.**

## Measured 2026-08-23 — not a hypothesis

`bash plugins/leadv2/scripts/tests/run-core-offline.sh` on **clean main (6fa4823)**
fails. Two reported failures, both from ONE file
(`plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh`):

```
FAIL: (d) expected sonnet-fallback line missing from rendered artifact
      -- content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1 ...
[CORE-OFFLINE] FAILED: deferred-GLM ladder (V3-GLM-LADDER-01)
```

Consequence: `leadv2-dispatch-product-close.sh`'s e2e gate runs core-offline in
changed-scope, so **every lane touching plugin scripts fails with
`status: fail / reason: e2e_regression`.** Two lanes died on it tonight
(`67198a6e` -> f05eddf, `be70b3f8` -> 8f0e066) with byte-identical failure
signatures, and a third lane's report on 2026-08-23 already dismissed this pair as
"pre-existing, unrelated" — it was right, and nobody fixed it.

## Origin

`git log -- plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` top commit is
`4077109` (2026-08-20), whose own message says: *"worker died at acceptance wait; lead
checkpoints before suite verify"*. It landed on main explicitly unverified and left the
suite red for three days. The feature commit under it (`389820a`, V3-GLM-LADDER-01) is
real work — **do not blanket-revert it.**

That same commit also tracked files that must never be in git:
`plugins/leadv2/scripts/tests/docs/leadv2/.bus.lock`, `.merge.lock`,
`active.yaml.lock`, `.bus-offsets`, `bus.jsonl`, `active.yaml`, `merge-queue.jsonl`,
`open-threads.md`. Lock/state fixtures committed as repo content.

## Do

1. **Diagnose case (d) before changing anything.** It is at
   `test-glm-deferred-ladder.sh` around L285-297: it runs `leadv2-broad-status.sh`
   against a stub collector with `LEADV2_BROAD_STATUS_DISPATCHED=1` and asserts the
   rendered `founder-status.md` contains
   `sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate)`. The rendered artifact does not
   contain it. Determine which side is wrong — the renderer never emits that counter, or
   the test's fixture does not actually produce a fallback the renderer can count.
   State the mechanism with file:line evidence before you fix it.
2. **Fix the side that is actually broken.** If the renderer is missing the counter,
   implement it (the founder wants a loud sonnet-fallback count — that was the point of
   389820a). If the test's fixture is wrong, fix the fixture. Do not delete the test, do
   not mark it skipped, do not weaken the assertion to something that always passes.
   The negative case just below it (zero fallbacks -> no line) must keep passing.
3. **Untrack the committed lock/state fixtures** listed above (`git rm --cached`) and add
   the right ignore rules so a test run cannot dirty the repo again. If any of them is a
   genuine required fixture, say so and keep it — but a `.lock` never is.
4. `run-core-offline.sh` must exit 0 on the resulting tree.

## Off-limits

- Do not revert `389820a`.
- Do not touch the main tree's unrelated uncommitted files (another session owns them):
  no `git stash`, no `reset`, no `clean`.
- Do not "fix" the e2e gate to ignore failures. The gate is right; main is red.

## Verify (real pasted output, not claims)

1. `bash plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` — full output, all
   cases including the negative one.
2. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — final counts + exit code.
3. `git status --porcelain` after a full suite run: the run must leave the tree clean.
4. Name any failure you did NOT fix and why it is out of scope.

## Deliverable

`docs/handoff/CORE-OFFLINE-RED-ON-MAIN-01/report.md` — the mechanism with file:line,
which side was wrong and why, the four verifications with pasted output, and
`git diff --stat`. End with DELIVERABLE_COMPLETE.
