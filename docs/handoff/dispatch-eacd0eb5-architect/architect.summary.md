verdict: REVISE
next_action: continue

Straight delete is unsafe: `leadv2-supervise.sh --json` is the live lanes source for founder-status.md (status-collector.sh:112) and the only active.yaml prune writer.

- Migrate via `git mv` → `leadv2-lanes-snapshot.sh` (commit 1), retarget supervisor-role.md hook pointers (commit 2), then delete (commit 3).
- Suite count drops 56→54, not by 1; 6 suites need repair, not deletion.
- 6 hooks + 6 hooks.json rows + plugin-sync curated set must move together.

Full: architect.full.md
