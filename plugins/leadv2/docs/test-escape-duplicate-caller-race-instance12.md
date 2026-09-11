# Test escape: `test-dispatch-duplicate-caller-race.sh` (instance #12)

**Date:** 2026-09-11 18:36:31 EEST (mission epoch 1789140991; glm run
`260911-183742-leadv2-3578`)
**Escaped lane:** `FORKPASS-810129d0` / ask-channel `dispatch-cc6aa5b1` —
running in the MAIN leadv2 checkout, not a dedicated worktree
**Worker model:** glm-5.3-flash via the REAL `glm-coder.sh` (run `meta.yaml`:
`endpoint: https://api.z.ai/api/anthropic`, `model: glm-5.3-flash`, supervised
pid 87058 — dead while `status: running`, see below)
**Precedent:** #9 (2026-09-06, a7f74519), #10 (double-assigned by parallel
lanes: 2026-09-07 87b20053 and 2026-09-11 6141f5bb), #11 (2026-09-10,
83b30201) — sixth run of the family since 2026-08-24.

## What happened

This worker's mission string is verbatim the fixture mission:
`docs-only: duplicate-caller-race 10908 1789140991` — pid 10908 (the
fixture-owner shell; `ps -p 10908` returns nothing, the suite run is
finished), epoch 1789140991 = 2026-09-11 15:36:31 UTC (18:36:31 +0300). The
suite's tmpdir carried the same stamp
(`/var/folders/.../T/dispatch-race-10908-1789140991.CSiYH1/`) and the
supervised glm run started 18:37:42 local (`meta.yaml` `run_id:
260911-183742-leadv2-3578`) — 71 s after the mission stamp.

Env proof (live in this worker):

```
LEADV2_DISPATCH_SUBSESSION_BIN=<tmpdir>/fake-claude-subsession.sh
LEADV2_DISPATCH_RACE_DELAY=0
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE=<tmpdir>/terminal-ledger.jsonl
LEADV2_DISPATCH_E2E_GATE=0  LEADV2_DISPATCH_REVIEW_GATE=0  LEADV2_DISPATCH_ARCHITECT_GATE=1
LEADV2_DISPATCH_CODEX_BIN=<repo>/plugins/leadv2/scripts/codex-task.sh
LEADV2_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2
```

`LEADV2_DISPATCH_GLM_BIN` is ABSENT from the env (`env | grep -c
'^LEADV2_DISPATCH_GLM_BIN='` → 0), so `leadv2-dispatch-code.sh` fell back to
the real `glm-coder.sh`, which supervised this `claude -p` child.
`LEADV2_PROJECT_ROOT` is pinned to the REAL repo root, not the fixture —
FOREIGN-PROJECT-ROOT-GUARD-01 discarding the fixture root is the escape
mechanism, live. The tmpdir is GONE at doc time (suite exit cleaned it, as in
#11 — second consecutive run contradicting #10's half-emptied observation),
so the terminal-ledger row for this very dispatch is gone; the surviving
artifact is the glm run dir
`~/.claude/cache/glm-runs/260911-183742-leadv2-3578/`. Its supervisor pid
87058 is already dead while `meta.yaml` still says `status: running` — a
supervised child outliving its supervisor, so nothing will harvest or stop
this run except the worker itself.

## New since instance #11

1. **The seam is still open at every ref.** Stub count for
   `GLM_BIN|CODEX_BIN|KIMI_BIN` in the suite: 0 at origin/main, 0 at local
   main, 0 at this checkout's HEAD (`grep -c` artifacts). The
   `# run-all-triggers: leadv2-dispatch-code` marker is still at `:20`, so
   the suite remains on the changed-scope hot path.
2. **Two real GLM workers in one escape window.** Contemporaneous run
   `260911-183622-b7504d3f-4678` started 18:36:22 (9 s BEFORE this worker's
   mission stamp), `model: glm-5.3-flash`, `status: failed`, cwd
   `/private/var/folders/.../tmp.TEAjjq8A7k/myrepo/.claude/worktrees/b7504d3f`
   — a real glm worker dispatched INSIDE a fixture tmp worktree. Plausibly
   the race fixture's second dispatcher arm (this suite simulates two
   concurrent callers), escaping in parallel with the arm that became this
   worker. UNVERIFIED that the b7504d3f run belongs to the same suite
   invocation (its tmpdir prefix differs from `dispatch-race-*`). If real,
   the per-escape cost is two GLM spawns, not one.
3. **Suite flags drifted, the missing guard is the constant.** This run
   carried `LEADV2_DISPATCH_ARCHITECT_GATE=1` (#11 recorded 0) — the suite
   evolves, the one-line bin stub still hasn't landed.
4. **Docs fragmentation from #11 is resolved.** `git ls-files` shows the
   base doc + instance9/10/11 all tracked on main. This document continues
   the series as a docs-only commit.
5. **This phantom left no registry row.** Neither `FORKPASS-810129d0` nor
   `cc6aa5b1` appears in `~/.claude/leadv2-state/leadv2/active.yaml` — and
   the shared main checkout's HEAD visibly flipped main →
   `FORKPASS-810129d0` → main under this session within minutes. The lane
   exists only as that transient branch flip plus this document.

## Action from inside the escape

None engine-side (standing policy from #6–#11: the escaped worker does no
mission work; this document is the deliverable, committed docs-only). The fix
remains the one-liner from #9/#10/#11 — copy the guard at
`test-dispatch-ledger-task-id.sh:35-37` into
`plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh`:

```bash
export LEADV2_DISPATCH_GLM_BIN=/usr/bin/false
export LEADV2_DISPATCH_CODEX_BIN=/usr/bin/false
export LEADV2_DISPATCH_KIMI_BIN=/usr/bin/false
```

(or set `LEADV2_FOREIGN_ROOT_GUARD=0` in the `_dispatch` env, or stop
trigger-selecting the suite until one of those lands). Fourth escape in six
days on an identical, thrice-documented gap; recurring GLM burn plus a
phantom lane per run — now apparently two workers per window.
