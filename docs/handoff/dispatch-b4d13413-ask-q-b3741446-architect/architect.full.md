# Decision — stale index.lock in worktree BRAIN-CLASS-LIVE-01

## Question
A 0-byte `.git/worktrees/BRAIN-CLASS-LIVE-01/index.lock` (ts 03:25) blocks all write ops.
lsof+ps show no live holder — stale from an earlier crash. The Bash sandbox denies
`rm`/`mv` on sensitive `.git` paths, so the worker cannot clear it itself.

## Analysis
- Option b (report diff only) does not resolve anything: the lock stays, and *every*
  subsequent lane in this worktree — commit, checkout, merge-queue land — keeps failing.
  It converts one blocked task into an indefinitely broken worktree, and an uncommitted
  diff in a shared worktree is exactly the state a parallel session can silently revert.
- Option a is a one-shot, low-risk, lead-side unblock. Removing a stale 0-byte
  `index.lock` is safe: it carries no content, so nothing is lost; git recreates it on
  the next write. The only hazard is deleting a lock held by a *live* process, and that
  hazard is already excluded by the lsof+ps evidence in the question.
- Sandbox denial here is a guardrail against agents mutating `.git`, not a signal that
  the operation is wrong. The correct escalation path for a guarded-but-necessary op is
  exactly this: hand it to the lead/founder. That is what the guard is for.

## Verification the lead should do before `rm`
1. `lsof <path>` → empty, and `ps` shows no git process for this worktree (already done).
2. Confirm the file is 0 bytes and its mtime is older than any running lane.
3. `rm -f .git/worktrees/BRAIN-CLASS-LIVE-01/index.lock`, then `git status` to confirm
   write ops recover.

## Out of scope
Not deciding anything about the pending diff's content, the review gate, or whether the
worktree should be recreated. Only the unblock path.

DECISION_OPTION: a
RATIONALE: The lock is provably stale and 0-byte, so deleting it is safe and restores every write op in the worktree, while option b leaves the worktree permanently broken and the diff exposed to a parallel session.

DELIVERABLE_COMPLETE
