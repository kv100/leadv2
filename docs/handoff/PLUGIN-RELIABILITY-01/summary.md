# PLUGIN-RELIABILITY-01 — Summary

**Date:** 2026-08-12
**Branch:** worktree-PLUGIN-RELIABILITY-01
**Round:** 2 (fix round for review findings: 3 Critical + 4 High)

## Scope

Five audited defects in product-close/dispatch pipeline, confirmed by file:line audit and two live incidents on 2026-08-12. Round 1 passed its own test suite but the suite had zero behavioral coverage — all Criticals passed green via grep-on-source. Round 2 fixes the root causes and rewrites tests as behavioral.

## Round 2 Review Findings (all addressed)

### Critical 1+2: `_pc_process_alive` / `_pc_reap_worker` self-match via `pgrep -f "$handle"`

**Root cause:** Round 1 used `pgrep -f "$handle"` to find the supervise process. The close gate's own argv contains the handle (it's the 4th positional), so `pgrep` always self-matched → `_pc_process_alive` always returned alive → every GLM/Kimi lane burned the full 4200s ceiling. Worse, `_pc_reap_worker` SIGKILL'd the self-matched list including the close gate's own PID, killing it before it could write review-gate.md or the terminal ledger row. The unscoped pgrep could also match/kill unrelated processes (tail, grep) referencing the handle string.

**Fix:** Both functions now take `<run_dir>` instead of `<handle>` and read exact PIDs from spawn-record files only:
1. `run_dir/meta.yaml` → `pid:` (the glm-coder.sh start process)
2. `run_dir/pgid` (the `__run_child` process)
3. `<runs_dir>/.lock-<repo_hash>/pid` (the `__supervise` process, repo_hash from `run_dir/.lockref`)
4. `<runs_dir>/.lock-<repo_hash>/pgid` (child pid from lock perspective)

Self (`$$`) and parent (`$PPID`) are always excluded via an associative array. `_pc_reap_worker` deduplicates PIDs before sending TERM→5s→KILL. No `pgrep` is used anywhere.

### Critical 3: Synchronous `leadv2-ask.sh --timeout 1800` in prepass-park

**Root cause:** Round 1 called `leadv2-ask.sh` with `--timeout 1800` synchronously in `cmd_resolve`, blocking the dispatcher for up to 30 minutes before `exit 3`. The ask's answer was discarded and `exit 3` ran unconditionally.

**Fix:** Changed `--timeout 1800` to `--no-block`. This writes the V2 control-plane question record (visible in the questions dir for `_pc_emit_pending_questions`) and returns immediately. The dispatcher exits 3 without blocking. The prepass_parked journal line remains for supervise visibility.

### High 1: `claude-subsession.sh` `== "agents"` excludes `agents_worktree_fallback`

**Root cause:** Round 1's frontmatter-strip branch tested `ROLE_SOURCE == "agents"` only. The worktree fallback correctly set `ROLE_SOURCE="agents_worktree_fallback"` but the comparison missed it, so the raw YAML frontmatter was injected as the system prompt and zero skills were loaded.

**Fix:** Changed the comparison to `[[ "$ROLE_SOURCE" == "agents" || "$ROLE_SOURCE" == "agents_worktree_fallback" ]]`. Both use `agents/<role>.md` format with YAML frontmatter that must be stripped.

### High 2: Ask answer discarded + exit 3 unconditional

**Root cause:** Same as Critical 3 — the ask answer was never captured.

**Fix:** Resolved by switching to `--no-block` (no answer to discard; the question surfaces via the control plane for manual founder retry).

### High 3: Empty-status→dead has no run-age/meta-existence grace guard

**Root cause:** Round 1's empty-status dead path (`-z "${status}" && registry_alive == 0 → return 1`) could fire on the very first poll of a just-spawned worker that hadn't written meta.yaml yet, declaring it dead before it started.

**Fix:** Added a grace guard: if meta.yaml doesn't exist → `return 0` (keep watching). If it exists but is <30s old (by mtime) → `return 0`. Only after 30s with empty status → dead.

### High 4: Zero behavioral test coverage

**Root cause:** Round 1's test suite used grep-on-source assertions and hand-rewritten shell — none of the real functions were ever sourced or invoked.

**Fix:** Complete test rewrite. Tests source the real `_pc_process_alive` and `_pc_reap_worker` via `eval "$(awk ...)"` extraction and assert observable behavior:
- Live meta pid → alive; dead → dead
- Live pgid → alive; dead → dead
- Live lock_dir/pid → alive; dead → dead
- **Self pid ($$) excluded — no self-match** (the round-1 Critical)
- Parent pid ($PPID) excluded
- _pc_reap_worker kills the victim process, does NOT kill self/parent
- Reap from lock_dir/pid works
- No live processes → no-op
- agents_worktree_fallback frontmatter stripped correctly
- Grace guard: fresh meta → not dead; old meta → dead-eligible

## Files Changed

| File | Changes |
|------|---------|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | D1: `_pc_process_alive` + `_pc_reap_worker` rewritten to pid-file-only (no pgrep), call sites pass `run_dir`. D4: grace guard (meta existence + 30s mtime check) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | D3: `--timeout 1800` → `--no-block` (fire-and-forget question write) |
| `plugins/leadv2/scripts/claude-subsession.sh` | D2: frontmatter-strip comparison accepts `agents_worktree_fallback` |
| `plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh` | Complete rewrite: 21 behavioral assertions (source real functions, spawn fake processes, assert kill behavior) |

## Test Results

```
[PLUGIN-RELIABILITY-01] passed=21 failed=0
```

Syntax checks: all three modified scripts pass `bash -n` (rc=0).
Related suites: test-no-work-terminal (42/1 — the 1 failure is pre-existing "revived waited to timeout"), test-dwr-resume (20/0), test-question-delivery-ownership (10/0) — all rc=0.
