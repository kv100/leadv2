# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — developer full report

## What changed

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (`pc_scope_diff()`):

1. **E1** — hoisted lane-worktree resolution out of the `if [[ "${CROSS_REPO_DIFF}" == "1" ]]`
   guard so it runs unconditionally. `CROSS_REPO_DIFF` now controls only the multi-repo
   per-write grouping branch (unchanged, ~line 960-1008). Comment block above the
   resolution updated to record the narrowed meaning and cite this mission id.
2. **New helper `_pc_lane_dirty <root>`** (beside `_pc_diff_base`) — rc0 iff `<root>` is a
   git work tree with ≥1 uncommitted tracked change or untracked file, after excluding
   `docs/leadv2/` and `docs/handoff/` (same exclusion set as `_pc_git_diff`). Read-only,
   never touches the index.
3. **E2** — inside the empty-diff branch, before falling to `no_work`: if `_lane_root` is
   set/exists and `_pc_lane_dirty "${_lane_root}"` is true, terminal becomes
   `refused`/`unscoped_lane_work` (not a new ledger word — `refused` already exists and is
   retryable, same treatment as `partial_diff`). Otherwise the existing `no_work`/
   `empty_diff`/`asked_into_void` path is unchanged. `review-gate.md` gains a `dirty: <n>`
   line and `_dl_note` gets `lane_root=<basename> dirty=<n>` evidence, only on the new
   branch.

`plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` (new, 4 cases, mirrors
`test-landing-diff-scoping.sh`'s sandbox/tripwire/red-first pattern):
- C1 — lane worktree with an uncommitted tracked modification → non-empty diff, not `no_work`.
- C2 — lane worktree with a new untracked file (matching LANE_WRITES) → non-empty diff, not `no_work`.
- C3 — lane worktree clean → `terminal=no_work cause=empty_diff` (anti-rescue case).
- C4 — lane dirty only under `docs/handoff/` → `terminal=no_work` (exclusion-set case).

`plugins/leadv2/scripts/tests/run-core-offline.sh` — registered the new suite beside the
existing product-close checks (line 88).

## Test output — new suite, standalone

```
[TEST] PASS C1-tracked-mod
[TEST] PASS C2-untracked-new
[TEST] PASS C3-clean-anti-rescue
[TEST] PASS C4-handoff-only-dirt
[TEST] FAIL C1-tracked-mod
[TEST] FAIL C2-untracked-new
[TEST] PASS C3-clean-anti-rescue
[TEST] PASS C4-handoff-only-dirt

Results (post-fix, live tree): 4 passed, 0 failed
red-first: 2/4 post-fix-passing cases RED against pre-fix
GREEN-PRE-FIX (not evidence): C3-clean-anti-rescue
GREEN-PRE-FIX (not evidence): C4-handoff-only-dirt
pre-fix-could-not-run: 0
```

All 4 pass post-fix. C1/C2 (the cases proving the fix) are RED against the pre-fix
`git archive HEAD` reconstruction, as required. C3/C4 (the anti-rescue / exclusion-set
cases) are correctly GREEN-PRE-FIX — they never depended on this bug — and are reported
as such, not folded into evidence.

## Test output — full `run-core-offline.sh` (this worktree)

```
[CORE-OFFLINE] product-close scopes a single-repo lane worktree
[TEST] PASS C1-tracked-mod
[TEST] PASS C2-untracked-new
[TEST] PASS C3-clean-anti-rescue
[TEST] PASS C4-handoff-only-dirt
Results (post-fix, live tree): 4 passed, 0 failed

[CORE-OFFLINE] review body persist (opus/sonnet materialisation + body_lost guard)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: /bin/bash 3.2 -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Test (a) deliverable: exit 0
[TEST] PASS: Test (a): review-sonnet.md has both contract lines
[TEST] PASS: Test (a): review-sonnet.md is 688 bytes (full body materialised, not 97)
[TEST] PASS: Test (a): review-sonnet.md contains the numbered findings prose
[TEST] PASS: Test (a2) stream-fallback: exit 0
[TEST] PASS: Test (a2): review-sonnet.md has REVIEW_VERDICT from stream transcript
[TEST] PASS: Test (a2): review-sonnet.md is 413 bytes (stream body recovered)
[TEST] PASS: Test (b) body_lost: exit 6
[TEST] PASS: Test (b): review-gate.md status=blocked reason=review_body_lost
[TEST] PASS: Test (c) glm-regression: exit 0
[TEST] PASS: Test (c): review-gate.md status=pass — guard did not trip on healthy glm arm

[TEST] 13 passed, 0 failed

[CORE-OFFLINE] core-offline root arithmetic (git-derived REPO_ROOT)
[ROOT-ARITH] cases passed=4 failed=0

[CORE-OFFLINE] suites passed=31 failed=4 missing=0 repo=<this worktree>
```

The "review body persist" sub-suite (mentioned in the mission as already failing from
inside a lane worktree with this exact defect's symptom) is now **13/13 PASS** — it went
green because of this fix, as the acceptance criteria required.

### The 4 failing suites — all pre-existing, none touch `leadv2-dispatch-product-close.sh`

- `dispatch refusal fallback chain` (`test-routing-enforcement-p1.sh`)
- `hook token + mode isolation` (`test-hook-token-mode-isolation.sh`)
- `landed-at-spawn (no terminal=landed at spawn; target repo keying)` (`test-landed-at-spawn.sh`)
- `lane placement pin (--resume-lane/--worktree)` (`test-lane-placement-pin.sh`)

None of these four test files reference `leadv2-dispatch-product-close.sh` (grepped —
zero hits). I ran all four directly against the **unmodified main checkout**
(`~/Projects/leadv2`, clean of this branch's edits) and every one fails identically
there:

```
=== test-routing-enforcement-p1.sh ===         rc=1  (dispatch_refused reason=duplicate_task_signature)
=== test-hook-token-mode-isolation.sh ===       rc=1  ([TEST] FAIL: parallel lead task hook selected the wrong registry row)
=== test-landed-at-spawn.sh ===                 rc=1  ([LANDED-AT-SPAWN-01] passed=9 failed=3)
```

`test-lane-placement-pin.sh` run standalone against main: `[LANE-PLACEMENT-01]
passed=13 failed=11` — same 11 failures (P-g/P-h/P-i cluster around a worktree-resume
prompt-pin line), same shape as inside this worktree. These are pre-existing
environmental/test-state failures (duplicate-signature races, registry-row lookup,
placement-pin prompt text) unrelated to diff-scoping. Per the repo's own rule
("establish whether it fails on clean main before touching it — an environment-sensitive
failure is a finding, not a test bug"), I left them alone.

## `bash -n` — all touched files

```
bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh  -> clean
bash -n plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh -> clean
bash -n plugins/leadv2/scripts/tests/run-core-offline.sh -> clean
```

## R1 (design-acknowledged): `test-landing-diff-scoping.sh` Q3-pair now fails

Ran `test-landing-diff-scoping.sh` per the design's explicit instruction. Result: 10
passed, 1 failed (Q3-pair); red-first 0/10 (none of the 10 that still pass regressed —
they're all green pre-fix too, i.e. unaffected by this change).

Q3-pair asserted that `CROSS_REPO_DIFF=0` is a full revert: with a worktree left
deliberately empty and a real edit made *outside* it (in the main checkout), the old
code diffed the empty worktree when the flag was ON (0 bytes, blocked) and diffed the
main checkout when the flag was OFF (>0 bytes, unblocked) — i.e. the flag flipped
*which tree got diffed*. Post-fix, diff_root always resolves to the lane worktree
regardless of the flag, so both ON and OFF now diff the (empty) worktree — 0
bytes/blocked in both cases — and the pair's "must differ" assertion fails.

This is exactly the outcome the design's R1 risk predicted and explicitly authorized:
*"CROSS_REPO_DIFF=0 is no longer a full revert... Expected and mission-ordered... do
not re-conditionalise E1 to make it pass."* `test-landing-diff-scoping.sh` is outside
this task's `LANE_WRITES` (only `leadv2-dispatch-product-close.sh`,
`test-lane-diff-single-repo.sh`, `run-core-offline.sh` are in scope), so I did not edit
it. Per the design, this delta is reported here rather than silently patched: Q3's
"flag flips the outcome" claim should be re-scoped in a follow-up to assert the flag
flips the *multi-repo grouping* (partial_diff detection) instead of root resolution —
left for the lead to schedule as separate work, not bundled into this diff.

## Out of scope / left alone (per design §7)

`partial_diff`/`asked_into_void`/`unscopable_diff` semantics, the multi-repo grouping
branch, `_pc_git_diff`/`_pc_diff_base`/`_pc_repo_diff` internals, `leadv2-lane-worktree.sh`,
`leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh`, `LEADV2_REVIEW_DIFF_CROSS_REPO`
removal, any shared tree, any other gate — all untouched.

DELIVERABLE_COMPLETE
