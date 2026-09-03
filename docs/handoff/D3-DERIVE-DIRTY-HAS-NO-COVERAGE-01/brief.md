# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — the derive half of the D3 diff has zero coverage

LANE_WRITES: plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh, docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01/

## The gap — measured by the lead, do not re-derive it

Work in the lane worktree `.claude/worktrees/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF` (branch
`worktree-D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF`, head `962bcaaf`).

That lane's diff changes **two** things in `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`:

1. `_dl_reap_one_lane` — the reap funnel. Covered by
   `plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh` (19/19 green), and two
   independent negative controls bite it.
2. `_dl_derive_lane_state` (~line 906-1000) — the fix that a DIRTY-but-uncommitted tree must not
   be stamped `landed`, but must fall through to liveness and come back
   `dead_with_unlanded_work`. **This half has zero coverage.**

Proof of the gap, run 2026-09-04. This sed applied to a scratch copy restores the exact original
defect:

```
s/"\${commit_sha}" != "none" \]\]; then/"${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then/
```

The suite stayed **19 passed, 0 failed** (`leadv2-mutation-control.sh` exit 1 = `mutant_survived`).
`grep -rn '_dl_derive_lane_state' plugins/leadv2/scripts/tests/` returns nothing across the whole
test tree.

The original incident this fix exists for: 573 uncommitted lines in a SIGKILLed lane were stamped
`landed` and the worktree was one sweep from deletion. Shipping the fix with no assertion behind it
means the next regression restores the incident silently.

## Task

Append case **C8** to `plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh`, exercising
`_dl_derive_lane_state` directly (it is documented as usable standalone — see the comment near
line 976). Two assertions minimum:

- **C8a** — no path-scoped commit, DIRTY working tree, liveness dead => derives
  `dead_with_unlanded_work`, never `landed`. This is the assertion the mutation above must break.
- **C8b** — the mirror: a real path-scoped commit still derives `landed`. Without it, C8a could be
  satisfied by a function that never returns `landed` at all — formally correct, operationally
  catastrophic.

Match the file's existing fixture style: same helpers, same `pass`/`fail` calls, same temp-repo
construction. Append only — do not restructure, renumber, or reorder existing cases.

## The deliverable is the control, not the test

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh \
  plugins/leadv2/scripts/leadv2-dispatch-ledger.sh \
  's/"\${commit_sha}" != "none" \]\]; then/"${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then/' \
  docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01
```

Exit 0 (`baseline_rc=0`, `mutated_rc=1`) is the bar. Exit 1 = the mutant survived: C8 does not bite
and you are not done. Exit 2 = the control never applied: fix the anchor, never paper over it.
A `diff_hash` alone is not proof that anything ran — paste the literal red suite line.

Run the suite standalone before and after and paste both counts with both exit codes.

## Constraints

- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session.
- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh` — this lane adds coverage for it,
  it does not change it. If C8 cannot pass without changing the function, stop and say so.
- No assertion is weakened; nothing goes into `tests/known-red-suites.txt`.
- Do NOT touch `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` — concurrent
  session state, not yours.
- Commit the suite file the moment C8 is green, BEFORE running the mutation control. Force-add the
  artifact (`git add -f`) — `docs/handoff/*/*` is gitignored at `.gitignore:49`, and that gitignore
  is exactly how a finished worker's report was mistaken for a death last night.

## Report

Two suite counts, the mutation-control exit code with its `baseline_rc`/`mutated_rc` pair, the
literal red line, and the commit shas. Nothing else.
