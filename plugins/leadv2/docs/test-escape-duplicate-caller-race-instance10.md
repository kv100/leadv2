# Test escape: `test-dispatch-duplicate-caller-race.sh` (instance #10)

**Date:** 2026-09-11 03:11 EEST (lane anchor commit `a1b16f0b`, 03:11:34+03:00)
**Escaped lane:** `worktree-6141f5bb` (this worktree), dispatch id `dispatch-6141f5bb`
**Worker model:** glm-coder harness (`LEADV2_COSTLOG_ARM=glm-coder:glm-flash`)
**Precedent:** instance #9 (2026-09-06, lane `dispatch-a7f74519`, this same suite)
and the 2026-08-24 original it cites. Same suite escaping again, five days
later, by the same mechanism.

## What happened

This worker's mission string is verbatim the fixture mission:
`docs-only: duplicate-caller-race 88684 1789085480` — pid 88684 is the suite
shell, epoch 1789085480 = 2026-09-11 03:11:20 EEST; this lane's anchor commit
landed 14 s later (03:11:34). `ps -p 88684` is empty at probe time: the
fixture-owner is dead, no live runner to wait on.

The env confirms the escape live (probed 03:2x EEST):

```
LEADV2_PROJECT_ROOT=/var/folders/.../dispatch-race-88684-1789085480.yIa4Yn/repo
LEADV2_DISPATCH_SUBSESSION_BIN=/var/folders/.../dispatch-race-88684-1789085480.yIa4Yn/fake-claude-subsession.sh
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE=/var/folders/.../dispatch-race-88684-1789085480.yIa4Yn/terminal-ledger.jsonl
LEADV2_DISPATCH_RACE_DELAY=0.3
LEADV2_JOURNAL_BIN=/bin/true   LEADV2_ROUTER_V2=0   LEADV2_LANE_SHAPE=off
```

`RACE_DELAY=0.3` → this worker descends from **racer A's** winning dispatch
(suite lines 117 vs 120). `LEADV2_DISPATCH_GLM_BIN` is absent from the env →
the launch step fell back to the real glm-coder, exactly the instance #9
mechanism. FOREIGN-PROJECT-ROOT-GUARD-01 discarded the fixture
`LEADV2_PROJECT_ROOT` and rooted the lane in the real leadv2 checkout — hence
a real worktree, real anchor commit, real registry row: this lane.

## Debris shape (new versus #9)

The fixture tmpdir survived, but **partially emptied** — only the fixture
`repo/` tree is left (dir and `repo/` mtime 03:12, nothing written since; the
terminal ledger, cache dir, fake launcher, and both racers' output files are
gone, and the winner's terminal row is therefore unrecoverable from the
fixture side). The suite's own `trap 'rm -rf "$TMPDIR_ROOT"' EXIT`
(suite line 49) provably did not run to completion — consistent with the
known macOS trap semantics (a trapped signal defers behind a foreground
child; an untrapped kill drops EXIT cleanup entirely). So the escape now
leaves TWO debris classes: the phantom lane (worktree + handoff + registry
row) and a half-cleaned `/var/folders` fixture dir.

## Why the suite ran at 03:11 tonight

The suite is trigger-marked `run-all-triggers: leadv2-dispatch-code`
(suite line 20). Commit `f86a7732` (02:27, 44 lines in
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, premise-gate fix) made any
changed-scope run-all on that diff select this suite — and every engine-side
selection escapes. Any lane that touches dispatch-code.sh re-arms this trap.

## Root cause — unchanged since #9, re-verified on this checkout

```
$ grep -c GLM_BIN plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh
0
$ grep -n "GLM_BIN" plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh
35:export LEADV2_DISPATCH_GLM_BIN=/usr/bin/false
```

The 2026-08-24 recommendation (stub `GLM_BIN`) is in the sibling suite
(`:35`) but still not in this one — one more escape after #9 said the same.
Also absent from `_dispatch`'s env: `LEADV2_FOREIGN_ROOT_GUARD=0` (the
fixture-root discard is the actual hijack step) and the
`docs/handoff/<sig8>/context.yaml` fixture (2026-09-06 fix hint).

## Family index note

`plugins/leadv2/docs/test-escape-duplicate-caller-race.md` — the base doc #9
cites as holding the original 2026-08-24 write plus instances #4–#8 — is NOT
tracked on this branch: `git ls-files | grep test-escape-duplicate-caller-race`
returns only instance9, and `git log -- <base doc>` is empty. Either it lives
uncommitted in some worktree or was never committed; treat #9 as the only
durable predecessor on main.

## Action from inside the escape

None engine-side (standing policy from #6/#7/#8/#9: the escaped worker does
no mission work; this document is the deliverable, committed docs-only on the
lane branch). Follow-up for the owning lane — unchanged from #9 and still
pending after two escapes: add `LEADV2_DISPATCH_GLM_BIN=/usr/bin/false`
(plus CODEX/KIMI siblings, cf. `test-dispatch-ledger-task-id.sh:35`) AND
`LEADV2_FOREIGN_ROOT_GUARD=0` to `_dispatch`'s env, or stop trigger-selecting
this suite until that lands.
