# FORK-STORM-KILLS-HOOKS-01 — report

Lane branch `worktree-FORK-STORM-KILLS-HOOKS-01`, build commit `08fb23a`.
Run with `LEADV2_SUITE_LOCK_DISABLE=1`. All fixtures in `$(mktemp -d)`; no
process outside a fixture tree was killed by any suite.

## 0. The headline correction

The lane's premise numbers were wire counts, not per-call costs, and one core
assumption ("when a hook cannot fork the tool call fails") is false on the
current runtime. Both findings have probe artifacts; both changed the design.

## 1. What the harness actually does when a hook dies (Critical 1)

Probe: fixture project with a PreToolUse Bash hook, five `claude -p --model haiku
--max-turns 4` runs, hook firing proven by a side-file write (`/tmp/forkprobe/hookfired.log`
showed all five `hook-ran-*` lines). Transcripts via `--output-format json`:

| hook exit                                   | final model reply | tool call |
|---------------------------------------------|-------------------|-----------|
| rc=0 (`rc-0/t-0.json` result `"probe-ok"`)   | "probe-ok"        | succeeded |
| rc=1                                         | "probe-ok"        | succeeded (non-blocking) |
| rc=2                                         | "BLOCKED"         | **blocked** |
| rc=254 (fork-failure class)                  | "probe-ok"        | succeeded |
| 127 (`nonexistent-hook-binary-xyz-12345`)    | "probe-ok"        | succeeded |

**Conclusion: the harness fail-opens natively on any rc != 2.** A hook that
cannot fork does NOT take the tool call down — it degrades to a non-blocking
error the model can see. The only case that blocks is deliberate rc=2, which
is exactly how guards (lead-edit-guard et al.) deny actions. Masking exit
codes would disable every guard: not done.

Design consequence: the fail-open entry discipline ships as the **journal
suffix on the 34 lifecycle-event commands** in hooks.json (SessionStart,
UserPromptSubmit, Stop, SubagentStop, PreCompact, PostCompact, CwdChanged,
TaskCreated): `rc<=2` passes through untouched, anything else flattens to
"did not run" (exit 0) and appends `<hook> rc=<n>` to
`${LEADV2_DEGRADE_LOG:-/tmp/leadv2-hook-degrade.log}`. The journal write is
builtins-only (`printf`), so it cannot itself die of EAGAIN. Per-call events
(52 commands) are deliberately untouched — see §2.

## 2. The "52 hooks per tool call" figure (Critical 3)

Facts from the hook table (`hooks.json`, verified pre-change):

- PreToolUse has 36 commands, but **34 of 36 already carry tool matchers**
  (`Bash`, `Agent`, `Write`, `Edit`, `MultiEdit`, `Read`, `TaskOutput`,
  `Monitor`, `AskUserQuestion`, `Workflow`). Only `leadv2-loop-detect-hook.sh`
  is `.*`.
- Measured process model: the harness shell **tail-exec's a single simple
  command**. Control probe: `sh -c '"$TMP/stub-ppid.sh"'` reports the CALLER
  as the stub's PPID — 1 process per hook command, with or without an explicit
  `exec` (suite 5 asserts both directions, plus the compound-command control
  at 2 processes).

So the honest per-call counts (asserted in suite 5, pinned exactly):

| tool call | hook commands fired | of 52 wired |
|-----------|--------------------|-------------|
| Bash      | **13** (2 Pre + 11 Post) | 13 |
| Edit      | **14** (7 Pre + 7 Post)  | 14 |
| Agent     | 21 (11 Pre + 10 Post)    | 21 |
| Read      | 11 | 11 |

**No further config-level narrowing is possible without a behavior change.**
The `.*` PostToolUse hooks genuinely act on every tool (e.g.
`leadv2-turncap-checkpoint-hook.sh` counts every turn in its Job 2 — narrowing
it to Write/Edit would change the turn budget; `leadv2-tool-counter.sh`,
`leadv2-auto-status.sh`, `leadv2-single-lead-beat.sh` never even read
tool_name). Hook arrays were not reordered — suite 6 asserts firing-set
identity for 10 events × 21 tools against the pre-lane blob
(`10fe3d6e9fcb`), and the worktree-vs-HEAD diff touches only command strings.

The real remaining pressure is INSIDE the hook scripts (turncap alone spawns
`python3` twice per call just to parse `tool_name`; the heavy hooks fork
20-26 children each). Those files are outside LANE_WRITES → **follow-up lane:
"cut internal forks of per-call hooks"** (turncap + loop-detect python3-per-
parse are the top two).

