# D2-M4 (5th real conversion) — lib/leadv2-worktree-protected.sh

## Change

The `active.yaml` session-scan's `pid_alive` computation caught bare
`except (TypeError, ValueError, OSError)` — `PermissionError` subclasses
`OSError`, collapsing EPERM (pid exists, owned by another user, e.g.
reparented to ppid=1) into the same "dead" branch as ESRCH
(D2 brief #9/#14). Split: `ProcessLookupError` → 0 (dead, unchanged),
`PermissionError` → 1 (alive, new), other `(TypeError, ValueError, OSError)`
→ 0 (unchanged, malformed pid data).

## Measured before writing a full test (per Leadmain's methodology)

This file's header describes exactly the incident class this bug-class
targets (a sweeper deleting a live lane's worktree). But tracing the call
graph: `lv2_worktree_protected()` calls `_lv2_wt_session_row(id, wt)`
FIRST, which returns `rc 1` (protected) on ANY row with
`tid == id || tid == "dispatch-$id" || wpath == wt`. Only if that returns
"no match" does it fall through to `_lv2_wt_pid_alive(id)` (the only
consumer of the `alive` column this fix touches), which matches on
`tid == id || tid == "dispatch-$id"` — a strict subset of the first
function's condition. Any row that would make `_lv2_wt_pid_alive` report
"alive" already made `_lv2_wt_session_row` report "protected" via `rc 1`
first. **`rc 3` (`live_pid`) is therefore provably unreachable for the same
`id`** — the file's own comment ("in practice rc 3 only refines rc 1") is
slightly optimistic; it does not refine, it never independently fires.

Conclusion: the bug is real and the fix is correct, but the sweeper-facing
protection decision in production does **not** currently depend on it —
it is already fully covered by `rc 1` regardless of pid liveness. Fixed
anyway (matches the file's own documented TSV contract:
`S \t task_id \t worktree \t pid \t pid_alive(0|1)` — a wrong value in that
column is a real correctness defect even if no current caller branches on
it), and scoped the test to the column itself rather than pretending `rc 3`
fires.

## New test

`test-worktree-protected-pid-alive.sh`: calls `lv2_wt_protect_prime`
against a fixture `active.yaml` (resolved via `leadv2-state-path.sh`, NOT
`<root>/docs/leadv2/active.yaml` directly — that path guess was wrong on
the first attempt; the real control-plane file lives in the shared
`~/.claude/leadv2-state/` tree) and reads the `alive` column directly.
C1: pid=1 (EPERM) → alive=1. C2: pid=999999 (ESRCH) → alive=0. 2/2 pass.

## Mandatory negative control (mutation-control-proven)

Mutated line 112 (`except PermissionError: alive = 1` → `alive = 0`,
reverting to the pre-fix collapse). Suite goes RED exactly on C1:
`FAIL: C1: expected alive=1, got '0'`. GREEN on the committed code.

## Commit

`c97c3f41` (fix+test), this report + artifact next.
