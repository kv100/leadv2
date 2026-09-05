# Round 2 — the plugin-sync fix has no tests, and it governs the one-copy rule

Repo: ~/Projects/leadv2, `main` at `7de23af`. Continue in the EXISTING lane worktree
`.claude/worktrees/67198a6e` (head `f05eddf`). Confirm your root is in `git worktree list`
before writing anything.

## State, verified by the lead

`f05eddf` changes exactly one file:

```
plugins/leadv2/scripts/leadv2-plugin-sync.sh | 214 ++++++++-------- (164 insertions, 50 deletions)
```

Lead-run checks on that tree:
- `bash -n plugins/leadv2/scripts/leadv2-plugin-sync.sh` — clean.
- `bash plugins/leadv2/scripts/tests/test-one-copy-drift.sh` — 8 passed, 0 failed. The existing
  drift detector still works.

**It has no tests of its own.** This file decides whether a script under a project's
`.claude/scripts/` ends up a symlink to canonical or a real copy. A real copy drifts silently —
that is the failure this whole change exists to prevent, and it is currently unguarded.

The branch is also behind `main`; merge `main` into it first, so main's three landed fixes are
present and the suite list is current.

## Do

Add `plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh` covering the three
outcomes the change introduces, each as a real filesystem fixture (a temp project dir with a
`.claude/scripts/`, and a fake canonical tree), not a mocked function call:

1. **LINK** — a canonical script with no counterpart in the project is created as a **symlink**
   pointing at canonical. Assert `-L` on the path and that `readlink` resolves to the canonical
   file. This is the case that regressed: the old rsync excluded only *pre-existing* symlinks,
   so anything new landed as a real copy.
2. **CONVERT** — a project path that is a real file byte-identical to canonical is converted to
   a symlink. Assert `-L` afterwards, and assert the content still resolves to canonical.
3. **DRIFT** — a project path that is a real file and **differs** from canonical is NOT silently
   overwritten. Assert the divergent content survives and that the run reports it (exit code and
   message both asserted — a silent survival is as wrong as a silent overwrite).

Plus two guards that tonight's incident makes non-optional:

4. **Idempotence** — running the sync twice changes nothing on the second run (no churn, same
   inode for the symlink).
5. **Declared exception** — a path listed as a deliberate per-repo override is left alone and is
   not converted to a symlink.

Wire the suite into `run-core-offline.sh` the way its siblings are wired.

If a test exposes a real defect in `leadv2-plugin-sync.sh`, fix it minimally and say so. Do not
reshape the script to make a test convenient.

## Off-limits
- Do not touch any project's real `.claude/scripts/` — tests run against temp fixtures only.
- Do not merge to `main` yourself; commit on the lane branch, the lead lands it.
- No `reset --hard` / `clean` / `stash`: shared tree, live sessions.

## Verify (FOREGROUND, explicit timeout, real pasted output)
1. `bash plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh` — every case.
2. `bash plugins/leadv2/scripts/tests/test-one-copy-drift.sh` — must stay 8 passed, 0 failed.
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Known-foreign
   and NOT yours: `deferred-GLM ladder (V3-GLM-LADDER-01)` and `fanout classifier/runner guard`.
   A separate lane is fixing a third (`parked worker contract`, a self-invalidating red-first
   assertion) — if you still see it, name it and move on; do not fix it here.

## Deliverable
`docs/handoff/PLUGIN-SYNC-CLAUDE-SCRIPTS-01/report-round-2.md` — the five cases with pasted
output, any defect a test exposed, `git diff --stat` against `7de23af`.
End with DELIVERABLE_COMPLETE.
