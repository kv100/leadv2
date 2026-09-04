# MON-PULSE-01 — dispatcher-owned lane watch + single-lead pulse beat default-on

Commit: see lane branch. All evidence from this session's runs (raw tails below).

## Built
1. `leadv2-lane-pulse-watch.sh` (new): detached nohup watcher armed by
   `leadv2-dispatch-code.sh` at worker_spawned (single choke point
   `_spawn_worker_body`, covers router + arm_advance). Replay-safe: offset
   starts 0 → first pass reads `tail -n +1`; matches
   `dispatch_terminal|dispatch_refused|worker_died|review_gate` for ITS sig
   only; pulses via existing `leadv2-pulse.sh`; pidfile per sig; exits at
   terminal, at FREEPOOL/GLM timeout (3900s), or when the lane root/journal
   disappears (grace 300s).
2. `leadv2-single-lead-beat-loop.sh` (new): armed once at first spawn
   (pidfile); every 300s drives `leadv2-pulse-beat.sh --check` while ≥1 lane
   is live; exits on real-zero, root-gone, or 3 unknown counts. Kill-switches
   `LEADV2_PULSE_MODE=0`, `LEADV2_SINGLE_LEAD_BEAT=0`.
3. `tests/run-all.sh`: EXTRA_SUITE_MAP added (stem→suite).

## Tests
`test-lane-pulse-watch.sh` 4/4 (W4 = negative control: `tail -n 0` revert RUN
RED, misses the pre-existing terminal); `test-single-lead-beat-loop.sh` 5/5.
E2E probe: real dispatch spawn → watcher armed and alive (`ARMED --sig
a38d3b21`).

## Known baseline (NOT this diff — A/B-proven)
`tests/run-all.sh --scope changed`: 5 passed, 1 failed (run-core-offline 74/9).
8 of 9 reds reproduce identically on pristine HEAD in a clean worktree;
`phase-precondition` is worktree-location dependent. The 9th (fg-dispatch
guard hook) is a hermeticity FAIL from symlink repair dirt, PASS=36 FAIL=0 on
assertions.

## Limitation
Beat-loop pidfile guard is keyed per state root; dispatches from different
PROJECT_ROOTs can arm parallel loops (each self-exits when its board empties).

```
test-lane-pulse-watch: 4 passed, 0 failed
test-single-lead-beat-loop: 5 passed, 0 failed
run-all: 5 passed, 1 failed, scope=changed
[CORE-OFFLINE] suites passed=74 failed=9 missing=0
```
