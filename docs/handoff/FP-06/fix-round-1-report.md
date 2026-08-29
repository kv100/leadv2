# FP-06 fix-round 1 — telemetry truth (final arm), terminal census, safe packing

Review: `docs/handoff/dispatch-5aeaa8bb/review-opus.md`. Fixed: H1, H2, H3, M2, M3 (+H4 cap,
noted M5-adjacent). Skipped per mission: M1, L*.

**H1** — `_MS_MODEL` re-stamped at the top of every candidate-loop iteration; re-arbitration
sites (bench-fallback, exit76-continuation) refresh `_arb_model` for the NEW first candidate.
Row now names the FINAL executing arm/model (same identity `worker_spawned` journals).
**H2** — all 7 terminals instrumented: win, all_arms_unavailable, all_arms_exhausted,
all_arms_not_dispatchable_v2 ×2, all_arms_capped, all_arms_quota_locked,
all_arms_exhausted_quota, all_arms_excluded.
**M2** — every emitted value sanitized (`tr ' \t=\r\n' '_'`) before k=v journal row AND CSV.
**M3** — header+row append under one `lv2_lock_wait` critical section.
**H3** — negative controls run from a mktemp-unique $TMP scripts mirror (symlinked siblings),
never the canonical dir.
**Tests** — suite extended (e/g1–g6/h/i + H1 RUN-red negative control reproducing the round-1
lie under mutation).

```
bash -n: dispatch OK; telemetry suite OK
test-model-select-telemetry.sh: === 54 passed, 0 failed ===
test-freepool-capability-floor.sh: === 31 passed, 0 failed ===
tests/run-all.sh --scope changed: run-all: 6 passed, 2 failed, scope=changed
  run-core-offline.sh — known pre-existing aggregate red (baseline memory, 2026-08-28)
  test-phase-precondition.sh — pass=70 fail=9, IDENTICAL at clean HEAD (stash-free
    checkout proof): project_root_guard foreign_env_overridden worktree artifact, not this diff
```

DELIVERABLE_COMPLETE
