verdict: APPROVE
next_action: continue

# architect.summary — FORK-RUNS-FULL-SESSION-01

Only two things genuinely block a fork from running Phase 0→8; the rest already works.

- **Blockers:** Gate 1 has no async branch (5s silent auto-accept, or infinite hang on Heavy);
  registry liveness is pid-keyed and a fork has no pid of its own.
- **Not blockers:** the lock is per-task, not global; ExitWorktree is convention. Worktree entry
  in a fork is the one unknown — probe first.
- **Scope:** Standard-class, plugin-repo, file-artifact live signal. Heavy excluded.

Full: architect.full.md
