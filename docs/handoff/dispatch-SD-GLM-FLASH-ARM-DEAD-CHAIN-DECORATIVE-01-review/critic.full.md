# critic — armfix.diff, ROUND 2 (verification-only)

REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=0 low=3

No Critical or High findings. All four prior findings verified fixed by execution and by
reading the live tree (the diff is applied in the worktree). Round-1 analysis is preserved
at `critic.round1.full.md`.

## Prior-finding verification

### 1. [High] product-close:861 — quota-advance caller never set `_PC_CONTINUATION_HANDED_OFF` — FIXED
`leadv2-dispatch-product-close.sh:858-863`:
```
if _pc_arm_advance; then
  _PC_CONTINUATION_HANDED_OFF=1
  emit decision "review_gate ... action=arm_advanced arm=${arm}"
  exit 5
fi
```
Reachability verified so the `exit` is not swallowed by a subshell: `_pc_maybe_quota_advance`
is called only from `pc_worker_alive` (lines 1030 and 1094), and `pc_worker_alive` has exactly
one call site — `if ! pc_worker_alive; then` at line 1246, in the main shell. So `exit 5`
terminates the close process and the flag reaches `_pc_exit_handler`, whose new early return
(lines 229-231) suppresses both the write-once terminal and `leadv2_tasks_unclaim`. Symmetric
with the silent-arm caller at 2527.

### 2. [High] dispatch-code.sh:4631 `_glm_model="glm-4.7"` — FIXED (hunk gone, id corrected)
`grep -n "glm-4.7"` over `leadv2-dispatch-code.sh` and over `armfix.diff`: zero matches. The
live line is `_glm_model="glm-5.3-flash"` (dispatch-code.sh:4628), and that id is confirmed by
the provider's own run metadata:
```
$ grep -E 'model|exit_code' ~/.claude/cache/glm-runs/260829-042322-cd7dad21-32e8/meta.yaml
model: glm-5.3-flash
exit_code: 0
```
The hunk is no longer part of this diff, so the out-of-scope objection is moot too.

### 3. [High] fix.md:3 — untagged evidence-free provider-runtime root-cause claim — FIXED
fix.md now carries an `## F4 evidence` section naming the four preserved run dirs. Re-probed
independently; all four exist and match the claim exactly:
```
260829-042322-cd7dad21-32e8  model: glm-5.3-flash  status: complete  exit_code: 0  duration_s: 106
260829-042325-d458df09-4e07  model: glm-5.3-flash  status: complete  exit_code: 0  duration_s: 188
260829-043252-95fdcfe2-5029  model: glm-5.3-flash  status: complete  exit_code: 0  duration_s: 80
260829-043355-baa812c9-5ebb  model: glm-5.3-flash  status: complete  exit_code: 0  duration_s: 122
```
"Four runs, exit 0, 80-188s" is now artifact-backed, not asserted.

### 4. [High] dispatch-code.sh:7371 — loop broke on rc=0 with no parsed handle — FIXED
`cmd_advance_arm` now breaks only when `candidate_handle` is non-empty; an rc=0 spawn with no
handle emits `arm_advance_failed ... reason=missing_handle rc=0`, appends the candidate to
`attempted_csv`, and keeps walking. `attempts=none` is now reachable only if every element of
`candidate_arms` is the empty string, which the preceding fallback block prevents
(`candidate_arms=("${arm}")`). Exhaustion exits 4 → `_pc_arm_advance` returns 1 → the old close
owner writes the `no_work` terminal, which is the intended ownership.

## Execution evidence

- `tests/test-arm-advance-real.sh` → rc=0: "PASS: real dispatcher advanced to a second model
  without a premature terminal" (glm-flash → freepool; two `worker_spawned` rows, no
  `dispatch_terminal` between them).
- `tests/test-dispatch-silent-arm.sh` → rc=0, 12/12.
- `tests/test-close-chain.sh` → rc=0, 18/18.
- `tests/test-t13-slice1.sh` → rc=0, 19/19 (includes its own negative controls).
- `tests/test-glm-flash-arm.sh` → 18 pass / 3 fail. **Not caused by this diff**: with the diff
  reverse-applied into a scratch copy (`cp -R plugins/leadv2/scripts /tmp/basecheck/scripts`,
  then `patch -R -p1 < armfix.diff`) the same suite is 13 pass / 8 fail. The 3 residual failures
  are environment-caused — the fixture is refused before the assertion with
  `dispatch_refused reason=lead_session_lane_cap` and
  `project_root_guard status=foreign_env_overridden`.
- `tests/test-dispatch-product-close-exit-trap.sh` → 6 pass / 2 fail, **byte-identical failure on
  the reverted baseline** (Test (a) takes the `empty_diff`/`no_work` path and exits 5 instead of
  landing). Pre-existing, and on a different branch than the one this diff modifies. Its
  `bash -n` check on `leadv2-dispatch-product-close.sh` passes, so the edited file parses.
- Burn-gate hunk: the three newly parsed keys exist on the live governor line —
  `bash leadv2-burn-governor.sh verdict` →
  `verdict=soft burn24h=961919592 soft=800000000 hard=1300000000 glm_daily_pct=0 glm_soft_pct=15 glm_hard_pct=25 reason=over_soft`
  — and each `sed` extraction matches a single unambiguous occurrence.

## Nits (Low — do not block)

**L1. Deleted continuation-provenance journal line.** The diff removes
`emit decision "worker_spawned by=arm_advance model=... handle=..."` from the success path of
`cmd_advance_arm` and does not restore it. `spawn_worker` still journals
`worker_spawned by=router ...` (dispatch-code.sh:4930-4932) so no consumer breaks —
`grep -rn "by=arm_advance" plugins/ scripts/` returns nothing — but the continuation-vs-initial
distinction is no longer in the journal.

**L2. Successor chain narrowing (round-1 M1, partially still live).** `spawn_product_close` arg 4
changed from `""` to `$(IFS=,; printf '%s' "${candidate_arms[*]}")`. Correct in the normal case
(already-failed candidates sort before the winner, so `_pc_next_arm_in_chain` skips them). In the
degenerate fallback `candidate_arms=("${arm}")` the successor's chain has one element →
immediate `chain_exhausted`, where the old `""` fell back to the journal's full `candidate_chain`
row. Strictly narrower on that one path.

**L3. rc=0 with an empty handle now continues to the next arm.** This is the requested fix, but if
the launcher did start a worker and merely failed to print `handle=`, the walk spawns a second arm
alongside it. Bounded (one extra worker in the same lane worktree) and strictly better than the
previous behaviour of reporting success with an empty handle — recorded so it is a known
trade-off rather than a surprise.

DELIVERABLE_COMPLETE
