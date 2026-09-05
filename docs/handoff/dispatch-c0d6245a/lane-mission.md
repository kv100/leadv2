T16 — hooks/infra hygiene round (LEAD-FINAL-FIXES-01, last open T-task) + four defects measured live this session. Base: leadv2 main (ce914d3). Each fix gets a test or a verifiable probe; bash -n everything touched.

ORIGINAL T16 LIST:
1. codex-direct-exec-guard: parse `VAR=1 cmd` env-prefix form (guard currently misses inline env overrides).
2. Deregister the 2 supervisor-only hooks from registration (supervisor retired permanently).
3. engine-flag-row-inject: collapse to ONE registration (currently duplicated).
4. docs-truth-inject: refresh/auto-update the last-verified stamp (it fails the gate at >7d even when content is current — seen live this session on open-threads-rules.md).
5. feature-liveness-inject -> summary form.
6. analysis-only fast-path for continuation/promise-guard.
7. Merge drift-warn with one-copy check.
8. Delete test-supervisor-fanout-guard.sh.

SESSION-MEASURED DEFECTS (all four reproduced today; fix root causes):
9. HOOK-EDIT-SPAWN-POISON-01: live plugin-cache sync copies hook files mid-edit; a worker session spawning at that moment dies at first prompt on a syntax-broken snapshot (killed lane 75a42e3a on 08-26). Fix: sync only bash -n-clean files (syntax gate inside the sync step; on failure keep the previous cached copy and log).
10. LANE-DEREGISTRATION: closed/terminal lanes never leave docs/leadv2/active.yaml, so lead_session_lane_cap refuses new dispatches until a human prunes (hand-pruned 3x on 08-26/27). Fix: dispatch_terminal path (and product-close exit trap) must remove the lane's registration row (tombstone-consistent with T18 abandon path); add a test: register -> terminal -> row gone.
11. WORKTREE-RESURRECTOR-02: anchor worktrees + worktree-* branches get re-created after removal (20 dirs / 132 branches accumulated). Find the re-creator (candidate: SessionStart lane-recovery scanning stale journals/handoff dirs and re-adding worktrees for non-live lanes) and gate it: recovery may only re-create a worktree for a lane that is BOTH registered in active.yaml AND has a live PID. Add a probe/test.
12. BOARD-HEALER overreach (PE side observed, fix the shared hook here in canonical): the open-threads tail/head regenerator restored ARCHIVED content into the board (undid a founder-ordered triage) and silently consumed a hand-written [x] row. Fix: the regenerator may rewrite ONLY the marked GENERATED blocks (between BEGIN/END markers), never insert content outside them, never delete hand rows; archive-consumption of [x] rows must append to open-threads-archive.md in the same write. Add a test with a synthetic board.

Constraints: canonical repo only (plugins/leadv2/...); no behavior change beyond the listed items; every new guard fail-open on infrastructure absence; commit on the lane branch with per-item message lines.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c0d6245a" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.