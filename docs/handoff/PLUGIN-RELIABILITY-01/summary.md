# PLUGIN-RELIABILITY-01 — Summary

**Date:** 2026-08-12
**Branch:** worktree-PLUGIN-RELIABILITY-01

## Scope

Five audited defects in product-close/dispatch pipeline, confirmed by file:line audit and two live incidents on 2026-08-12.

## Defects & Fixes

### D1: BREAKS-LANES — pc_worker_alive false-dead without kill -0

**Root cause:** `leadv2-dispatch-product-close.sh:780` — `pc_worker_alive` for the `glm|kimi` case declared a worker dead from `meta.yaml status=complete/failed` + registry absence, but the `kill -0` pid check (line 773) only fired on the meta pid, which could be stale (the coder child that already exited while the parent `__supervise` process still held the GLM lock). Twice today a lane got `terminal=dead` while its GLM supervise kept running 30–50 min, blocking all other GLM lanes.

**Fix:** Added `_pc_process_alive()` — checks meta pid via `kill -0`, then falls back to `pgrep -f <handle>` to catch the supervise process that outlived the coder. This check runs BEFORE the complete/failed → dead decision. Added `_pc_reap_worker()` — sends TERM, waits 5s, then KILL to all handle-associated PIDs. Called at every `terminal=dead` path (both timeout exits + the complete/failed dead path) so the GLM lock is released before the ledger row is written.

**Proof:** `grep -c '_pc_process_alive\|_pc_reap_worker' leadv2-dispatch-product-close.sh` — function defs + call sites present; test suite verifies kill -0 fast path + pgrep fallback logic.

### D2: Worktree lanes review-blind — role file not found: critic

**Root cause:** `claude-subsession.sh:155-167` — role file resolution checked `$PROJECT_ROOT/.claude/agents/` and `$PROJECT_ROOT/.claude/roles/`, but lane worktrees don't materialize `.claude/agents/`. Every in-lane Phase-5 died with `role file not found: critic` and parked `all_review_arms_unavailable`.

**Fix:** Added a fallback in the `else` branch: derive the main checkout via `git rev-parse --git-common-dir`, then check `$_main_checkout/.claude/agents/<role>.md` and `.claude/roles/<role>.md` before giving up. `ROLE_SOURCE` is tagged `agents_worktree_fallback` / `roles_worktree_fallback` for diagnostics.

**Proof:** Test creates a fake worktree with `gitdir:` pointer and verifies the critic role is found via the common-dir derivation.

### D3: Architect prepass parks silently

**Root cause:** `leadv2-dispatch-code.sh:3099-3103` — after `ARCHITECT_PREPASS_ATTEMPTS` (2 × 420s) exhausted, the park was journaled as `architect_prepass status=parked` and logged to stderr, but no loud `prepass_parked` signal existed for supervise to surface, and no pending question was written.

**Fix:** Added `emit decision "prepass_parked ..."` with last failure reason + a `leadv2-ask.sh` call that writes a questions/ pending entry ("Retry or abort?") so `_pc_emit_pending_questions` surfaces it to the founder on the next poll.

**Proof:** `grep 'prepass_parked' dispatch-code.sh` — present; test verifies both the journal line and the ask.sh call.

### D4: Malformed/truncated meta.yaml → 4200s false wait

**Root cause:** `leadv2-dispatch-product-close.sh:786` — when meta.yaml was empty/truncated (status empty, pid empty), `pc_worker_alive` fell through to the default `return 0` (keep waiting), causing a full `LEADV2_PC_WORKER_MAX_WAIT_S` (4200s) false wait for a process that was already dead.

**Fix:** Added an explicit check: empty status + registry absence → `return 1` (dead) with a `worker_liveness=dead reason=empty_status_pid_gone` journal line. Also reordered the pid check to run BEFORE the status checks (via `_pc_process_alive`) so a pid-gone signal is primary, not secondary.

**Proof:** Test simulates empty-status meta.yaml and verifies the empty status + missing pid condition triggers dead classification.

### D5: Cosmetic — router_v2 reorder failure silent

**Root cause:** `leadv2-dispatch-code.sh:3589-3614` — when the router_v2 quota-gate resolver returned non-zero (`_qg_rc != 0`) or empty eligible list, the code fell through with no journal line, making refusal chains undebuggable.

**Fix:** Added two `emit decision "router_v2_reorder_failed ..."` lines — one for `rc != 0` (reason=resolve_nonzero) and one for empty eligible (reason=no_eligible_arms) — in the else path after the `if [[ ${_qg_rc} -eq 0 && -n "${_qg_eligible}" ]]` check.

**Proof:** `grep 'router_v2_reorder_failed' dispatch-code.sh` — present; test verifies both reason variants.

## Files Changed

| File | Lines changed |
|------|--------------|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | D1 + D4: added `_pc_process_alive`, `_pc_reap_worker`, reordered liveness logic, reaping at timeout paths |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | D3: prepass_parked signal + ask.sh question; D5: reorder_failed journal lines |
| `plugins/leadv2/scripts/claude-subsession.sh` | D2: worktree role-file fallback via git common-dir |
| `plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh` | New hermetic test suite (15 assertions) |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | Wired new suite into runner |

## Test Results

```
[PLUGIN-RELIABILITY-01] passed=15 failed=0
```

All existing core-offline suites pass except `test-codex-quota-guardrails` f2 (pre-existing, unrelated to this task).
