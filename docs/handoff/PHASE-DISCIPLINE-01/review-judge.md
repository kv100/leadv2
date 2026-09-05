# PHASE-DISCIPLINE-01 — judge review (round 3, deciding arm)

> Written to scratchpad: `.claude/hooks/guard-worktree-scope.sh` BLOCKED the write to
> `/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/PHASE-DISCIPLINE-01/review-judge.md`
> (cwd is persona-engine). Lead: copy this file to that path.

## VERDICT: FAIL

D4 (the #1 item) is **CLEAN**. `leadv2-gate1-prompt.sh:197` heavy_like branch precedes
DRY_RUN(:249)/BOT_MODE(:258)/timeout-read(:290) and every arm exits. Measured rc:
Heavy+DAEMON+SEC=0 → 1 · Heavy+DRY_RUN → 1 · Heavy+BOT_MODE → 1 ·
Standard+risk=safety_publish_payments+DRY_RUN → 1 · Standard+DAEMON+SEC=0 → 2.
The zero-timeout auto-accept is Standard-only. Declared negative control run by me (heavy branch
made DRY_RUN-bypassable) → suite rc=1, 11 pass/1 fail. phases.md aligned;
`LEADV2_GATE1_HEAVY_TIMEOUT_SEC` fully purged. Arbiter rc 64-67 untouched, symlink fixture kills
its mutation. `bash -n` clean on all 5 changed scripts.

### CRITICAL 1 — dispatch door bricked in 4 of 6 configs
`leadv2-dispatch-code.sh:3502` passes `${scope:+--${scope}}` → `--full`.
`leadv2-phase-record.sh:720` `cmd_assert` only knows `--pre-build`; `--*` → `exit 4` → guard
`return 1`. Measured guard rc: explicit warn/Light **1** · explicit warn/Standard **1** ·
explicit 1/Standard **1** (config_error, remedy lines never print) · unset/**Light 1** ·
unset/Standard 1 (correct) · `=0` 0. D3 says "Light unaffected" and off_limits pins `warn`
semantics — both violated. Fix: emit the flag only when `pre-build`, or add a no-op `--full)` arm.

### CRITICAL 2 — Slice B shipped default-on
`leadv2-backlog-pump.sh:742` `LEADV2_BACKLOG_PUMP_ADOPT:-1`, tried at :~197 **before** the
Slice A refusal. D5 scopes this task to Slice A; Slice B "needs Gate-1 answer". Live pump
behaviour is a detached full-cycle child, not the declared negative control ("refusal, zero
worker spawn"). Default to `:-0`. Flag documented nowhere (2 read sites).

### CRITICAL 3 — coverage
No test for `_pump_classify`, the `phases_required` refusal, `_pump_adopt_full_cycle`, or the D3
guard in any mode; the only new pump test is `tree_state_probe_failure`. No suite declares a
negative control. `tests/run-all.sh:110-114` maps stem→`test-<stem>.sh`: all six changed scripts
have **ABSENT** stem-matched suites → `--scope changed` selects none of them.

### HIGH 4 — Phase-4 re-entry join unproven
gate1 records under receipt sig8 = **intake** mission digest; the guard asserts sig8 = **build**
mission digest. `test-gate1-discipline.sh:98-112` hand-seeds `cafef00d` then asserts `cafef00d`
— tautological. `leadv2-session-runner.sh` never invokes dispatch-code.

### HIGH 5 — `leadv2-gate1-prompt.sh:158`
`grep -l | head -1` picks an arbitrary receipt when a task_id has >1; `$task_id` raw in an ERE.

### MEDIUM
6. `:225-232` comment claims a headless Heavy caller "hangs (park, not accept)"; real behaviour is
instant rc=1 at EOF under `set -e`, with **no `_gate1_emit_ledger`** — D4's journal contract has a
hole on that exact path.
7. `:~148` `pid=$!` is the subshell/`env` pid; if `setsid` forks, the registered lane pid is dead.
8. Journal shape differs: dispatch `task=<sig8>` vs pump `task=<tid> sig8=<sig8>`.

### LOW
9. Diff bundles FP-01/FP-02 (`freepool-arm.yaml` role_rank roster, `/leadv2mode`, quota-live) into
this review; roster ordering is off_limits text — review it on its own row.

**Contradiction scan:** kill switch `=0` OK · arbiter rc numbering OK · task-judge lexicon
untouched · WIP=1 intact · no new daemon *except* the adopt-spawned runner (Crit 2) ·
`LEADV2_BACKLOG_PUMP_ADOPT` undocumented · `--full` flag does not exist (Crit 1). shellcheck not
installed; `bash -n` used instead.

**Suites (raw):** admission-class 21/0 · backlog-pump 21/0 · gate1-discipline 12/0 ·
freepool-model-selector 25/0 · route-arbiter-symlink 3/0. All green — and all invisible to CI.

DELIVERABLE_COMPLETE
