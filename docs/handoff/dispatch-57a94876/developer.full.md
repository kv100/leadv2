# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — verification pass

C8a/C8b coverage for `_dl_derive_lane_state` in
`plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh` was already implemented and
committed by a prior session on this same lane (commits `b6d1ecbd`, `484dd7a2`). No source or
test edits were made this session — `leadv2-dispatch-ledger.sh` remains untouched
(`git diff --stat` empty) per the constraint. This session re-ran the acceptance bar end to end
and confirms it holds.

## Suite run (standalone)

```
[TEST] PASS: C8a: derive(dirty tree, no path-scoped commit, dead) -> dead_with_unlanded_work, never landed
[TEST] PASS: C8b: derive(real path-scoped commit) -> landed with that exact sha

[TEST] 21 passed, 0 failed
```

## Mutation control

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh \
  plugins/leadv2/scripts/leadv2-dispatch-ledger.sh \
  's/"\${commit_sha}" != "none" \]\]; then/"${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then/' \
  docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01
```

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh file=plugins/leadv2/scripts/leadv2-dispatch-ledger.sh red_line=[TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown diff_hash=a481a28718596346fea5d1cafe951465d67f22ecb605fba2a7b0ca29e5d6aae6 lane_diff_hash=88b5e4ae362ead29409d9cfb9a46f47a2226de2139abd9f61c01046c62c1d4b2
EXIT=0
```

- `baseline_rc=0`, `mutated_rc=1` (implied by `MUTATION-CONTROL ok` — the tool itself exits 1 for
  `mutant_survived` and 2 for a control that never applied; here it printed `ok` with exit 0).
- Red line: `[TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown`

## Self-checks

```
bash -n plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
BASH_N_OK
```

`git diff --stat -- plugins/leadv2/scripts/leadv2-dispatch-ledger.sh` — empty (file untouched, as
required). `git status --short` on the test file and this handoff dir — clean (already committed
upstream on this branch).

## Commit shas

- `b6d1ecbd` — test(D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01): C8 derives `_dl_derive_lane_state`
  directly
- `484dd7a2` — test(D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01): fix round 2 — fixtures verify their own
  construction
- `c60cf2f8` — proof(D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01): fix round 2 controls, same mutation
  control result reproduced independently this session

## Left alone

- `leadv2-dispatch-ledger.sh` — not touched, per constraint.
- No changes to `docs/leadv2/*`, `LEAD_V2_STATE.md`, or `dispatch-nw*` handoffs were made by this
  session (those paths show as modified in `git status` from concurrent sessions/lead activity,
  not from this task).

DELIVERABLE_COMPLETE
