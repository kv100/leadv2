# Context diet: per-turn injection dedup (HOOK-INJECT-DEDUP-01)

`leadv2-task-anchor.sh`'s thread-anchor block (the "NO ACTIVE TASK — thread
anchor" injection shown on `UserPromptSubmit` when no leadv2 task is active)
is content-hash gated per session. On the founder's first prompt in a
session it prints in full; on any later prompt in the same session whose
open-threads/scheduled-decisions content is byte-identical *and* the UTC
date has not rolled over, it collapses to a single line:

```
<task-anchor>thread anchor unchanged — docs/leadv2/open-threads.md; the block above still governs.</task-anchor>
```

The digest is `sha256(body + "\n" + utc_date)`, so any real content change
or a new day forces a full re-inject even if the body text is otherwise
identical — the founder is never more than one prompt away from seeing
current state.

**Deliberately out of scope:** `leadv2-single-lead-beat.sh`'s BROAD_STATUS
injection has its own, older, independent dedup gate and is untouched here.
The existing task-mode dedup marker (`/tmp/.leadv2-task-anchor-full-<sid>-<task>`,
used when a leadv2 task *is* active) is also separate and unaffected — this
gate only covers the no-active-task thread anchor.

**Kill-switch:** `LEADV2_INJECT_DEDUP=0` disables the gate entirely; every
fire prints the full block. Any internal failure (unwritable state dir,
missing session id, corrupt state) also fails open to the full block —
this gate is only ever allowed to suppress an injection it is certain is a
duplicate of the last one it sent.

**Post-compact clear:** `/compact` drops earlier turns from the transcript
but the stored digest is keyed by session id and survives on disk, so
without a clear the very next prompt after compaction would wrongly see
the one-line marker with no actual full block behind it in context.
`leadv2-pre-compact-checkpoint.sh` (registered on `PreCompact`) best-effort
removes both `<STATE_DIR>/.inject-hash.<sid>.*` and
`/tmp/.leadv2-task-anchor-full-<sid>-*` for the compacting session, so the
first prompt after `/compact` always gets the full block again.
