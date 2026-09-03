# HOOK-OUTPUT-CAP-PLUGIN-01 — round 2: the cap works, but it now swallows real errors

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-one-copy-drift.sh,plugins/leadv2/hooks/leadv2-truth-card-inject.sh,plugins/leadv2/scripts/tests/test-hook-output-cap.sh,tests/run-all.sh,docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/

HEAD is `e121b56`. The reviewer could not write a verdict file into this worktree (the lead session's
scope guard blocked it), so the full findings are reproduced below.

**Confirmed by independent reproduction — keep all of it.** The headline is real: the drift hook
goes **45,705 B → 277 B**, the cap sits on the path the harness actually takes, `hooks.json` is
untouched, both controls go RED→GREEN against the production function bodies, artifacts are present
(gitignored, not missing), and the write set is bash-3.2 clean. The reviewer also measured
`leadv2-truth-card-inject.sh` in `persona-engine`: **7,758 B → 287 B**.

## [Critical] the hook is now silent about a real failure

The mission's one hard rule was that a capped hook must stay loud when something is actually wrong.
The reviewer reproduced a crash-shaped failure of `leadv2-one-copy-convert.sh --check` (exit 2,
stderr that is neither a REGRESSION line, a BADLINK line, nor a tally). The new hook prints:

```
⚠ one-copy drift
0 regression(s)/badlink(s).
```

and points at a detail log that is **0 bytes**. The real error text is gone. The pre-lane code
dumped it raw, so this is a regression in exactly the direction the mission forbade: a byte count
bought by hiding a failure.

Handle the non-zero-exit path explicitly: when the underlying command fails, say so in the summary
and put its stderr in the detail file. Then add a control for it — force the checker to exit
non-zero, assert the summary reports a failure and the detail file is non-empty, mutate the handling
out, show RED.

## [High] `--scope changed` does not select the suite any more

The `round1-red` proof was captured at 19:35, before the 19:36:30 commit, while the lane files still
appeared in `git diff --name-only HEAD`. Post-commit the reviewer re-ran it: `changed` resolves to
nine unrelated dirty `docs/leadv2/*` coordination files — which are routine in this repo under
concurrent lanes — so the `HEAD~1..HEAD` fallback never fires because `changed` is non-empty, and
`test-hook-output-cap.sh` is not selected.

Make the selection hold for a committed change with unrelated dirt present, and prove it by running
`--scope changed` at a clean-committed HEAD with those coordination files dirty. A proof captured
before the commit does not describe the state CI will be in.

## [Medium] persona-engine still pays the old bill until the cache refreshes

The live plugin **cache** copy of the hook is byte-identical to the pre-lane version, so
`persona-engine` sessions keep paying 7,758 B until the cache is refreshed and the session
restarted. CLAUDE.md already records that hooks are the exception to one-inode sharing for exactly
this reason.

Record it in `report.md`: what the number is before cache refresh, what it is after, and the exact
step needed. Do not attempt the refresh from inside the lane.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production hook, RED,
  revert, GREEN. A zero-match `sed` is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Do not reorder, add or remove entries in `hooks.json`; it is not in LANE_WRITES.
- Never make a hook quieter about a real problem to improve a byte count.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Commit artifacts with `git add -f <file>`, one file at a time; do not edit `.gitignore`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

A forced checker failure producing a summary that says so and a non-empty detail file, held by a
mutation-proven control; `--scope changed` selecting `test-hook-output-cap.sh` at a committed HEAD
with unrelated dirt present, proven by a pasted run; and `report.md` stating the before/after byte
totals for both repos plus the cache-refresh caveat.
