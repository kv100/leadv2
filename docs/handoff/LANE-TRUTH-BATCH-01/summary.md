# LANE-TRUTH-BATCH-01 — Summary

## Verdicts

### Row 1: LANE-LIVENESS-BLIND-TO-FUNNEL-PATH-01 — **fixed**

**Problem:** dispatch-code.sh self-registers with the default `pulse.md` log_path, but the real worker stream lives at `docs/handoff/dispatch-<sig8>/developer.stream.jsonl`. Liveness resolves via `log_path`, so the stamped path pointed at a file the worker never writes — the lane fell through to `dead:no_handoff_dir`. fanout's finalize register could not correct it: its live-PID guard sees the durable PID from self-registration and skips the overwrite.

**Fix:** Added `leadv2_active_set_log_path` op to active-registry.sh and a corresponding shell function. dispatch-code.sh now calls it immediately after `leadv2_active_register` to stamp `docs/handoff/dispatch-<sig8>/developer.stream.jsonl` as the authoritative log_path.

**Files:**
- `leadv2-active-registry.sh`: `set_log_path` python op + `leadv2_active_set_log_path()` wrapper
- `leadv2-dispatch-code.sh`: `leadv2_active_set_log_path "${reg_id}" "docs/handoff/dispatch-${sig8}/developer.stream.jsonl"` after register (line ~3076)

**Mutation gate proven:** deleting the `set_log_path` call from dispatch-code.sh fails test "Row 1 mutation gate" (pass=14 fail=1).

### Row 2: LANE-REGISTRATION-ONLY-ON-FANOUT-PATH-01 — **already-fixed**

**Problem:** Lanes launched without `--task-id` (direct/backlog-pump dispatch) were invisible to the registry because registration was gated on `-n "${founder_task_id}"`.

**Verdict:** Already fixed by **STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C5** (commit `5d8c5a3`, already on main). That commit replaced the `founder_task_id` gate with `reg_id="${founder_task_id:-dispatch-${sig8}}"`, making hand-dispatched lanes visible to the registry. Our commit builds on top of this — no duplicate implementation.

**Evidence:** `leadv2-dispatch-code.sh:3071` — `local reg_id="${founder_task_id:-dispatch-${sig8}}"`

### Row 3: UNLANED-FIXES-IN-USER-SCRIPTS-COPIES-01 — **fixed**

**Problem:** Exclude-mode DIRECTION-SAFETY blocked overwriting a divergent copy but had no quarantine safety net — an un-landed fix in the copy could be silently lost. Additionally, a permanently-divergent copy re-synced N times would create N identical quarantine copies (unbounded disk growth).

**Fix:**
1. **Quarantine in exclude mode:** Before excluding a file, `_quarantine_copy` preserves its content. The log message includes the quarantine path so the operator can inspect and recover.
2. **Convergence (content-hash dedup):** `_quarantine_copy` now hashes the content and checks whether an identical copy already exists in the quarantine tree for the same `(copy_name, relpath)`. If so, it returns the existing path instead of creating a duplicate. A changed divergent copy still gets a new quarantine entry.

**Files:**
- `leadv2-plugin-sync.sh`: `_quarantine_copy` convergence + exclude-mode quarantine block

**Convergence proven:** 3 additional syncs of the same divergent copy produce 1 quarantine file (not 3). Changed content produces a new quarantine (1 → 2).

## Review Findings Resolution (FIX ROUND 2026-08-13)

| Finding | Severity | Resolution |
|---------|----------|------------|
| Row-2 re-implements STATUS-SURFACE C5 | Critical | Rebased onto main (which has 5d8c5a3). Our delta is ONLY log_path stamping — no duplicate registration logic. |
| Quarantine never converges (3 syncs = 3 copies) | High | Content-hash dedup in `_quarantine_copy`. Proven: 3 re-syncs = 1 file. |
| Zero test coverage of dispatcher change | High | Mutation gate: deleting `set_log_path` from dispatch-code.sh fails the suite. |
| Suite registered twice in run-core-offline.sh | High | One registration only. |

## Test Results

- `test-lane-truth-batch-01.sh`: **pass=15 fail=0**
- Mutation test: removing set_log_path → **pass=14 fail=1** (gate fires)
- `run-core-offline.sh`: **suites passed=44 failed=0 missing=0** (rc=0)
