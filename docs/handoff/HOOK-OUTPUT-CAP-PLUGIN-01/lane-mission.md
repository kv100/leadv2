# HOOK-OUTPUT-CAP-PLUGIN-01 — cut the per-session-start hook tax at its real source

WORKTREE PIN: all edits go in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-one-copy-drift.sh,plugins/leadv2/hooks/leadv2-truth-card-inject.sh,plugins/leadv2/scripts/tests/test-hook-output-cap.sh,tests/run-all.sh,docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/

## Why this lane exists

Every ordinary session start in every repo pays a large hook-output bill. That output is not paid
once: it is appended to the conversation and re-sent on every later turn, so it is a standing
per-turn tax on the founder's real spend.

A sibling lane (`HOOK-OUTPUT-BUDGET-UNMANAGED-01`, in `persona-engine`) spent three rounds capping
hooks and moved the number by **zero bytes**. The reason is now established: it was capping the
wrong repo's hooks. Measured in the main checkout, session-start output is **62,404 B**, and the
two hooks that produce almost all of it are **plugin-owned and live here**:

- `plugins/leadv2/hooks/leadv2-one-copy-drift.sh` — **46,257 B** of output, registered under plain
  `SessionStart` at `plugins/leadv2/hooks/hooks.json:68` (and `PostToolUse:Bash` at `:497`).
- `plugins/leadv2/hooks/leadv2-truth-card-inject.sh` — **7,758 B**, registered at `hooks.json:16`.
  A sibling lane recorded this one as 146 B; that measurement was taken in a worktree and is wrong.

Everything the persona-engine lane capped is 2-4x *below* its own 2048 B trigger, so none of those
caps ever fires.

## The work

1. **Cap `leadv2-one-copy-drift.sh` at source.** Its output is a long list of `REGRESSION:` lines,
   one per drifted file. A session start needs the *fact* and the *count*, not the list. Emit a
   short summary — how many regressions, and the path to a file holding the full list — and keep
   the full detail on disk for anyone who wants it. Target: well under 2 KB in the common case.
2. **Cap `leadv2-truth-card-inject.sh` the same way**, on the same principle: what a session needs
   at start, with the rest behind a path.
3. **Both caps must apply to the SessionStart path the harness actually takes.** A cap that only
   fires in a branch the harness never reaches is the defect this lane exists to correct. Prove
   each by invoking the hook the way the harness does and pasting the byte count before and after.
4. **Measure in the MAIN checkout, never in a worktree.** The wrong-by-7.6 KB figure above came
   from measuring in a worktree. State where each measurement was taken.
5. **Report the total.** `report.md`'s first line must say what an ordinary session start costs in
   bytes after this lane, measured, versus the 62,404 B before.

## Hard constraints

- **Do not reorder, add, or remove entries in `hooks.json`.** The array's tail contains
  `scheduled-decisions-inject.sh`, which is the deferred-actions guarantee named in CLAUDE.md;
  reordering evicts it. Cap inside each hook script instead. `hooks.json` is not in LANE_WRITES.
- **Do not trim or alter `scheduled-decisions-inject.sh`.**
- **Do not "fix" the drift the drift-hook reports** by editing `~/.claude/leadv2-shared/` or any
  other shared tree. Silencing the report is out of scope and forbidden; capping the *output* is
  the task.
- A capped hook must still be loud when it matters: if there are regressions, the summary says so.
  Never make the hook silent about a real problem to make a byte count look good.

## Controls — the part that decides whether this round counts

- One control per cap: apply a mutation **inside the function body of the production hook** that
  removes the cap, run the suite, show RED; revert, show GREEN. A `sed` that matches zero lines is
  a hard failure, not a skip.
- No `grep` against script source as an assertion. No negated command as an assertion — `set -e`
  never trips on it. No mutation of a scratch copy. No `git show HEAD:` pre-image.
- Every artifact must assert its own outcome. A file in `red/` recording a passing run under a RED
  header is a hard failure of the round; that shipped twice today.
- `--scope changed` must select the new suite for this write set. Prove it.
- Bash 3.2.57 only: no `read -N`, no bash-4 array idioms, and every `${arr[@]}` guarded under
  `set -u` — an unbound array under `set -u` is fatal and shipped in another lane today.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

An ordinary session start measured in the main checkout, before and after, with the two hooks each
shown capped on the path the harness takes; a suite that goes RED when either cap is removed;
`red/` holding a matching RED/GREEN pair per cap; `--scope changed` selecting it; and `report.md`
opening with the measured before/after byte total.
