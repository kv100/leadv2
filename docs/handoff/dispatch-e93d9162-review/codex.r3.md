# Codex adversarial re-review — STOP-GATE r3

Reviewed worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e93d9162`  
Range: `53d4465...HEAD`  
Date: 2026-08-20

## Findings

### HIGH — timeout `review.diff` drops an untracked in-scope change

Both timeout branches capture with `git -C "${_pc_to_lane}" diff HEAD` (product-close.sh:1912–1917 and 1949–1954). Unlike `pc_scope_diff`'s `_pc_git_diff`, that raw command does not use a throwaway index with `git add -N`, so Git omits untracked files. The following checkpoint does commit the file via the stop gate, leaving the timeout handoff with an empty `review.diff` even though the checkpoint contains the worker's change.

I reproduced this with a real temporary lane: create an untracked declared `agent/new.py`, force the worker-timeout route, then inspect the artifacts. The close gate exited 5, created the STOP-GATE commit, and `review.diff` existed but had 0 bytes. Thus r2 finding 3 is not fully closed: the required pre-checkpoint handoff snapshot is absent for a normal class of new-file deliverables.

The raw capture is also unscoped: it includes every tracked dirty path in the lane, rather than only the declared write set. It must use a capture-only helper that preserves `pc_scope_diff`'s write-set/path resolution and untracked-file behavior without any verdict, journal, or ledger side effects. Add a timeout test with an untracked declared file (and preferably staged/foreign coverage).

### MEDIUM — cross-repository skip is still silent on the timeout paths

The r2 finding 4 is closed on the normal path: `pc_scope_diff` populates `PC_STOP_GATE_FOREIGN_REPOS`, and `pc_stop_gate_autocommit` journals `stop_gate_skipped_foreign_repo`. But neither timeout block calls `pc_scope_diff`. At that point the array is only declared/empty, so the stop gate does not emit the promised skip decision; the raw lane-only diff also cannot capture the foreign repository's change. This is a silent loss of the cross-repo diagnostic specifically on the worker-timeout route.

Resolve/group the declared paths in the capture-only helper (or independently populate the foreign-repo list) before invoking the stop gate, and assert the timeout route emits the journal record.

## Earlier findings status

1. **Pre-staged out-of-scope laundering — closed.** The checkpoint is constructed from `HEAD` in a temporary `GIT_INDEX_FILE` and commits only parsed in-scope paths. The real index is not committed; the new staged-junk test covers this case.
2. **Porcelain quoting/path parsing — closed.** Status is now read with `--porcelain=v1 -z`, including the second NUL record for renames/copies. The test covers a tab-containing rename.
3. **Timeout `review.diff` before checkpoint — partially closed, but still failing.** An artifact is now created before checkpointing for tracked changes, but the capture loses untracked in-scope files and is not scoped.
4. **Cross-repo write-set checkpoint protection — partially closed, but still failing on timeout.** The normal route journals a foreign-repo skip; the timeout route does not establish that state and remains silent.

## Capture-only regression checks

- **WORK_ROOT resolution:** uses the established `LEADV2_LANE_WORK_ROOT` first, then the same `path-of "${FOUNDER_TASK_ID:-${TASK}}"` fallback as `pc_scope_diff`; no resolution regression found.
- **HANDOFF existence:** `HANDOFF` is created before waiting, and both timeout blocks also `mkdir -p` defensively; no absence regression found.

`git diff --check 53d4465...HEAD` is clean. The supplied stop-gate suite's tracked timeout case is insufficient to expose the untracked artifact regression.

VERDICT: FAIL
