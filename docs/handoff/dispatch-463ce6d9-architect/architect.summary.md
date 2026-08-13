verdict: APPROVE
next_action: continue

Split the anchor: LOGICAL_DIR → git-derived REPO_ROOT; physical readlink chain → PLUGIN_ROOT/TEST_DIR.

- Guard needs `|| true` (set -e) and `-e .git` (worktree lanes) or it blocks every lane.
- `.claude/` stale copy → **relative** symlink to canonical; `tests/run-all.sh` needs no change.
- Baseline is 33 registrations, not 32; probe flag cuts self-recursion.

Full: architect.full.md
