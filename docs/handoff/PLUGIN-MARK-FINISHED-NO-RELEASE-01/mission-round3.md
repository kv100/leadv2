# PLUGIN-MARK-FINISHED-DOES-NOT-RELEASE-THE-ROW-01 — round 3

Row `980e16e6ffd2`. Rounds 1–2 landed (`132dd4b3` + round 2) and the row was **closed, then
reopened by the lead on live evidence**. All writes in **`~/Projects/leadv2`**, file
`plugins/leadv2/scripts/leadv2-active-registry.sh`.

## The measurement that reopened it — 2026-09-15, live registry

```
$ export LEADV2_PROJECT_ROOT=~/Projects/leadv2 PROJECT_ROOT=~/Projects/leadv2
$ source plugins/leadv2/scripts/leadv2-active-registry.sh
$ _leadv2_yaml_file
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/active.yaml      # correct file
$ leadv2_active_mark_finished dispatch-2c6e1405 landed '{"evidence":"merged d08d4f17"}'
$ echo $?
0
```

**rc=0, and the row survived.** After the call, `~/.claude/leadv2-state/leadv2/active.yaml` still
carries:

```
- session_id: s-20260915T030041Z-1-62617
  task_id: dispatch-2c6e1405
  phase: spawning
  stale: true
  writes: plugins/leadv2/scripts/leadv2-orphan-reaper.sh,plugins/leadv2/scripts/tests/test-reaper-dry-run-env-precedence...
  dead_at: '2026-09-15T08:25:42Z'
  updated_at: '2026-09-15T08:27:14Z'          <-- the ONLY field the call moved
  lane_events:
  - {at: '2026-09-15T08:25:42Z', event: reconciled_dead}
```

So the call reached the file and touched the row — `updated_at` moved — but the **write-set claim
was not released**. The lane `dispatch-2c6e1405` had landed and merged two hours earlier
(`d08d4f17`).

## Why this is the keystone, not a cosmetic miss
`MAIN-RED-SUITES-BLOCK-EVERY-LANE-01` has now been refused **four times** with
`writeset_overlap ... blocked_by=dispatch-2c6e1405` — blocked by a dead lane. That lane in turn
blocks `PLUGIN-PREPASS-PHANTOM-DESIGN-01`, whose review cannot pass until the red suites are
fixed. One unreleased claim is holding three rows.

## Why round 2's suite did not catch it
The round-2 suite passes 4/4, and it is not lying — it exercises **fixtures**. The live row has a
shape the fixtures do not: `stale: true`, `dead_at` set, `phase: spawning`, a `lane_events` list
with `reconciled_dead`, and a `task_id` carrying the `dispatch-` prefix. A green fixture suite
beside a broken live path is the exact false green this whole row exists to eliminate.

## Required first step — find which condition skips the release
Do not guess and do not patch blind. Instrument or trace `leadv2_active_mark_finished` against a
**copy of the real row above** and report the exact branch that returns success without removing
the claim. Name it with `file:line`. Candidates worth checking, none assumed:
- the `task_id` lookup shape (`dispatch-<sig>` vs `<sig>` — note `mark_finished <sig>` alone
  answered `task not registered`, so the prefix matters somewhere);
- a guard that treats `stale: true` or a non-null `dead_at` as "already handled";
- a guard keyed on `phase`, where `spawning` is not in the released set;
- writing to a different list than the one the write-set check reads.

State the branch before the fix. A compound fix that removes the symptom teaches nothing about the
cause.

## Then fix, and prove it on the live shape
- After `mark_finished`, **zero live rows** may remain holding that `task_id`'s write set — the
  verifier must re-read the file and confirm the absence, not confirm the row it just touched.
- `rc=0` must mean the claim is gone. If the row cannot be released, the call must return non-zero
  with a named reason. A success code over an unchanged file is the defect.

## Acceptance — fixtures built FROM the live row
Copy the real row above verbatim into a fixture, including `stale: true`, `dead_at`,
`phase: spawning`, the `lane_events` entry and the `dispatch-` prefixed `task_id`. Then:
1. `mark_finished` on it → the claim is gone and a dispatch-time write-set check against those
   paths no longer conflicts. Show the check, not just the file.
2. The round-2 properties still hold: two live rows sharing one `task_id` are both released; no
   failure path leaves `active.yaml` truncated.
3. A `task_id` that genuinely is not registered still returns non-zero.

## Negative controls — one per property, all RUN
1. Restore the branch you found in step 1 → the live-shape fixture test goes RED.
2. Restore the first-match-only release → the duplicate-row test goes RED.
3. Restore the truncating write → the corruption test goes RED.
Paste all three red/green pairs. An unmatched mutation anchor is a test failure, never a silent skip.

## Off limits
- Do NOT sweep or edit the live `~/.claude/leadv2-state/*/active.yaml`. Fixtures only — other
  sessions are live in both repos right now.
- Do not change the lane-cap resolution order or the write-set conflict taxonomy.
- `leadv2-active-registry.sh` stays a library, not a CLI.

## Report
Append `## Round 3` to `docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/report.md`: the named
branch with `file:line`, the fix, the live-shape fixture, all three controls.
End with `DELIVERABLE_COMPLETE`.
