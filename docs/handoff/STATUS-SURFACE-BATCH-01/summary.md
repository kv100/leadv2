# STATUS-SURFACE-BATCH-01 — Summary

## Per-row verdict

### 1. MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — **already-fixed**

Both defects are resolved in the current tree:

**Dead lanes showing as active:** The `render_single_lead()` path uses a
unified `_terminal_hit(repo, sig8, task_id, lane_label)` function
(`leadv2-status-surface.sh:3004-3013`) that matches terminal ledger rows by
sig8 (first), then task_id/founder_task_id, then lane_label — per-repo, so a
terminal row in repo A can never blank a reservation in repo B. Lanes with a
terminal hit are dropped via `classify()["terminal"] == True` at
`leadv2-status-surface.sh:3250,3281`. Commit `fb9165d` (in HEAD) directly
addresses this row.

**Hash names instead of human task-ids:** `lane_name()` at
`leadv2-status-surface.sh:3015-3034` resolves from reservation fields
(task_id → founder_task_id → lane_label) → terminal fields → census task_id
→ sig8 fallback. The `.5s.sh` widget additionally resolves sig8 tokens
through `resolve_lane_label()` and `labels.map` on the render path
(`leadv2-status-surface.5s.sh:148-176,265-275`). Raw sig8 survives only in a
demoted detail line.

### 2. STATUSLINE-FLICKER-PARTIAL-CACHE-01 — **fixed**

**Root cause:** When the wrapped user command (`~/.claude/burn/statusline.sh`)
failed or timed out, `leadv2-lane-status-line-tail.sh` replaced BASE with
`FALLBACK_BASE` — a different line lacking the style segment and burn
fragment. The cached line then alternated between the user-command output and
the fallback on every refresh boundary, producing the visible "статуслайн
скачет" flicker.

**Fix:** The tail script now reads the previous cached line before computing
a new one. When the user command fails, it extracts the BASE portion
(everything before the last ` \033[34m| ` separator) from the previous cache
and reuses it, so the BASE segment is stable between refreshes. `FALLBACK_BASE`
is only used on the first-ever render (no prior cache). Git-branch fallback
is skipped when preserving the previous BASE (the prior successful render
already carries its own formatting).

**Proof:** `tests/test-status-surface-batch01.sh` T1 (success→fail preserves
BASE), T2 (no-cache→fallback), T5 (consecutive successes byte-identical).

**File:** `plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh:73-110`.

### 3. STATUSLINE-SHOWS-LANES-QUESTIONMARK-01 — **already-fixed**

Both defects are resolved:

**Latency fallback (defect 1):** The foreground (`leadv2-lane-status-line.sh`)
never runs a synchronous cold path. It either cats the cache or reads the D1.5
count sidecar (`leadv2-statusline-lanecount-*`, written immediately after
every successful liveness read by the tail script). "lanes ?" appears only on
the literal first-ever render before any detached refresher has completed.

**Wrong path shape (defect 2):** The tail script now calls
`leadv2-lane-liveness.sh --all --json --no-codex` (C5 fix, tail script lines
411-414) as the sole liveness source. Lane-liveness.sh discovers lanes via
`docs/handoff/*/WORKER_STREAM_NAMES` glob, which finds
`dispatch-<sig8>/developer.stream.jsonl` — the actual stream file for
funnel-launched lanes. The `fanout-lane-<task_id>/` directories are launch
markers (containing only `launcher.log` and `mission.txt`); the actual worker
stream lives in the dispatch dir and is already discoverable.

### 4. SD-STATUSLINE-BURN-FIRSTCLASS-01 — **fixed**

**Root cause:** `LEADV2_STATUSLINE_DROP_BURN` defaulted to `1`, which stripped
the burn segment (` | <N>t <Hh MMm>` — turns + session lifetime from the
founder's `~/.claude/burn/statusline.sh`) from BASE entirely before width
budgeting, giving the burn zero width budget.

**Fix:** Default changed from `1` to `0` in
`leadv2-lane-status-line-tail.sh:103`. The burn segment now survives every
BASE-compression step (steps 0-4 target context parentheticals, style
brackets, cwd paths, and ctx% — none match the pipe-delimited burn fragment).
The lanes digest compresses to accommodate the burn, which is the correct
precedence: burn is context the founder asked for, lanes are supplementary.
`LEADV2_STATUSLINE_DROP_BURN=1` remains as a one-flip escape hatch.

**Proof:** `tests/test-status-surface-batch01.sh` T3 (burn preserved by
default), T4 (DROP_BURN=1 still strips it).

**File:** `plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh:96-107`.

## Test results

| Suite | Result |
|-------|--------|
| test-status-surface-batch01.sh (new) | 6 passed, 0 failed |
| test-status-surface-parity.sh | 12 passed, 0 failed |
| test-status-surface-fast-names.sh | 12 passed, 0 failed |
| test-status-surface-single-lead.sh | 23 passed, 0 failed |
| test-status-surface-bash32.sh | 14 passed, 1 failed (pre-existing: `_t6b` live-state row-count drift, unrelated to tail script changes) |

## Files changed

- `plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh` — flicker fix + burn first-class
- `tests/test-status-surface-batch01.sh` — new test suite (hermetic)
- `docs/handoff/STATUS-SURFACE-BATCH-01/summary.md` — this file
