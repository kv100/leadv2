verdict: REVISE
next_action: continue

Test design is mechanism-closed; two mission premises are false on the tree.

- `.claude/worktrees/f72c8c9c` is not a registered worktree — round 1 landed on the main checkout (already on `lane/dispatch-f72c8c9c`); the scaffold holds a stale 162-line trace lib. Build there, not in it.
- Defect A: 4 of 9 seams define no `SCRIPT_DIR`, so the sink never resolves — `provider.*`/`status.collect` can never emit.
- Defect B: a clock failure in the EXIT drain loop hangs the host script forever.

Full: architect.full.md
