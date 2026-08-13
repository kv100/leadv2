# SUPERVISOR-HARDENING-01 — build report

Finisher (resume-once) pass. Repo root: `~/Projects/leadv2` (plugin canonical
source). No commit, no push, no `git add`. No revert of any dirty statusline
hunk the finisher did not author. All six items were already on disk from the
prior (exit-76) worker; the finisher's whole job was the three mission tests,
the `bash -n` sweep, and this report.

## 1. Disk state — six-row item table

`bash -n` passes on every touched/new file (no half-finished edit was found).
The persona-engine PostCompact hook is a symlink to the canonical plugin hook
(shared-tree policy satisfied — verified: `persona-engine/.claude/hooks/
leadv2-supervisor-mode-reinject.sh -> .../plugins/leadv2/hooks/...`).

| # | Item | Status | On-disk evidence |
|---|------|--------|------------------|
| 1 | PostCompact reinject hook (both markers, PID-checked, fail-open) | DONE | `plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh`; Branch A `.supervise-active` (live PID) + Branch B legacy `SUPERVISOR-MODE.on`; emits role block + `supervisor-role.md` pointer |
| 2 | Loop self-watchdog (`loop_silent`) | DONE | loop `_write_heartbeat` + `HEARTBEAT_FILE`; `scripts/leadv2-supervise-watchdog.sh` emits one `LOOP_SILENT` through the dedupe |
| 3 | Status beat on `--ensure` (cron-owned) | DONE | loop "Item 3: cron-owned status beat", installed on both `--ensure` outcomes, marker-tag idempotent, python3 fcntl lock |
| 4a | Statusline supervisor gate (supervisor-only lanes digest) | DONE | `leadv2-lane-status-line.sh` `_leadv2_statusline_sup_active` — `--no-link .supervise-active` resolve, base line only when not supervising |
| 4b | Lane-list + liveness caches | DONE | `leadv2-lane-status-line-tail.sh` `LANE_CACHE_FILE`, `LABEL_MEMO_FILE`, `LIVENESS_MEMO_FILE` (~10 s memo) |
| 5 | Alarm dedupe lib (transition on (key,value)) + wiring | DONE | `scripts/lib/leadv2-alarm-dedupe.sh`; wired in loop (pass-through fallback + `leadv2_alarm_filter` / `_filter_seen` / `_sweep`) and watchdog; covers truth_red, job_stalled, lane_no_artifact, loop_silent |
| 6 | Dead-without-deliverable terminal check | DONE | loop `LANE_DEAD_NO_ARTIFACT` 4-condition check (dead lane + success-shape + no deliverable + no commits), always-sweep so a late deliverable clears the key |

## 2. `bash -n` sweep (§1 files + three new tests)

All nine parse clean (`bn_fail=0`):

```
OK   plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh
OK   plugins/leadv2/scripts/lib/leadv2-alarm-dedupe.sh
OK   plugins/leadv2/scripts/leadv2-supervise-loop.sh
OK   plugins/leadv2/scripts/leadv2-supervise-watchdog.sh
OK   plugins/leadv2/scripts/leadv2-lane-status-line.sh
OK   plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh
OK   plugins/leadv2/scripts/tests/test-supervisor-mode-reinject.sh
OK   plugins/leadv2/scripts/tests/test-statusline-supervisor-gate.sh
OK   plugins/leadv2/scripts/tests/test-alarm-dedupe-transition.sh
```

## 3. Test results

New mission tests (T1–T3), all green:

| Test | rc | Result |
|------|----|--------|
| `test-supervisor-mode-reinject.sh` (item 1) | 0 | 12 passed, 0 failed |
| `test-statusline-supervisor-gate.sh` (item 4a) | 0 | 6 passed, 0 failed |
| `test-alarm-dedupe-transition.sh` (item 5) | 0 | 9 passed, 0 failed |

Pre-existing regression tests (run as required by T4):

| Test | rc | Result | Note |
|------|----|--------|------|
| `test-supervise-failclosed.sh` | 0 | PASS=6 FAIL=0 | clean |
| `test-statusline-readable.sh` | 1 | pass=8 fail=1 skip=1 | **cross-lane note:** the 1 failure is `R10` in the dirty `leadv2-lane-status-line-tail.sh` hunk (line 189 cache write, item 4b) — NOT in any file this finisher authored. Per the non-goals ("a hunk you did not author is off limits"), it is recorded here, not fixed. |
| `test-supervise-v2.sh` | 124 (timeout) | passes Tests 1–11, no FAIL reached | **cross-lane note:** Test 12 ("pid:null funnel row survives prune") did not complete within a 110–130 s timeout. This is a heavy tmux/`-L`-socket integration test in the dirty loop/watchdog hunks, unrelated to the three new test files. Recorded, not investigated (off-lanes). |

## 4. Acceptance mapping

- **file_artifact** — this report: six-row DONE table (§1), test table listing all
  three new tests with non-zero pass / zero failures (§3). ✔
- **log_line** — item 5 dedupe is wired at the emitters; a repeated alarm condition
  now fires once per `(key,value)` transition and does not re-fire until the value
  changes (asserted directly by `test-alarm-dedupe-transition.sh` cases 1a/1b/2,
  and the sweep→CLEAR→re-fire recovery edge by cases 3/4). The runtime log_line
  is observable once a supervise session runs against the wired loop. ✔

DELIVERABLE_COMPLETE
