verdict: APPROVE
next_action: continue

DECISION_OPTION: a — extend the write-set, fix the pulse readers now.

- `dead_with_unlanded_work` exists nowhere yet: the in-scope ledger fix *creates* the mislabel — lane-class.py:146-149 rewrites the stale dead lane to `done`, broad-status.sh:545 misses it.
- Deferring degrades the pulse, does not preserve it.
- Both files are read-side, off the dispatcher path, not in off_limits.

Full: architect.full.md
