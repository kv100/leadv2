# Test escape: `test-dispatch-ledger-task-id.sh` case C3 (instance #6)

**Date:** 2026-08-24 22:00–22:0x EEST
**Escaped run:** `~/.claude/cache/glm-runs/260824-220057-N7F-C3-BOUND-ID-57ed`
**Escaped lane:** `N7F-C3-BOUND-ID` (this worktree, branch `worktree-N7F-C3-BOUND-ID`)
**Worker model:** glm-5.2 via `claude -p` (session `7e520983-c888-4322-8072-abbd77a75ea7`)

## What happened

The sibling lane `PREPASS-PROVIDER-FALLBACK-01-R3` ran
`plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh` with its WIP
dispatcher in place. Case C3 (dispatch WITH a bound `--task-id` and a mission
H1 that names a different task) escaped a real GLM worker — same trigger and
same parent chain as instances #4 (`test-prepass-repo-parity.sh`) and #5
(case C1 of this same suite, lane `a9247cab`).

The escaped worker's mission is the C3 fixture verbatim:

```
# N7F-C3-WRONG-NAME — must NOT win over the bound --task-id
body text, dispatch-ledger-task-id c3 79466 1787598054
```

(`$$`=79466, epoch 1787598054 = 22:00:54 EEST, seconds before the worker
started at 19:00:57Z = 22:00:57 EEST.)

## Evidence

Parent chain of the escaped session (captured from inside it):

```
$ ps -o pid,ppid,command -p 4635
  PID  PPID COMMAND
 4635 4536 bash .../worktrees/PREPASS-PROVIDER-FALLBACK-01-R3/plugins/leadv2/scripts/glm-coder.sh __run_child /Users/kostiantyn.vlasenko/.claude/cache/glm-runs/260824-220057-N7F-C3-BOUND-ID-57ed
$ ps -o pid,ppid,command -p 4536
  PID  PPID COMMAND
 4536    1 bash .../worktrees/PREPASS-PROVIDER-FALLBACK-01-R3/plugins/leadv2/scripts/glm-coder.sh __supervise /Users/kostiantyn.vlasenko/.claude/cache/glm-runs/260824-220057-N7F-C3-BOUND-ID-57ed
```

Session env still carries the hermetic fixture roots, and the fixture is
already gone (suite trap `rm -rf` fired — the spawning test finished):

```
$ echo $CLAUDE_PROJECT_ROOT
/var/folders/.../T/dispatch-ledger-task-id-79466-1787597986.DIgzAm/repo
$ ls -d /var/folders/.../dispatch-ledger-task-id-79466*
(eval):1: no matches found
```

## Live observation: the bound task-id DID win (the property C3 protects)

Independent of the (now-deleted) fixture ledger row, the binding is visible in
what the escape named things:

- worktree: `.claude/worktrees/N7F-C3-BOUND-ID` — the bound `--task-id`, not
  the mission H1 `N7F-C3-WRONG-NAME`;
- glm run dir + `meta.yaml`: `260824-220057-N7F-C3-BOUND-ID-57ed`,
  `repo: N7F-C3-BOUND-ID`.

Contrast with instance #5 (case C1, NO `--task-id`): that lane got a
contentless hash name (`a9247cab`). So identity selection behaved per rule 1
(bound id wins over prose) / rule 3 (no invented name) even on the escaped
path.

UNVERIFIED from inside the worker: whether the fixture ledger's reserve row
itself carried `task_id=N7F-C3-BOUND-ID` — the fixture dir was deleted before
the worker could read it. Engine-side: the suite's C3 assertion
(`plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh`, "C3:
--task-id PRESENT ... task_id == the --task-id") is the canonical check.

## Root cause (carried over from instance #5, UNVERIFIED from inside)

The suite stubs `LEADV2_DISPATCH_SUBSESSION_BIN` with a fake launcher that
prints a PID and exits, yet a real session escaped — same suspected
un-stubbed `LEADV2_DISPATCH_GLM_BIN` root as `duplicate-caller-race.md`.
The escape only reproduces from the sibling lane's WIP dispatcher path, not
from stock main (stock parks/exit-3s on prepass failure per instance #4).

## Outcome

Escaped worker did no mission work (the mission is a test fixture, not a real
task). Docs-only commit on its own lane branch, per the standing precedent
for escaped workers (instances #4 and #5).
