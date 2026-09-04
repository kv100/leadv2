# TEST-ESCAPE — test-dispatch-ledger-task-id.sh C2 spawns a real GLM worker (instance #7)

**Escaped worker:** this lane (worktree-b2ffe12a), run `260824-220411-b2ffe12a-42da`.
**Date:** 2026-08-24 22:04 EEST. **Precedent:** instance #6 (commit 405f697, lane
worktree-e0259db2, case C1, 1 min earlier — root cause VERIFIED there), instance #5
(8a18fce), instance #4 (test-prepass-repo-parity, 99ce70f), TEST-ESCAPE-DUPLICATE-
CALLER-RACE (33b3769). This instance adds nothing new on root cause — it is the same
hole firing from case C2, recorded so the fix's blast radius covers the C2 dispatch
site too.

## What happened

The engine-side suite run (test shell PID **12848**, fixture tmpdir
`dispatch-ledger-task-id-12848-1787598188.EUafLP`) reached case C2 — mission with no
H1 and no `--task-id`, asserting the reserve row invents no lane name
(`plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh:187-199`):

```bash
c2_mission="plain mission body, no heading line, dispatch-ledger-task-id c2 $$ $(date +%s ...)"
...
"${DISPATCH_SH}" "${c2_mission}" --protected --spawn --kind docs
```

The mission string is exactly what this worker received as its prompt heading
(`... dispatch-ledger-task-id c2 12848 1787598244`; 1787598244 = 22:04:04 EEST,
seconds before the run dir was created at 22:04:11). A real GLM worker (this
session) launched instead of the spawn staying hermetic.

## Root cause — re-confirmed from inside this worker

Same verdict as instance #6, independently re-probed:

1. `LEADV2_DISPATCH_SUBSESSION_BIN` **IS set** in this worker's env to the fixture's
   `fake-claude-subsession.sh` (fixture tmpdir path, verbatim):
   `.../T/dispatch-ledger-task-id-12848-1787598188.EUafLP/fake-claude-subsession.sh`
   — the stubbed seam is not the escape route.
2. `LEADV2_DISPATCH_GLM_BIN` is **absent** from the worker's full environment.
3. `leadv2-dispatch-code.sh:3361` falls back to the sibling `glm-coder.sh`, which
   supervised a real `claude -p` child (parent chain below).
4. The test's C2 invocation (`:193-199`) stubs `SUBSESSION_BIN`, gates, journal,
   router, arms, lane shape — everything except the GLM launcher seam.

Instance #6's suggested engine-side fix already covers this site (fake
`LEADV2_DISPATCH_GLM_BIN` on every `--spawn` call: C1/C2/C3 at 172/200/229 and F4 at
334/361). Not applied from inside the escape — the engine session owns it; the
in-flight suite reads `DISPATCH_SH` from its own checkout, so an edit here cannot
affect a run already past dispatch anyway.

## Evidence

Parent chain of this session (captured from inside the escape; note the dispatcher
this time ran from lane worktree `44687dea`, not PREPASS-…-R3 as in instance #6 —
the suite runs from whatever worktree hosts it):

```
68295 68116  claude -p 'plain mission body, no heading line, dispatch-ledger-task-id c2 12848 1787598244' ...
68116 67906  bash .../worktrees/44687dea/plugins/leadv2/scripts/glm-coder.sh __run_child .../glm-runs/260824-220411-b2ffe12a-42da
67906     1  bash .../worktrees/44687dea/plugins/leadv2/scripts/glm-coder.sh __supervise .../glm-runs/260824-220411-b2ffe12a-42da
```

Run metadata (`~/.claude/cache/glm-runs/260824-220411-b2ffe12a-42da/meta.yaml`):
`endpoint: https://api.z.ai/api/anthropic`, `model: glm-5.2`, `status: running`.
Real provider traffic: 23 `PROVIDER_RETRY` lines in `progress.log` (3.4 KB at
capture) — the escape burns real GLM quota against a fixture mission.

