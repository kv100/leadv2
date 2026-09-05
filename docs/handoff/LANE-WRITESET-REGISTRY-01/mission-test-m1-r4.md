# M1 TEST — the assertion design is wrong, not the extraction. Assert the CAUSE, not an echo.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27` (HEAD `127674d`).
File: `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh`, function
`run_product_close_reclassify_wire`. Nothing else may change. The product code is CORRECT — do
not touch `leadv2-dispatch-product-close.sh`.

## Diagnosis — done by the lead, do not re-derive
The pattern anchor from the last round is FINE. It matches line 2392 and the guard is at 2393,
127 lines are extracted. The failure is in what the case ASSERTS.

The real shape of that region is:

```
  _pc_terminal="refused"; _pc_cause="${blocked_reason}"; _pc_rg_reason="${blocked_reason}"   # 2392
  if [[ "${blocked_reason}" != "partial_diff" && "${blocked_reason}" != "writeset_drift_conflict" ]]; then
      ... recompute _pc_terminal / _pc_cause / _pc_rg_reason ...
  fi                     # <- indented, closes the guard
  emit decision "review_gate ... reason=${_pc_rg_reason} terminal=${_pc_terminal} cause=${_pc_cause}"
  _dl_note ...
  _stamp_review_terminal blocked
  exit 5                 # <- UNCONDITIONAL, outside the guard
fi
```

So `exit 5` runs on BOTH paths. The current case waits for an `echo` after `source`, which can
never print — hence `out1=[]` and a permanent FAIL. The guard does not decide whether to exit;
it decides **what the cause is**.

## What to assert instead
Capture what the snippet EMITS, not what runs after it. Stub `emit` so it records its argument
(e.g. `emit() { printf '%s\n' "$*" >> "$EMITTED"; }`), run the snippet, and assert on the
recorded `review_gate` line — or on `review-gate.md` if the stub path writes one.

1. `blocked_reason=writeset_drift_conflict` → the emitted line carries
   `cause=writeset_drift_conflict` / `reason=writeset_drift_conflict`. The guard did NOT
   recompute it.
2. `blocked_reason=foreign_commit` (any other non-`partial_diff`) → the emitted line carries a
   cause DIFFERENT from `foreign_commit`, proving the branch still fires for the reason it was
   written for. A case that only checks direction 1 would pass if someone deleted the branch.

Expect `exit 5` in both directions — treat a non-zero rc as normal, not as failure. Keep the
pattern anchor and the loud "pattern not found" guard from the last round.

## Proof — paste all of it
1. Full suite in the lane: the exact line `Results: PASS=7 FAIL=0`.
2. Negative control in a SCRATCH copy (never the lane): delete
   `&& "${blocked_reason}" != "writeset_drift_conflict"` from the guard, re-run — the M1 case
   must go RED, because the cause now gets recomputed. Paste it.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite selected.
4. `git commit`, then `git status --porcelain` showing nothing modified under `plugins/`.

## If it still will not work
Return `BLOCKED` with the exact command and output that defeated you. Do not leave a failing
case in the suite, and do not weaken an assertion to make it pass — say so instead.

Return `PASS|FAIL|BLOCKED` + commit SHA + both runs (RED and GREEN) verbatim.
