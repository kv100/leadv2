# Fix round 3 — GATE-FALSE-SILENT-01: "unknown base" is now too broad and broke C5

Repo: ~/Projects/leadv2. Continue in the EXISTING lane worktree
`.claude/worktrees/2d8a2849`. Do not restart; rounds 1-2 are sound apart from this.

## Round 2's own claim was wrong — verified by the lead, not asserted

Round 2's summary said all three `run-core-offline.sh` failures were pre-existing and
unrelated. The lead ran the third one on both trees:

```
main (6fa4823):        bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh  -> RC=0, 0 FAIL
lane (2d8a2849):       same command                                                     -> RC=1
                       FAIL: C5-registered-arm-silent   (Results: 4 passed, 1 failed)
```

It passes on main and fails in this lane, in `leadv2-dispatch-product-close.sh` — the
file this lane changes. **It is a regression this lane introduced.** The other two
(`deferred-GLM ladder (V3-GLM-LADDER-01)`, `fanout classifier/runner guard`) were
re-confirmed as genuinely pre-existing and are not yours.

## Why C5 broke — the two boundaries were merged into one

`case_c5_registered_arm_silent` (`tests/test-lane-diff-single-repo.sh:181-203`) builds a
FRESH repo + worktree via `new_repo`/`ensure_worktree`, writes an `arm-registered` file,
and runs the gate with no work of any kind. It expects
`terminal=no_work cause=arm_produced_nothing` — a genuinely silent arm.

In that fixture no base resolves (no `LEADV2_LANE_START_SHA`, no
`${CACHE_BASE}/dispatch-${TASK}.start-sha`, no `origin/main`), so round 2's
`_pc_lane_commits_ahead` returns `unknown`, the caller treats `unknown` as NOT silent,
and the expected verdict never fires.

Round 2's rule — "a probe that cannot resolve the base must not conclude silence" — is
right in spirit and too broad in practice: it collapses two different situations.

- **Provably zero:** the worktree's HEAD is identical to the commit it was created from
  (no commits of its own). This is C5. Silence is provable here WITHOUT resolving the
  configured base — no base lookup is needed to see that HEAD moved nowhere.
- **Genuinely unknown:** HEAD differs from every reference the probe can reach, so it
  cannot tell whether those commits are the lane's work or inherited history. Only THIS
  case may refuse to conclude silence.

## Do

Separate those two. Before falling back to `unknown`, prove-zero when you can:
compare the worktree's HEAD against the parent repository's HEAD / the worktree's
creation point (`git -C <wt> rev-parse HEAD` vs the main checkout's, or the worktree's
own reflog origin — pick what is robust in a bare fixture repo and say why in the
report). HEAD unmoved ⇒ commits_ahead is 0, not unknown ⇒ the existing silent path runs
unchanged. Keep round 2's `silent_probe_base_unresolved` journal line for the genuinely
unknown case only.

## Off-limits
- Do not edit `test-lane-diff-single-repo.sh` to make C5 pass. C5 is correct; the
  product is wrong. Changing that test is the failure mode this round exists to prevent.
- Do not weaken Case E in `test-silent-arm-commits-ahead.sh` (unresolvable base must
  still not be called silent when it is genuinely unknown). Both must be green together.
- Do not touch `pc_scope_diff`, the e2e gate, or main's unrelated dirty files.

## Verify (real pasted output, FOREGROUND, with a timeout)
1. `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` — all 5 cases,
   C5 green.
2. `bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` — all cases,
   Case E still green.
3. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — all cases.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Exactly
   TWO failures must remain (`deferred-GLM ladder`, `fanout classifier/runner guard`).
   If a third appears, it is yours: name it and fix it.

## Deliverable
`docs/handoff/GATE-FALSE-SILENT-01/report.md` — how you separated provably-zero from
unknown with file:line, the four verifications with pasted output, `git diff --stat`.
State plainly whether each remaining failure was verified against main by you.
End with DELIVERABLE_COMPLETE.
