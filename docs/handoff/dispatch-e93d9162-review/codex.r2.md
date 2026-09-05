# Codex adversarial review — STOP-GATE r2

Reviewed worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e93d9162`  
Range: `53d4465...HEAD -- plugins/`  
Date: 2026-08-20

## Findings

### HIGH — checkpoint commit launders an already-staged out-of-scope change

`pc_stop_gate_autocommit` limits only its *new* `git add` invocation to `_sg_files`
(product-close.sh:1447), then calls a normal `git commit` (line 1454).  A normal commit
includes every entry already in the real index.  Therefore an out-of-write-set file staged by a
worker (or left staged in the worktree) is committed along with the intended checkpoint.  This
contradicts the nearby promise that junk is “deliberately left alone”, and is worse than merely
leaving junk dirty: the scoped `review.diff` does not contain the laundered file, so review can
approve a snapshot that does not describe the checkpoint commit.

Reproduced end-to-end with the real close script and a real lane worktree:

1. Commit `agent/in.py` and `other/out.py`; modify both in the lane.
2. Stage only `other/out.py` before invoking product-close with
   `LEADV2_DISPATCH_LANE_WRITES=agent/in.py` and e2e/review disabled.
3. The close exited `0`; the new STOP-GATE commit contained both
   `agent/in.py,other/out.py`, the worktree was clean, and `review.diff` had no
   `other/out.py` entry.

The existing out-of-scope test uses an **untracked** junk file, so it cannot detect this index
case.  Before committing, inspect the complete staged name set and refuse/checkpoint-fail if any
path lies outside the concrete allowed set (including correct rename handling); or create the
checkpoint from an isolated index whose contents are explicitly constrained to the approved
paths.  Do not commit through the inherited real index unconditionally.

### HIGH — ordinary porcelain quoting is not parsed into file names

The implementation asks for line-oriented, non-`-z` porcelain (line 1415) and attempts to
unquote by removing only the first and last quote (lines 1438–1441).  Git uses C-style quoting
there, so that is not an unescape operation.  For example, a real status record is:

```
 M "agent/a\\tb.txt"
```

The parser yields the literal path `agent/a\\tb.txt`, not a filename containing a tab.  `git add`
then fails, `stop_gate_autocommit_failed reason=add_failed` is emitted, and the function returns
success with the in-scope work uncommitted.  The same applies to newline, quote, backslash, and
normally quoted non-ASCII names.  The ` -> ` rename branch is only safe for simple names; it
also relies on this incomplete unquoting for quoted old/new names.

Use `git status --porcelain=v1 -z` and consume NUL-delimited records (skipping the second,
source-path record for rename/copy) rather than parsing display-oriented quoting.  Add red/green
coverage for a tab or newline filename and for a quoted rename.  The current rename test uses
spaces only and the staged `git mv` state, so it does not exercise escaped bytes or an unstaged
rename.

### MEDIUM — timeout checkpoint paths advance HEAD without first preserving `review.diff`

The normal exit route does the right thing: `pc_scope_diff` at line 1894 writes the exit-time
snapshot before `pc_stop_gate_autocommit` at line 1900.  Both timeout routes instead reap and
checkpoint at lines 1833–1843 and 1858–1869, then immediately exit `5`; neither creates
`review.diff`.  A timed-out worker is specifically one of the paths this gate is intended to
save, but its partial diff has no handoff snapshot.  The checkpoint is recoverable from Git, but
the review artifact and its base/evidence are absent, making the timeout outcome materially less
auditable and violating the stated capture-before-checkpoint ordering on those routes.

Either capture a scoped snapshot before the timeout checkpoint (without proceeding to e2e/review)
or explicitly write a separate equivalent checkpoint-diff artifact.  Extend Case F to assert the
artifact contains the pre-checkpoint change, not just that `HEAD` advanced.

### MEDIUM — the gate does not checkpoint work discovered in cross-repository write sets

`pc_scope_diff` can resolve each declared write through symlinks into another repository and
assemble a cross-repo `review.diff`.  `pc_stop_gate_autocommit`, however, always runs
`git status`, `git add`, and `git commit` only in `_sg_lane_root` (lines 1403–1454).  A target
behind a tracked symlink leaves the symlink blob clean in the lane worktree; the status query is
empty and the gate returns without checkpointing the actual modified repository.  This leaves an
established `CROSS_REPO_DIFF=1` lane outside the claimed commit-before-exit protection.

If cross-repo lanes are supported downstream, group concrete dirty paths by their owning Git
repository using the same resolution as `pc_scope_diff`, and checkpoint each group safely.  If
they are intentionally unsupported by STOP-GATE, block loudly rather than silently declaring a
successful no-op.

## Confirmed good

- On the normal, non-terminal route, `review.diff` is captured before the checkpoint, so later
  selfcheck/e2e/review consume the exit-time snapshot while their tree sees the checkpoint.
- The missing-declared-path and timeout-reap holes from the prior revision are addressed in the
  current diff.
- `LEADV2_STOP_GATE=0` is an immediate no-op in product-close, and the dispatch mission paragraph
  is under the same exact guard after the dedup signature is computed.  I found no healthy-path
  exit-code leak from the disabled gate itself.
- `bash -n` / `/bin/bash -n` are clean, and `git diff --check` reports no whitespace errors.

## Verification notes

`test-no-work-terminal.sh` printed all of its assertions as PASS in the isolated run, including
the non-empty natural-completion route and timeout terminal assertions.  The new stop-gate suite
covers missing declared paths and timeout checkpointing, but it has no pre-staged-junk,
quoted-path, cross-repo, or timeout-`review.diff` assertion.

VERDICT: FAIL
