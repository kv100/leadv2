# Test escape: `test-dispatch-ledger-task-id.sh` case C1 (instance #8)

**Date:** 2026-09-04 16:21 EEST (glm run `260904-162104-3c0940cd-0355`)
**Escaped lane:** `worktree-3c0940cd` (this worktree)
**Worker model:** sonnet via `claude -p --model sonnet --effort low`
**Precedent:** instances #5 (C1, lane a9247cab), #6 (C3, N7F-C3-BOUND-ID),
#7 (C2, worktree-b2ffe12a). This instance adds one NEW fact, recorded below.

## What happened

The engine-side suite run (test shell PID **99254**, fixture tmpdir
`dispatch-ledger-task-id-99254-1788527789.ZcoLyw`, cwd
`.../worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/plugins/leadv2/scripts/tests`)
reached case C1 — mission H1 `# N7F-C1 — case one heading, dispatch-ledger-task-id
99254 1788527870`, no `--task-id`. The mission string is verbatim this worker's
prompt. A real worker launched instead of the spawn staying hermetic.

## Root cause — re-confirmed, plus the new fact

Same verdict as #5/#6/#7:

1. `LEADV2_DISPATCH_SUBSESSION_BIN` IS set in this worker's env to the fixture's
   `fake-claude-subsession.sh` — the stubbed seam is not the escape route.
2. `LEADV2_DISPATCH_GLM_BIN` is ABSENT from this worker's env (probed live:
   `env | grep LEADV2_DISPATCH` shows SUBSESSION_BIN only).
3. `leadv2-dispatch-code.sh` fell back to sibling `glm-coder.sh`, which supervised
   a real `claude -p` child (parent chain below).

**New fact:** the GLM_BIN hermeticity fix ALREADY exists on current main —
`tests/test-dispatch-ledger-task-id.sh:34` carries
`export LEADV2_DISPATCH_GLM_BIN=/usr/bin/false` (+ CODEX/KIMI siblings, and a
FAKE_GLM export at :123). The escape fired because the suite ran from the
`DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01` worktree, whose copy of the test
contains ZERO occurrences of `GLM_BIN` (grep-verified this session) — a stale
pre-fix copy. So the remaining exposure is not an unfixed suite but
**worktrees pinned to pre-fix branches re-running old suites**; the earlier
instances' engine-side fix is effective on current main and needs no change
here.

## Evidence

Parent chain of this session (captured from inside the escape):

```
26939 86448  (worker shell)
86448 86113  claude -p '# N7F-C1 — case one heading, dispatch-ledger-task-id 99254 1788527870 ...' --model sonnet ...
86113 85775  bash .../worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/plugins/leadv2/scripts/glm-coder.sh __run_child ~/.claude/cache/glm-runs/260904-162104-3c0940cd-0355
85775     1  bash .../worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/plugins/leadv2/scripts/glm-coder.sh __supervise ~/.claude/cache/glm-runs/260904-162104-3c0940cd-0355
```

Fixture-owner probe: `ps -p 99254` → `bash test-dispatch-ledger-task-id.sh`;
`lsof -p 99254` cwd → the DARK-SUITES worktree's tests dir (i.e. the in-flight
suite reads DISPATCH_SH from that pre-fix checkout — an edit from inside this
escape could not affect the run anyway).

## Action from inside the escape

None engine-side (same policy as #6/#7: the engine session owns the suite; the
in-flight run already dispatched). This document is the deliverable. Suggested
follow-up for the owning lane: rebase/merge `DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01`
onto main so its test copy carries the :34 GLM_BIN guard, or sweep live worktrees
for suites lacking the guard before running them.
