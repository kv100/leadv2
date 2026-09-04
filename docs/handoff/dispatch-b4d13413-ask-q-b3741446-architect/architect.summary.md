verdict: APPROVE
next_action: continue

DECISION_OPTION: a — lead deletes the stale index.lock.

- Lock is 0-byte with no live holder (lsof+ps), so removal loses nothing and git recreates it.
- Option b leaves the worktree broken for every later lane and the diff uncommitted.

Full: full.md
