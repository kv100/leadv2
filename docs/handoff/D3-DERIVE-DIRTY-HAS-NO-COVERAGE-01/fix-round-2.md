# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — fix round 2: C8's fixture does not check its own setup

LANE_WRITES: plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh, docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01/

C8 is accepted in substance — commits `b6d1ecbd` and `96cbf1f5`. The lead re-ran your mutation
control independently and it bites: `baseline_rc=0`, `mutated_rc=1`, red line
`[TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown`.
Do not redo any of that. One defect remains, and it is in the fixture, not in the product.

## What happened

On one run out of four, while three lanes were spawning on this machine, the suite came back
**20 passed, 1 failed**:

```
[TEST] FAIL: C8b: expected landed with sha ad57f180cd272363b2f42d81e39de850faaa3152, got: deadnoneunknown
```

Three consecutive re-runs on a quiet machine gave 21/0. So it is load-sensitive, not a product bug.

The mechanism: C8b's setup is

```
( cd "${wt}" && printf 'a\n' > work.txt && git add work.txt && git commit -qm "lane work" >/dev/null )
sha="$(git -C "${wt}" rev-parse HEAD)"
```

That subshell's exit status is discarded. When `git commit` fails, `rev-parse HEAD` quietly returns
the **seed** commit instead, `_dl_derive_lane_state` correctly finds no path-scoped commit for
`work.txt`, and the assertion reports a product failure that never happened. The reported sha in the
red line above is the seed commit, which is the tell.

This is the same disease as everything else this lane exists for: **a setup step that missed its
target reported success.** A fixture whose own construction can silently fail produces a red that
looks like a defect and, worse, could produce a green that looks like proof.

## The fix

Give C8a and C8b an explicit setup assertion, in the style of the `NC-SETUP-FAIL` guard used by the
negative-control scripts: after constructing the fixture, verify the construction and abort loudly
as a **setup error** — distinct wording from an assertion failure — if it did not hold.

- **C8b** — assert the subshell succeeded AND that `git -C "${wt}" log -n1 --pretty=%H -- work.txt`
  is non-empty, i.e. the path-scoped commit the case is about actually exists, before calling
  `_derive`. Take `sha` from that same path-scoped lookup rather than from bare `HEAD`, so the
  expected value and the thing under test cannot disagree about which commit is meant.
- **C8a** — assert the uncommitted file exists and that `git status --porcelain` in the lane
  worktree is non-empty before deriving. A silently-failed `printf` would otherwise make C8a pass
  for the wrong reason, which is worse than the red.

Audit the other cases in this file while you are in it: any fixture whose construction runs inside
`( … )` with the status discarded has the same hole. Fix the ones that do, and say in your report
which ones you checked and found sound — a list of names, not prose.

## Then re-prove, do not assert

1. Run the suite five times in a row and paste all five count lines. Five, not one — the defect
   this round fixes appeared once in four.
2. Re-run the same mutation control and paste the pair again, to prove the setup guards did not
   accidentally neuter C8a:

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh \
  plugins/leadv2/scripts/leadv2-dispatch-ledger.sh \
  's/"\${commit_sha}" != "none" \]\]; then/"${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then/' \
  docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01
```

3. Add one more control proving the **setup guard itself** bites: mutate the fixture so the C8b
   commit step cannot succeed, and show the suite reports a **setup error**, not a C8b assertion
   failure. If a guard cannot tell those two apart it has not been added.

## Constraints

- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh` — this lane adds coverage for it.
- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session.
- No assertion is weakened; nothing goes into `tests/known-red-suites.txt`.
- Do NOT touch `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*`.
- Commit the moment the five runs are green, before the controls.

## Report

Five suite count lines, the two control pairs, the names of the fixtures you audited, and the
commit shas. Nothing else.
