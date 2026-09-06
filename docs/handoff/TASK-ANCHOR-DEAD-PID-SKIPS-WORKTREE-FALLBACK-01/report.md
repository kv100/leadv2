# TASK-ANCHOR-DEAD-PID-SKIPS-WORKTREE-FALLBACK-01

Found while auditing D2-M4's original 18-file EPERM/ESRCH list
(`hooks/leadv2-task-anchor.sh` was the last file checked in that sweep).
Filed as its own row per Leadmain's direction, since the divergence is
NOT the D2 bug (EPERM was already handled correctly here) — it is code
diverging from its own comment on the DEAD branch, a distinct defect.

## Change

`main()`'s `active.yaml` scan (around line 764) decides "should this
session row be excluded from worktree-fallback matching" for any row
whose pid is not one of this process's own ancestors. Both branches of
the `os.kill(session_pid, 0)` try/except used to end in `continue`
(exclude) — the `try` body (pid alive) AND
`except (ProcessLookupError, PermissionError)` (pid dead OR foreign-owned)
alike — even though the comment immediately above says the intent is to
exclude only "A valid PID belonging to a different **live** process tree
... Never select it by worktree fallback." A genuinely dead pid (ESRCH)
is not a live foreign session at all; its row should fall through to
worktree matching, the same as any pid-less row, but never did.

Split: `PermissionError` (pid exists, foreign-owned, alive) still
`continue`s — unchanged, matches the comment's intent. `ProcessLookupError`
(genuinely gone) now `pass`es through to the worktree-match check below.

## New test

`test-task-anchor-dead-pid-worktree-fallback.sh`:
- **C1**: a session row with a genuinely dead pid (`ESRCH`, a found-unused
  high pid) and `worktree == cwd` must still be selected as the active
  task via worktree fallback (`ACTIVE TASK: ANCHOR-C1-DEAD-PID` in
  output).
- **C2 (regression sanity)**: a session row with a real, ALIVE pid that is
  not this test process's ancestor (a genuine background `sleep 30`) and
  `worktree == cwd` must still be EXCLUDED — the original intent (never
  select a live foreign session by worktree fallback) is unaffected by
  the fix.

2/2 pass on the first real run.

## Mandatory negative control (mutation-control-proven)

Mutated the `ProcessLookupError` branch back to `continue` (the pre-fix
behavior). Suite goes RED exactly on C1: output is empty (no `ACTIVE
TASK:` line at all — the hook fell through to its silent "no active task"
default, exactly the incident this fix targets). GREEN on the committed
code.

## Commit

`5318e02e` (fix+test), this report + artifact next.
