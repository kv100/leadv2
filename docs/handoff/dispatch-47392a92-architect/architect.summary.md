verdict: APPROVE
next_action: continue

Design: `.finalized` sentinel + dead run-dir `pgid` group ⇒ `dead:sentinel_finalized`, evaluated regardless of log freshness, placed after B8 so B8 stays byte-identical.

- Sentinels exist for glm/kimi only; codex + claude-subsession have none.
- Death proved via `<run_dir>/pgid`, not `active.yaml pid` (observed case had `pid: null`).
- 60s settle window closes the runner-retry race.

Full: architect.full.md