Side-effects inventory (real, outside the fixture tmpdir, which was already cleaned
up by the suite's temp trap before this worker captured anything in it): the glm-run
dir above, worktree `.claude/worktrees/b2ffe12a` + lane branch `worktree-b2ffe12a`,
this GLM session. The ledger logic under test behaved per spec (C2 asserts
`"task_id":""` with no invented lane name) — the defect is purely the spawn
side-effect.

## Worker conduct

No mission work was performed: the mission is a fixture string, not a task. The
worker captured its own escape evidence, wrote this doc, and committed docs-only on
its own lane branch — the instance #5/#6 precedent. Deliberately NOT run:
`test-dispatch-ledger-task-id.sh` itself, because re-running the unfixed suite would
manufacture escape instance #8; docs-only change carries no shell/python surface to
syntax-check.

---

# TEST-ESCAPE — instance #8: F4b fixture (bound --task-id OPS-42) escapes; task-id leaks into real worktree/branch names

**Escaped worker:** this lane (worktree **OPS-42**, branch `worktree-OPS-42`), run
`260824-220144-OPS-42-470e`. **Date:** 2026-08-24 22:01 EEST. **Precedent:** #5
(8a18fce), #6 (405f697, 038f1c6, 4bcee29 — root cause VERIFIED), #7 (cc7c79f).

## What happened

The spawning suite run (test shell PID **79466**, fixture tmpdir
`dispatch-ledger-task-id-79466-1787597986.DIgzAm`) reached case F4b — the guard
case asserting that a dispatch WITH `--task-id OPS-42` still resolves identity via
tasks.yaml (`test-dispatch-ledger-task-id.sh:342-364`):

```bash
"${DISPATCH_SH}" "@${f4b_mission}" --protected --spawn --kind docs --task-id OPS-42
```

This worker received the F4b fixture mission verbatim (`# OPS-42 — cleanup, N1B-F4b
with-task-id 79466 1787598101`). Root cause re-confirmed from inside this worker's
env: `LEADV2_DISPATCH_SUBSESSION_BIN` points at the fixture's
`fake-claude-subsession.sh` (the stubbed seam, not the escape route), while
`LEADV2_DISPATCH_GLM_BIN` is **absent** — the #6 hole firing from the F4b site.
Blast radius is now complete: BASE, C1, C2, C3, F4a, F4b — every `--spawn` case in
the suite escapes.

## New facts this instance adds

1. **The bound `--task-id` leaks into real infrastructure naming.** The lane
   worktree is `.claude/worktrees/OPS-42` and the lane branch is
   `worktree-OPS-42` — named from the *fixture's* task-id, which the fixture
   deliberately maps to a tasks.yaml record ("Totally unrelated record") because
   **OPS-42 is a real founder task id**. An escape minted a real worktree/branch
   named after a real task; a genuine OPS-42 dispatch later will collide with it.
   glm-run meta confirms: `repo: OPS-42`,
   `cwd: .../worktrees/OPS-42` (`~/.claude/cache/glm-runs/260824-220144-OPS-42-470e/meta.yaml`).
2. **Stock merged main also escapes.** Instances #5–#7 were spawned from sibling
   WIP lanes; this instance's parent chain roots in
   `PREPASS-PROVIDER-FALLBACK-01-R3`'s `glm-coder.sh` (see below) — the escape
   needs no WIP dispatcher, only the un-stubbed GLM seam.
3. **One escaped worker re-ran the suite and manufactured three more escapes**
   (before recognising the pattern): this worker's verification run (PID 89927,
   tmpdir `dispatch-ledger-task-id-89927-1787598150.xPpHmk`) itself spawned live
   escaped lanes `02f1b276` (claude, F4a), `408054ce` (glm, C-site) and
   `N7F-C3-BOUND-ID` (codex, C3), each leaving a lane worktree on disk. Escapes
   multiply when escaped workers follow the run-the-suite instinct.
4. **The suite is false-red when run from a worktree:** `[TEST] === 5 passed,
   9 failed ===` including F4/F4b, with every failing case logging
   `FOREIGN-PROJECT-ROOT-GUARD-01 ... status=foreign_env_overridden` (env root =
   fixture tmp repo, cwd root = worktree; the guard overrides the fixture root,
   so fixture ledger rows land outside the dirs the render checks). Feeds the
   N4-TESTRUNNER-FALSE-RED lane. The live ledger stayed clean: grep of
   `~/.claude/cache/dispatch-ledger/*` for the run's task sigs (408054ce,
   1fcd02e5, 89927) has zero hits.

## Evidence

