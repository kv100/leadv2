# PLUGIN-MARK-FINISHED-DOES-NOT-RELEASE-THE-ROW-01

Backlog row `980e16e6ffd2` (persona-engine `docs/tasks.yaml`, group `leadv2-plugin`).
Repo for ALL writes: **`~/Projects/leadv2`** — the file is
`plugins/leadv2/scripts/leadv2-active-registry.sh`, which exists only here.

## Problem (measured, three misses in one day)
`leadv2_active_mark_finished` returns **rc=0 without removing the row from `active.yaml`**. So a
merged lane keeps its write-set claim, and the next lane that needs the same files is refused
`writeset_conflict`. The caller sees rc=0 and believes the release happened. Two consequences
already paid for:
- a lead cannot retire its own claim — it calls the function, gets rc=0, and the claim survives;
- `active.yaml` accumulates rows whose lane is long dead (the live registry currently carries
  dozens of `stale: true` rows in `spawning`), so the lane cap is consumed by ghosts.

Related known fact: `leadv2-active-registry.sh` is a **library, not a CLI** — `bash <script> list`
is a silent rc=0. Source it. If you add a check, make sure it is reachable the way callers
actually enter.

## Change
1. `leadv2_active_mark_finished` must actually remove (or definitively mark released, per the
   schema's own convention — read it, don't invent one) the row it names.
2. It must return **non-zero** when it did not: row not found, file unwritable, lock not taken,
   concurrent rewrite lost the edit. rc=0 must mean "the row is gone from `active.yaml`, verified
   by re-reading the file after the write" — not "the function ran".
3. Never leave `active.yaml` truncated or half-written on a failure path.

## Acceptance
Registered probe: `grep -n mark_finished ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-active-registry.sh | head -1`
— that grep is a locator, not proof. The real acceptance is behavioural:

- A test under `tests/` that, against a FIXTURE `active.yaml` (never the live one):
  (a) marks an existing row finished → rc=0 **and** a re-read shows the row absent **and** its
      writes no longer block a dispatch-time write-set check;
  (b) marks a row that does not exist → **non-zero**, file unchanged;
  (c) simulates a failed write (read-only file) → **non-zero**, file not corrupted.
- **Negative control, RUN it:** inside the function body, make the removal a no-op while still
  returning 0 — exactly today's bug. Re-run the test in a scratch worktree, show it goes RED,
  restore. Paste both outputs. If the suite stays green under that mutation, it does not test
  this row at all.

## Off limits
- Do NOT mass-sweep the live `~/.claude/leadv2-state/*/active.yaml` — other sessions are live in
  both repos right now. Fix the function; sweeping is a separate decision.
- Do not change the lane-cap resolution order (override file > meta > `LEADV2_LANE_CAP`).
- Do not touch the write-set conflict taxonomy itself.

## Report
`docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/report.md` — diff summary, the three test cases
green, the negative control red. End with `DELIVERABLE_COMPLETE`.
