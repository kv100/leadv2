# Decision — duplicate executor in BEAT-LOOP-ORPHANS-01

DECISION_OPTION: a
RATIONALE: The 22:17 GLM run is the duplicate/orphan in an already-assigned lane — the lane session keeps ownership; terminate the orphan, then reconcile at commit.

## Why (a), not (b)

1. **Ownership is assignment-based, not arrival-based.** The lane BEAT-LOOP-ORPHANS-01 was assigned to the asking session; the beat loop spawning `glm-coder 260901-221700-BEAT-LOOP-ORPHANS-01-4e23` into the same worktree mid-build is exactly the orphan-class defect this lane exists to fix. Granting ownership to the duplicate (option b) rewards the bug and strands a legitimate mid-build session on the mere hope that the orphan happens to complete the same mission correctly.
2. **Option (b) has unbounded risk.** The orphan's mission fidelity is unknown; letting it own the lane means the lane's acceptance now depends on an unreviewed process nobody supervises.
3. **Option (a) has bounded, known mitigations** (below), all already established practice in this repo.

## Hard condition on option (a): stop the writer first

"Reconcile at commit" as stated is unsafe while the GLM run is **actively writing**. Two concurrent filesystem writers in one worktree produce lost updates, not git conflicts — whichever side writes last silently clobbers the other, and the clobbered side's Edit-buffer state is stale. Reconciliation at commit can only see the surviving bytes.

Therefore option (a) is taken **with this mandatory precondition**:

- **Lead terminates the GLM run (pid tree rooted at 16994) before the lane session resumes editing.** This is a lead action, not the architect's.

## Commit protocol (existing rules, restated for this lane)

1. After pid 16994 is dead, the lane session re-Reads every file the GLM run touched before further Edits (stale-buffer Edit calls will otherwise fail or double-apply).
2. `git diff <file>` immediately before each `git add` — never earlier (parallel-writer revert hazard).
3. Pathspec-commit ONLY the lane's own files (`hooks/leadv2-single-lead-beat.sh`, the 4 launchers, `hooks/lib/`, `scripts/tests/test-beat-loop-orphans.sh` per mission scope). Never `git add -A` in a dirty shared worktree.
4. GLM run's already-landed bytes are treated as prior art: diff-reviewed like any contributor input — adopted where correct, reverted where it contradicts the lane's context.yaml decisions. Nothing is trusted because it happens to be on disk.

## Risks

| Risk | Mitigation |
|---|---|
| GLM pid tree survives the kill (child re-parents) | Lead verifies pid 16994 gone via `ps -p 16994` before signalling the lane to resume |
| GLM run wrote half-finished bytes into launchers | Re-read + test suite (`test-beat-loop-orphans.sh`) before resuming; treat suite red as suspect until re-verified against committed blobs, not on-disk bytes |
| Lane session's unsaved edits already clobbered | Loss is accepted and re-derived from the session's own record — cheaper than standing down an owned lane |

## LEAD_ACTION

Terminate pid tree 16994 (GLM run 260901-221700-BEAT-LOOP-ORPHANS-01-4e23) and confirm termination to the lane session before it resumes editing. Also record the beat-loop duplicate-dispatch as the defect evidence this lane was built to eliminate.

DELIVERABLE_COMPLETE
