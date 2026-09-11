# Test escape: `test-dispatch-duplicate-caller-race.sh` (instance #11)

**Date:** 2026-09-10 16:04 EEST (glm run `260910-160349-83b30201-6797`)
**Escaped lane:** `worktree-83b30201` (this worktree), ask-channel `dispatch-83b30201`
**Worker model:** glm-5.3-flash via the REAL `glm-coder.sh` (run `meta.yaml`:
`endpoint: https://api.z.ai/api/anthropic`, `model: glm-5.3-flash`, supervised
child pid 38100)
**Precedent:** #9 (2026-09-06, lane a7f74519), #10 (2026-09-07, lane
87b20053), original escape 2026-08-24 — same suite, same gap, fourth run of
the family.

## What happened

This worker's mission string is verbatim the fixture mission:
`docs-only: duplicate-caller-race 68745 1789045372` — pid 68745 (the
fixture-owner shell; `ps -p 68745` returns nothing, the suite run is
finished), epoch 1789045372 = 2026-09-10 13:02:52 UTC (16:02:52 +0300). The
suite's tmpdir carries the second-earlier stamp
(`/var/folders/.../T/dispatch-race-68745-1789045371.2FcVJR/`) and the
supervised glm run started 16:03:49-50 local (`ps`: `glm-coder.sh __supervise
.../glm-runs/260910-160349-83b30201-6797`) — 57 s after the mission stamp.

Env proof (live in this worker):

```
LEADV2_DISPATCH_SUBSESSION_BIN=<tmpdir>/fake-claude-subsession.sh
LEADV2_DISPATCH_RACE_DELAY=0
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE=terminal-ledger.jsonl
LEADV2_DISPATCH_E2E_GATE=0  LEADV2_DISPATCH_ARCHITECT_GATE=0  LEADV2_DISPATCH_REVIEW_GATE=0
```

`LEADV2_DISPATCH_GLM_BIN` is ABSENT from the env, so
`leadv2-dispatch-code.sh` fell back to the real `glm-coder.sh`, which
supervised this `claude -p` child. The suite cleans its TMPDIR on exit (the
`dispatch-race-68745-1789045371.2FcVJR` directory no longer exists), so the
terminal-ledger row for this very dispatch is gone; the surviving artifact is
the glm run dir `~/.claude/cache/glm-runs/260910-160349-83b30201-6797/`
(`meta.yaml` names this lane and model; its `journal.jsonl` contains this
document's own first thinking block).

## Engine-side state on 2026-09-10

Stub count for the escape seam is 0 at every relevant ref:

```
$ git show origin/main:plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh | grep -c "GLM_BIN\|CODEX_BIN\|KIMI_BIN"
0          # origin/main = a3ac0067
$ git show main:plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh | grep -c "GLM_BIN\|CODEX_BIN\|KIMI_BIN"
0          # local main = 7aaefef7
$ grep -c "GLM_BIN\|CODEX_BIN\|KIMI_BIN" plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh
0          # this lane HEAD f552047a (only LEADV2_DISPATCH_SUBSESSION_BIN at :87)
```

New since instance #10: the suite grew a
`# run-all-triggers: leadv2-dispatch-code` header
(SUITE-SELECTION-COVERS-140-OF-390-01), so `run-all.sh --scope changed` now
SELECTS it whenever `leadv2-dispatch-code` changes — before that marker it
only ran under `--scope all`. Every such selection is another real GLM
spawn. The one-line stub is no longer a rare --scope-all event; it is on the
changed-scope hot path.

## Instance #10's evidence never reached main

Commit `9b650174` (`test-escape-duplicate-caller-race-instance10.md`) exists
ONLY on branch `worktree-87b20053`: `git merge-base --is-ancestor 9b650174
origin/main` is false, and it is absent from this lane's HEAD too — while its
open-threads UPDATE did reach this lane via merge. The escape record is
fragmenting across lane branches: the thread line survives, the cited
evidence file is unreachable from main. This document is committed docs-only
on its own lane branch and has the same fate risk — merge the docs, not just
the threads.

## Action from inside the escape

None engine-side (standing policy from #6–#10: the escaped worker does no
mission work; this document is the deliverable, committed docs-only on the
lane branch). The fix remains the one-liner from #9/#10 — copy the guard at
`test-dispatch-ledger-task-id.sh:35-37` into
`plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh`:

```bash
export LEADV2_DISPATCH_GLM_BIN=/usr/bin/false
export LEADV2_DISPATCH_CODEX_BIN=/usr/bin/false
export LEADV2_DISPATCH_KIMI_BIN=/usr/bin/false
```

Third suite escape in five days on an identical, thrice-documented gap; the
cost is now recurring GLM burn plus a phantom lane per run.
