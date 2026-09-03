# STATUS-CHURN-01 — one status snapshot per cadence, shared by every consumer; spawn-rate instrumented

Source: `~/Desktop/leadv2-laptop-load-ticket-for-dima-2026-09-01.md` §"Preferred code-level follow-up"
items 2 and 3 (item 1 is BEAT-LOOP-ORPHANS-01). Founder 2026-09-01: "было бы найс разобраться".
LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/STATUS-CHURN-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/leadv2-lanes-snapshot.sh,plugins/leadv2/scripts/leadv2-lane-liveness.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/lib/leadv2-status-cache.sh,plugins/leadv2/scripts/leadv2-spawn-rate.sh,plugins/leadv2/scripts/tests/test-status-churn.sh,tests/run-all.sh,docs/handoff/STATUS-CHURN-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured 2026-09-01 (lead, one `ps` instant, load avg 244)
`leadv2-pulse-beat.sh --now` ×13, `leadv2-broad-status.sh` ×10, `leadv2-status-collector.sh` ×8,
`leadv2-lanes-snapshot.sh --json` ×4, `leadv2-lane-liveness.sh` ×6, `leadv2-lane-detail.sh` ×4 —
every one an independent Python scan of `active.yaml` + every `*-runs/` dir, spawned by a different
consumer (statusline, beat loop, pulse watch, backlog pump, lead hooks) at its own cadence. The ticket's
read-only samples: CPU spikes are these short-lived jobs (66–92 % of a core each), not the sleeping loops.

## Do
1. `scripts/lib/leadv2-status-cache.sh`: ONE snapshot file per project
   (`<control-plane>/status-snapshot.json`, atomic tmp+mv, with `computed_at`). A consumer asks for a
   snapshot no older than N s; if fresh, it reads the file; if stale, exactly one producer recomputes
   (flock) and the rest wait ≤ 2 s then read. `broad-status`, `status-collector`, `lanes-snapshot`,
   `lane-liveness`, `lane-status-line-tail` all read through it. Default freshness 10 s
   (`LEADV2_STATUS_SNAPSHOT_TTL_S`), never below 3.
2. Debounce: a consumer that already produced a snapshot within TTL returns immediately; journal
   `status_snapshot hit|miss|recompute producer=<script> age_s=<n>` — one line per call, so the rate is
   measurable from the journal.
3. `scripts/leadv2-spawn-rate.sh`: prints, for the last 15 min, child-process starts per minute by
   script name and p50/p95 wall time (from the journal lines above + `ps` sampling every 10 s while it
   runs). This is the ticket's acceptance instrument — the before/after numbers come from it.
4. Suite `test-status-churn.sh`: (a) five concurrent consumers within TTL → exactly one recompute
   line; (b) stale snapshot → one recompute, others wait and read the new `computed_at`; (c) a consumer
   never reads a snapshot older than TTL+2 s. Mutation negative control, RUN and paste red: remove the
   flock → (a) red (≥2 recomputes). Register in `tests/run-all.sh`.
5. Evidence: `leadv2-spawn-rate.sh` before (from main) and after (this branch) over the same 15-min
   window with the same 4 lanes live; paste both tables in report.md.

## Do NOT
Change what any status surface DISPLAYS; change beat/pulse cadence (env already tuned per ticket);
touch the lane watcher's stall rules (ONE-LANE-WATCH-01-R2) or the orphan fix (BEAT-LOOP-ORPHANS-01).
