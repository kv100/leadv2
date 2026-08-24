# Lane worktree sweepers

`SWEEPER-LANE-SAFETY-01` protects a lane from unattended removal. The three
unattended entry points are:

- SessionStart: `hooks/leadv2-merged-worktree-sweep.sh`.
- Phase-8 close: `scripts/leadv2-worktree-cleanup.sh --sweep-merged` and
  `--sweep-dead`.
- Stale-session cleanup: `scripts/leadv2-stale-sweeper.sh`, which calls
  `leadv2-worktree-cleanup.sh --sweep-dead`.

All use `scripts/lib/leadv2-worktree-protected.sh`. It primes the control plane
once per pass, then protects a worktree if it has a matching `active.yaml`
session row (rc 1), an open `arm-registered` handoff marker (rc 2), a live
registered pid (rc 3), or is within the age window (rc 4). rc 0 means the
caller may apply its ordinary merged, dirty, and liveness checks.

Any unreadable gate input is rc 5 (`read-error:*`) and fails closed: every
candidate is kept for that pass, with one visible warning and debug log
entries. In particular, an empty `active.yaml` is treated as unreadable, so an
otherwise idle repository protects every worktree until the registry contains a
valid mapping.

## Age window

`LEADV2_SWEEP_MIN_AGE_S` is the preferred seconds setting when it is numeric.
`LEADV2_SWEEP_MIN_AGE_H` is the legacy hours setting used otherwise. Their
effective default is 48 hours; `0` disables only the age probe, never the
active-session, handoff, or pid probes. The probe uses the linked worktree's
creation-stamped gitdir mtime, falling back to the directory mtime only when
the gitdir stamp is unavailable.

Every actual removal makes a best-effort task-journal entry:
`worktree_swept id=<id> reason=<reason>`. A journal write failure does not undo
an already-completed removal, so this is forensic help rather than a removal
transaction.

## Deliberate boundaries

An explicit owner reap, `leadv2-worktree-cleanup.sh --name <id>`, is ungated by
design. The merged-sweep hook force-discards nothing (H2,
MERGED-BATCH-FIXROUND-01): it restores tracked orchestration paths from HEAD,
removes only untracked regenerated bookkeeping, then runs a plain
`worktree remove` — a removal refusal keeps the lane, and untracked
`docs/handoff/**` content always counts as real dirt and is never discarded.
A locked worktree is probed BEFORE any discard and kept byte-identical
(P9 / incident b413968c: never mutate ahead of the removal decision).
