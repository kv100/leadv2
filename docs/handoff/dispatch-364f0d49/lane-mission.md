# M1 TEST — last mile. Test 1 passes. Test 2 needs `_lane_root` set so the branch can recompute.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.
File: `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh`, function
`run_product_close_reclassify_wire`. Nothing else may change. Product code is CORRECT — do not
touch `leadv2-dispatch-product-close.sh`.

## Where it stands — diagnosed by the lead, do not re-derive
Your emit-capture rewrite WORKED for direction 1: `writeset_drift_conflict` keeps its cause,
that assertion passes. Only direction 2 fails:

```
FAIL: M1 reclassify wire: Test 2 failed - reclassification did not fire for foreign_commit
```

Reason: entering the guard is necessary but not sufficient. The recompute is gated by inner
conditions, the first two being (at `leadv2-dispatch-product-close.sh:2407` and `:2415`):

```
if   [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && ! _pc_lane_root_is_own_worktree "${_lane_root}"; then
       _pc_cause="lane_root_not_a_worktree"      # <- this is a recompute you can trigger
elif [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && _pc_lane_dirty "${_lane_root}"; then
```

Your harness leaves `_lane_root` UNSET, so both are false, nothing recomputes, and the cause
stays `foreign_commit` — which your assertion correctly reports as "did not fire". The test
setup is incomplete, not the product code.

## Fix
For direction 2 only: set `_lane_root` to a real existing directory (create a temp dir) and keep
the stub `_pc_lane_root_is_own_worktree() { return 1; }` so the FIRST inner branch is taken.
Then assert the emitted line carries `cause=lane_root_not_a_worktree` — i.e. the cause was
recomputed, proving the branch still fires for a non-`partial_diff`, non-`writeset_drift_conflict`
reason.

Leave direction 1 exactly as it is now (it passes): `_lane_root` may stay unset there, since the
point is that the guard is never entered at all for `writeset_drift_conflict`.

## Proof — paste all of it
1. Full suite in the lane: the exact line `Results: PASS=7 FAIL=0`.
2. Negative control in a SCRATCH copy (never the lane): delete
   `&& "${blocked_reason}" != "writeset_drift_conflict"` from the guard at `:2393`, re-run —
   the M1 case must go RED (direction 1 now recomputes). Paste it.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite selected.
4. `git commit`, then `git status --porcelain` showing nothing modified under `plugins/`.

## Do not
Weaken an assertion to make it pass. Delete direction 2. Touch product code or the other 6 cases.
If it still resists, return `BLOCKED` with the exact command and output — an honest blocker beats
a green lie.

Return `PASS|FAIL|BLOCKED` + commit SHA + both runs (RED and GREEN) verbatim.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-364f0d49" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.