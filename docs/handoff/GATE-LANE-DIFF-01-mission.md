# GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01 — the close gate discards a lane's work when CROSS_REPO_DIFF is off

**Repo to change: `~/Projects/leadv2` (the plugin), NOT persona-engine.** This mission file lives
in persona-engine only because that is where the lead dispatches from.

## The defect (live, cost a complete P0 fix today)

`~/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:861-868`:

```bash
diff_root="${ROOT}"
if [[ "${CROSS_REPO_DIFF}" == "1" ]]; then
  _lane_root="${LEADV2_LANE_WORK_ROOT:-}"
  ...
  [[ -n "${_lane_root}" && -d "${_lane_root}" ]] && diff_root="${_lane_root}"
fi
```

The lane worktree is consulted **only** when `CROSS_REPO_DIFF=1`. On a single-repo dispatch
`diff_root` stays the main checkout — where the lane worker's uncommitted work does not exist —
so `_pc_repo_diff` (:933) returns zero bytes and the gate concludes:

```
review_gate  status=blocked reason=no_work
dispatch_terminal  terminal=no_work cause=empty_diff
```

Observed on persona-engine task `0db1da80` (2026-08-04): the worker had produced a complete,
correct, fully-tested 221-insertion fix plus a new 193-line test file, sitting uncommitted in
`.claude/worktrees/0db1da80`. `review.diff` was 0 bytes and `review.diff.repos` read
`persona-engine 0`. The lead only rescued it by reading the worktree by hand; a lead that trusted
the gate would have thrown the work away and re-dispatched from scratch.

This is NOT a stale checkout: plugin `main` is at `1527b50`, equal to `origin/main`.

## Required fix

1. Resolve the lane worktree for the task **whenever one exists**, independent of
   `CROSS_REPO_DIFF`. The comment block above line 855 already argues that `diff_root` must never
   disagree with where the code landed — the code contradicts its own comment.
2. **`no_work` must not be terminal while a lane worktree is dirty.** Before concluding
   `empty_diff`, check the resolved lane root for uncommitted tracked changes AND untracked
   files; if either exists, this is a diff-scoping failure, not an absent-work outcome, and must
   be surfaced as its own distinguishable reason rather than silently retired as `no_work`.
3. Keep `partial_diff` / `asked_into_void` semantics exactly as they are.

## Rules — shared tree, be careful

- The plugin repo's scripts are symlinked into persona-engine, m3-market and respiro-ios. A
  regression here breaks dispatch in all three.
- Work on a branch in `~/Projects/leadv2`. **No commit to main, no push, no merge — the lead does
  that.**
- Do not touch `~/.claude/leadv2-shared/` or any project's `.claude/leadv2/`.
- Do not loosen or bypass any other gate to make a test pass.

## Done means

- A test proving that a single-repo dispatch (`CROSS_REPO_DIFF` unset or 0) whose lane worktree
  holds uncommitted work produces a NON-empty diff and does not terminate as `no_work`.
- A test proving that a genuinely empty lane still terminates as `no_work` — the fix must not
  turn "the worker did nothing" into a pass.
- Existing product-close tests still green; paste the full output.
- `bash -n` clean on every file touched.

## Attempt 2 note (lead, 2026-08-04T09:5xZ)

Attempt 1 was routed to codex while codex was under an unexpired quota lockout
(`~/.claude/cache/codex-lockout.state`), so it produced an empty worktree and the lane was
retired as a regression it could not have caused. This attempt runs on sonnet.

Be aware while testing: `plugins/leadv2/scripts/tests/run-core-offline.sh` sub-suite "review body
persist" ALREADY fails when run from inside a lane worktree, with exactly the symptom this
mission fixes (`review_diff repo=<lane sig8> bytes=0 base=HEAD` on its temp-repo fixtures). Do
not "fix" that by weakening the fixtures — it is the same defect observed from the harness side,
and a correct fix should make those four fixture cases pass on their own.

## Attempt 3 note (lead)

Attempt 2 could not spawn at all: this repo had no `developer` agent role, so the sonnet arm
died with `role file not found`. The role now exists (repo-local `.claude/agents/developer.md`).
Nothing about the required fix has changed.
