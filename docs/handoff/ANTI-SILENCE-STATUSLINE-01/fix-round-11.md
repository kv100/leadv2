# ANTI-SILENCE-STATUSLINE-01 — round 11: the suite must put the directory back

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

HEAD is `365b5da`. Main is `cf1349e`. This is the last open item on the lane.

**Round 10's hermeticity fix works and stays.** I verified it against the live world:

```
baseline                                              91 passed, 0 failed
a real question added to docs/leadv2/questions        91 passed, 0 failed
question removed                                      91 passed, 0 failed
```

The count no longer moves with the number of open questions. That was the cause of 90/0 in the
lane against 85/5 and then 62/21 on main, and it is settled.

## [Critical] the suite still replaces the real questions directory with a symlink

Immediately after that run:

```
lrwxr-xr-x  docs/leadv2/questions      <- symlink into a temp sandbox
??          docs/leadv2/questions
```

The suite points `docs/leadv2/questions` at its own fixture and never restores it. When the
sandbox is cleaned, the path becomes a dangling symlink and **every lane question the dispatcher
writes goes nowhere** — a lane can block on a question no one can see or answer.

This is not hypothetical and not new. An hour ago I repaired exactly this in leadv2 `cf1349e`, and
the *committed* version of that path was also a dangling symlink, swept into the repo by `a310073`
"session close". So a previous run's damage has already been persisted into git once. I restored
the directory by hand twice tonight.

Fix the teardown:

- the fixture must live entirely inside the suite's own temp dir — never re-point a repo path;
- if the suite genuinely must swap the path, it needs a `trap ... EXIT` that restores the original
  inode on **every** exit path, including failure and interrupt;
- nothing under `docs/leadv2/` may be left modified after the suite runs.

Prove it, pasted:

1. record `ls -ld docs/leadv2/questions` and `git status --short docs/leadv2/` before the run;
2. run the suite;
3. record both again — the directory must be unchanged and `git status` must show nothing new;
4. run the suite again with a **forced failure** inside it (make one assertion fail) and repeat
   step 3 — the teardown must hold on the failure path too;
5. a control: remove the restore, show step 3 detecting the damage, put it back.

Audit the suite for any other repo path it re-points or writes while you are there, and say in
`report.md` how many you found.

## [Medium] `tests/run-all.sh`

Reconcile with main — keep the state-file bounding, the widened
`scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob and the `freepool-arm.yaml` case; re-apply this
lane's `test-*.sh` self-selection case and its two `leadv2-lane-status-line*.sh` map rows.

## Rules

- Mutation INSIDE the production file, RED, revert, GREEN, clean `git diff --stat`. A suite that
  stays green with the fix removed is a failed control; a printed `RED control:` line that does not
  change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The suite leaves `docs/leadv2/` byte-identical on both the success and the failure path, shown with
before/after listings, and a reconciled `tests/run-all.sh`. Then this lane is merge-ready.