Parent chain (captured from inside the escape; the dispatcher ran from lane
worktree `PREPASS-PROVIDER-FALLBACK-01-R3` — the same lane as instances #5/#6):

```
45434 45341  claude -p '# OPS-42 — cleanup, N1B-F4b with-task-id 79466 1787598101' ...
45341 45141  bash .../worktrees/PREPASS-PROVIDER-FALLBACK-01-R3/plugins/leadv2/scripts/glm-coder.sh __run_child .../glm-runs/260824-220144-OPS-42-470e
45141     1  bash .../worktrees/PREPASS-PROVIDER-FALLBACK-01-R3/plugins/leadv2/scripts/glm-coder.sh __supervise .../glm-runs/260824-220144-OPS-42-470e
```

Run metadata (`~/.claude/cache/glm-runs/260824-220144-OPS-42-470e/meta.yaml`):
`endpoint: https://api.z.ai/api/anthropic`, `model: glm-5.2`, `status: running`,
6 `PROVIDER_RETRY` lines in `progress.log` — real provider quota burned on a
fixture string.

## Worker conduct

No mission work was performed: the mission body ("bound --task-id OPS-42 must
still resolve via tasks.yaml") is a fixture assertion, not a task. Deliberately
NOT re-run after the first (unwitting) attempt: the suite spawns real workers
(fact 3 above); docs-only change carries no shell/python surface to syntax-check.
Fix ownership stays engine-side per #6: stub `LEADV2_DISPATCH_GLM_BIN=/bin/true`
on every `--spawn` case — F4b's dispatch site is `:361`.

---

# TEST-ESCAPE — instance #9: C1 fixture (heading, no --task-id) escapes via sibling lane's glm-coder.sh

**Escaped worker:** this lane (worktree **de4fcc31**, branch `worktree-de4fcc31`), run
`260904-154357-de4fcc31-15f0`. **Date:** 2026-09-04 15:44 EEST. **Precedent:** #5
(8a18fce), #6 (405f697, root cause VERIFIED), #7 (cc7c79f), #8 (this file, F4b).

## What happened

The spawning suite run (test shell PID **72750**, fixture tmpdir
`dispatch-ledger-task-id-72750-1788525694.mAksKI`) reached case C1 — mission with an H1
heading but deliberately no `--task-id`, driving the real live dispatch shape. This
worker received the fixture heading verbatim: `# N7F-C1 — case one heading,
dispatch-ledger-task-id 72750 1788525770`.

## Evidence (captured from inside this worker)

1. `LEADV2_DISPATCH_SUBSESSION_BIN` **IS set** to the fixture's
   `fake-claude-subsession.sh` (fixture tmpdir path, verbatim) — the stubbed seam is
   not the escape route.
2. `LEADV2_DISPATCH_GLM_BIN` is **absent** from this worker's environment.
3. Parent chain: `claude -p '# N7F-C1 …'` (pid 27992) ← `glm-coder.sh` (pid 27867,
   pp=27752) running from lane worktree **DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01** —
   the escape needs no WIP dispatcher edit; the sibling lane's stock `glm-coder.sh`
   suffices when the GLM seam is un-stubbed.
4. Run metadata (`~/.claude/cache/glm-runs/260904-154357-de4fcc31-15f0/meta.yaml`):
   `endpoint: https://api.z.ai/api/anthropic`, `model: glm-5.3`, `status: running`,
   `repo: de4fcc31`, `cwd: …/worktrees/de4fcc31`; ≥1 `PROVIDER_RETRY` line in
   `progress.log` — real provider quota burned on a fixture string.

## Notable fact: current main's suite appears to carry the #6 fix

This checkout's `test-dispatch-ledger-task-id.sh` exports
`LEADV2_DISPATCH_GLM_BIN=/usr/bin/false` (line 34) and re-points it at a fake launcher
(line 123) — yet this worker's env has no `GLM_BIN`. Either the spawning checkout
(DARK-SUITES lane) predates that stub, or the C1 dispatch site drops it from the
spawned env. UNVERIFIED which: not probed from inside this worker beyond the env
capture above; the engine session that owns the fix should check whether the suite's
`export LEADV2_DISPATCH_GLM_BIN` actually survives into the child of the C1 `--spawn`
call.

## Worker conduct

No mission work was performed: the mission body ("case one heading, deliberately no
--task-id") is a fixture assertion, not a task. Deliberately NOT run:
`test-dispatch-ledger-task-id.sh` itself — re-running the suite risks manufacturing
escape instance #10 (see instance #8, fact 3). Docs-only change; no shell/python
surface to syntax-check.