## 3. The orphan-sleep class (Critical 2)

`plugins/leadv2/scripts/lib/leadv2-sleep.sh`:

- `leadv2_wait SECS` — fork-free timed wait: `read -t` on a private fifo held
  read-write (never EOFs). One `mkfifo` per watcher lifetime; every wait after
  that forks nothing, so a SIGKILLed watcher mid-wait leaves **nothing** to
  orphan. `read -t` timeout rc measured as 1 under BOTH /bin/bash 3.2.57 and
  Homebrew bash 5.3.9 — the helper maps every read rc to sleep semantics
  (return 0).
- `leadv2_spawn` / `leadv2_reap` / `leadv2_reap_arm` — watchers that need real
  children record their pids; EXIT/TERM/INT/HUP traps TERM them, wait 1s,
  KILL survivors, re-raise the kill status.

Census (regex pass over plugins/leadv2/{hooks,scripts}/**.sh; pattern strings
containing the word `sleep` count as false positives — e.g. this lane's own
fork-budget script shows up once): **113 files use `sleep`; 49 files have
in-loop sleeps (107 in-loop sleep lines)**. Top production poll loops:
`leadv2-dispatch-code.sh` (5), `freepool-coder.sh` (4), `kimi-coder.sh` (4),
`leadv2-kimi-session-runner.sh` (3), `leadv2-helpers.sh` (3),
`claude-subsession.sh` (3), `leadv2-glm-session-runner.sh` (3), `glm-coder.sh`
(3), `leadv2-daemon.sh` (3), `leadv2-dispatch-product-close.sh` (3),
`codex-task.sh` (2 — including `__quota-watch`, the watcher whose orphan kept
a finished lane reading "live" for 33 minutes), `leadv2-portable-lock.sh` (2),
`codex-guard.sh` (2).

**Converted: 0 production loops. Reason: every poll-loop file is outside
LANE_WRITES.** Ask-channel q-e5ee4725 asked to expand the write set to
`codex-task.sh`, `leadv2-lane-watch.sh`, `leadv2-single-lead-beat-loop.sh`;
it timed out on the default option (a: convert in a follow-up lane) — journaled.
The helper + conversion pattern is proven by suites 1-3 in
`test-no-orphan-sleep.sh`; the follow-up lane is mechanical from there.

## 4. Fork budget (Critical 4)

`plugins/leadv2/hooks/leadv2-hook-fork-budget.sh` — one command, ~0.08s,
exit 0 healthy / 1 within 80% of `ulimit -u` / 2 unmeasurable; `--sweep`
kills ONLY `comm=sleep && ppid=1` (the orphan class; never a live tree).

Live remediation on the day's residue (founder's incident class, regenerated
since 2026-09-01 morning):

```
$ leadv2-hook-fork-budget.sh            (pre-sweep)
fork-budget: 100 orphaned sleep at ppid=1; rerun with --sweep to reap
procs_total=1040  procs_mine=743  procs_claude=10
orphan_sleep_ppid1=100  procs_limit_user=5333  hook_degrade_lines=0
$ leadv2-hook-fork-budget.sh --sweep    (then re-read)
fork-budget: 2 orphaned sleep at ppid=1; ...
procs_total=956   procs_mine=660
```

100 orphans reaped, 84 fewer live processes; 2 regenerated within minutes
(the pressure is the unconverted loops, §3).

## 5. Mutation kills (RED each, then revert; all six committed GREEN first)

| # | mutation (inside production body) | suite that went red | red evidence |
|---|-----------------------------------|---------------------|--------------|
| 1 | `trap 'leadv2_reap' EXIT` → `trap ':' EXIT` | test-no-orphan-sleep | `FAIL: 2: child 32801 survived a NORMAL watcher exit (EXIT trap not reaping)` — rc=1 |
| 2 | `leadv2_wait` body → `command sleep` | test-no-orphan-sleep | `FAIL: 1a: child 38931 survived its TERM-killed watcher`, `1b children=[57540 57545] want [57540]`, `3: poll loop children mid-flight: 59005` — rc=1 |
| 3 | compound `; :` appended to a per-call command | test-hook-fork-budget | `FAIL: 5: per-call count changed or a per-call command lost single-simple form` — rc=1 |
| 4 | delete an Agent-group hook entry | test-hook-fork-budget | `DIFF ('PreToolUse','Agent', [... 11 hooks], [... 10 hooks])`, `FAIL: 6: firing set changed` — rc=1 |
| 5 | fork-budget verdict hard-flip to NEAR-WALL | test-hook-fork-budget | `FAIL: 7: fork-budget rc=1` — rc=1 |
| 6 | journal suffix stripped from a lifecycle command | test-hook-fork-budget | `FAIL: 4: could not extract journal suffix from hooks.json` — rc=1 |

M1 note: it red ONLY suite 2 because the TERM trap still reaped — the kill
isolated exactly the EXIT-trap path. M2 turned 1a/1b/3 red together (the
fork-free wait is load-bearing for all three).

## 6. Self-check (raw)

```
$ for f in <changed .sh files>; do bash -n "$f" && echo "bash-n OK: $f"; done
bash-n OK: plugins/leadv2/hooks/leadv2-hook-fork-budget.sh
bash-n OK: plugins/leadv2/scripts/lib/leadv2-sleep.sh
bash-n OK: plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
bash-n OK: plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
bash-n OK: tests/run-all.sh
$ python3 -c "import json; json.load(open('plugins/leadv2/hooks/hooks.json'))"
json OK
(no Python files changed — py_compile n/a)

$ bash plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh   (post-revert)
  ok: 1a ... ok: hygiene ...
no-orphan-sleep: pass=9 fail=0          rc=0
$ bash plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
hook-fork-budget: pass=15 fail=0        rc=0
```

Selection proof (`LEADV2_SUITE_LOCK_DISABLE=1 tests/run-all.sh --scope changed`):
see §7.

## 7. run-all --scope changed (LEADV2_SUITE_LOCK_DISABLE=1)

Selection proven — both new suites were selected and passed:

```
[RUN]  .../FORK-STORM-KILLS-HOOKS-01/plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
[PASS] .../FORK-STORM-KILLS-HOOKS-01/plugins/leadv2/scripts/tests/test-hook-fork-budget.sh
[RUN]  .../FORK-STORM-KILLS-HOOKS-01/plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
[PASS] .../FORK-STORM-KILLS-HOOKS-01/plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
run-all: 5 passed, 1 failed, scope=changed
```

(test-hook-fork-budget selected via the `hooks.json` AND
`leadv2-hook-fork-budget.sh` map rows; test-no-orphan-sleep via the
`leadv2-sleep.sh` row.)

The 1 failure is `run-core-offline.sh` — the **pre-existing baseline reds**
(matching the 2026-09-01 baseline exactly): `[CORE-OFFLINE] FAILED: T13
slice2 (arbiter bench-fallback + abandon dedup)`, `[CORE-OFFLINE] FAILED:
landed-at-spawn (no terminal=landed at spawn; target repo keying)`, and the
phase-precondition G-cases (G2/G3/G8/G11a spawn-sentinel failures). None
touch this lane's files. Note: the log at /tmp/runall-changed.log was
contaminated by a concurrent lane's run-all writing the same path; the
suite lines above carry this lane's worktree root and are from this lane's
selection run.

## 8. Files changed (commit 08fb23a)

- `plugins/leadv2/hooks/hooks.json` — 34 lifecycle commands get the fail-open
  journal suffix; 52 per-call commands byte-identical; zero reorder (verified:
  only command strings differ; order/metadata asserted identical).
- `plugins/leadv2/hooks/leadv2-hook-fork-budget.sh` — new.
- `plugins/leadv2/scripts/lib/leadv2-sleep.sh` — new.
- `plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh` — new (suites 1-3).
- `plugins/leadv2/scripts/tests/test-hook-fork-budget.sh` — new (suites 4-7).
- `tests/run-all.sh` — hooks.json + plugins/leadv2/hooks/*.sh now reach the
  stem machinery (synthetic stem, freepool-arm.yaml precedent); 3
  EXTRA_SUITE_MAP rows.

## 9. Follow-ups

1. Convert the named poll loops to `leadv2-sleep.sh` (write set:
   codex-task.sh, leadv2-lane-watch.sh, leadv2-single-lead-beat-loop.sh, then
   the rest of the census in §3) — ask q-e5ee4725 defaulted to deferring this.
2. Cut internal forks of the per-call hooks (turncap's two python3 parses per
   call; loop-detect's per-event python) — needs hooks/*.sh in a write set.
3. The degrade journal grows unbounded; fork-budget reports its line count —
   add rotation when it first matters.
