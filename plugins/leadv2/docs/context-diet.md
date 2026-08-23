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

The digest is `sha256(body + "\n" + utc_date + "\n" + sd_signature)`, so any
real content change, a new day, or a change in `sd_signature` forces a full
re-inject even if the body text is otherwise identical — the founder is
never more than one prompt away from seeing current state.

`sd_signature` (`"<row_id>:<STATUS>"`, `STATUS` ∈
`OVERDUE`/`DUE_TODAY`/`CONDITION_BOUND`, or `""`/`"none"`/`"oversize"`) is
the nearest actionable row in `docs/leadv2/scheduled-decisions.md`,
classified **inside this gate**, independently of the project-local
`.claude/hooks/scheduled-decisions-nearest.sh` renderer that supplies the
line actually shown in the body. That renderer's own suppression is
**id-keyed**: it prints nothing when the nearest row id is unchanged from
the last time it printed this session, even if that row's date just crossed
DUE TODAY → OVERDUE. A body-only digest would therefore never notice the
flip. Computing the classification in-gate closes that hole for the digest
— but the re-injected body can still fail to *name* the row, since the
renderer itself stays silent on an unchanged id; the gate only guarantees
a full re-inject happens, not that the re-injected block mentions the
overdue row. Read is capped at `LEADV2_SD_SCAN_MAX_BYTES` (default 8 MiB);
over the cap the signature degrades to the constant `"oversize"` and the
gate falls back to body+date behavior, still safe but blind to the ledger.

**Deliberately out of scope:** `leadv2-single-lead-beat.sh`'s BROAD_STATUS
injection has its own, older, independent dedup gate and is untouched here.
The existing task-mode dedup marker (`/tmp/.leadv2-task-anchor-full-<sid>-<task>`,
used when a leadv2 task *is* active) is also separate and unaffected — this
gate only covers the no-active-task thread anchor.

**Kill-switch:** `LEADV2_INJECT_DEDUP=0` disables the gate entirely; every
fire prints the full block. `LEADV2_SD_SCAN_MAX_BYTES` (default `8388608` =
8 MiB) caps the scheduled-decisions ledger read; set to `0` or a negative
value to force `sd_signature="oversize"` on every read, i.e. opt the ledger
scan out without touching `LEADV2_INJECT_DEDUP`. Any internal failure
(unwritable state dir, missing session id, corrupt state, unparseable
ledger) also fails open to the full block — this gate is only ever allowed
to suppress an injection it is certain is a duplicate of the last one it
sent. A fail-open path additionally writes one `[inject-dedup] fail-open:
<err>` line to the hook's stderr (never to the injected body), so a future
bug in the gate degrades visibly instead of silently becoming
always-full-inject.

**Post-compact clear:** `/compact` drops earlier turns from the transcript
but the stored digest is keyed by session id and survives on disk, so
without a clear the very next prompt after compaction would wrongly see
the one-line marker with no actual full block behind it in context.
`leadv2-pre-compact-checkpoint.sh` (registered on `PreCompact`) best-effort
removes both `<STATE_DIR>/.inject-hash.<sid>.*` and
`/tmp/.leadv2-task-anchor-full-<sid>-*` for the compacting session, so the
first prompt after `/compact` always gets the full block again.
