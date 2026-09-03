# SUPERVISOR-DELETE-01 round-2 finisher — architect prepass

Design only. No implementation performed. All greps below were run on
`~/Projects/leadv2` @ `b9959aa` (main) and cross-checked against the live lane worktree
`.claude/worktrees/eacd0eb5` (same HEAD, phase-1 work uncommitted there).

## 0. Where the work lives (verified, not assumed)

`git worktree list` → `.claude/worktrees/eacd0eb5  b9959aa [worktree-eacd0eb5]`.
`git status --short` in that worktree (handoff noise filtered):

```
R  plugins/leadv2/scripts/leadv2-supervise.sh -> plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
 M plugins/leadv2/hooks/leadv2-task-anchor.sh
 M plugins/leadv2/hooks/pre-compact-task-freeze.sh
 M plugins/leadv2/scripts/leadv2-plugin-sync.sh
 M plugins/leadv2/scripts/leadv2-status-collector.sh
 M plugins/leadv2/scripts/tests/test-active-registry-failclosed.sh
 M plugins/leadv2/scripts/tests/test-codex-session-runner.sh
 M plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
 M plugins/leadv2/scripts/tests/test-lane-liveness-lies.sh
 M plugins/leadv2/scripts/tests/test-status-surface.sh
 M plugins/leadv2/scripts/tests/test-supervise-failclosed.sh
 M plugins/leadv2/tests/test-open-threads-prune.sh
```

**Phase-1 is real and uncommitted in `eacd0eb5`.** The implementer MUST run in that
worktree and MUST NOT redo the rename. First act: `git status --short`, confirm the `R `
row above, then continue. Nothing in this design re-does phase 1.

## 1. The one finding that changes the mission

The mission says "git rm the four scripts, first grep for callers". I ran that grep. Of
**31 files** in `plugins/leadv2` referencing the four names, **all but three are comments
or state-file names**. The three real dependencies:

| # | Site | Line | Kind | Verdict |
|---|------|------|------|---------|
| R1 | `scripts/leadv2-lanes-snapshot.sh` | 138 (`--print` mode) | `exec bash "$RESUME_SH"` | **live-path exec of `leadv2-supervise-resume.sh`** |
| R2 | `scripts/leadv2-lanes-snapshot.sh` | 1394 (py, full `--json`) | `subprocess.run([... resume_script ...])` | **live-path exec of the same** |
| R3 | `scripts/leadv2-plugin-sync.sh` | 530 | curated sync file-list literal | names `leadv2-supervise-loop.sh leadv2-supervise-pick.sh` |
| R4 | `scripts/tests/test-ensure-adopt.sh` | 27 | `LOOP="${SCRIPT_DIR}/leadv2-supervise-loop.sh"` | **suite the mission never mentions** |

Raw grep (non-comment refs only):

```
$ grep -rn "leadv2-supervise-loop.sh\|leadv2-supervise-pick.sh" \
    plugins/leadv2/scripts/leadv2-plugin-sync.sh \
    plugins/leadv2/scripts/tests/test-status-surface.sh \
    plugins/leadv2/scripts/tests/test-ensure-adopt.sh | grep -vE ":[0-9]+:\s*#"
plugins/leadv2/scripts/tests/test-ensure-adopt.sh:27:LOOP="${SCRIPT_DIR}/leadv2-supervise-loop.sh"
plugins/leadv2/scripts/leadv2-plugin-sync.sh:530:    leadv2-active-registry.sh leadv2-supervise-loop.sh leadv2-supervise-pick.sh
```

### DECISION-A (needs the lead's yes/no — recommended answer given)

`leadv2-supervise-resume.sh` (275 lines) is **not supervisor-loop machinery**. It is the
`<supervisor-handoff>` restore-block *composer*, and it is contractually write-free
(`test-supervisor-reason-honest.sh:8` states this as a design invariant). The renamed,
kept `leadv2-lanes-snapshot.sh` execs it on **both** live paths (R1, R2) — the path the
task-anchor hook, the pre-compact hook and `leadv2-status-collector.sh` all reach.

`git rm` it literally and the snapshot degrades silently and *fail-soft*:
`resume_obj = {"status": "degraded", "degraded": ["resume composer unavailable"]}` and
`--print` prints `HANDOFF DEGRADED — resume composer script missing`. Both exit 0. No
suite goes red. That is a silent capability loss on a live path — exactly the failure
class this repo keeps re-learning.

- **RECOMMENDED — A1: keep and rename.** `git mv leadv2-supervise-resume.sh
  leadv2-lanes-resume.sh`; update R1 and R2 to the new name. Three scripts deleted
  (`-loop`, `-pick`, `-watchdog`), the composer survives under the lanes-* namespace it
  now belongs to.
- A2 (lead override): delete it, and **also** delete the `--print` branch
  (lanes-snapshot.sh:136-148) and the `resume_obj` block (~1385-1405) plus the `"resume"`
  key from the JSON result, so the loss is explicit rather than a degraded stub. Do NOT
  take A2 half-way (delete the script, leave the callers) — that is the silent-degrade
  outcome.

**If the lead does not answer, the implementer takes A1** and records the assumption in
the terminal artifact. Do not block the lane on this.

### DECISION-B — `test-ensure-adopt.sh` (not in the mission)

Its subject is the loop's ensure/adopt path (`LOOP=.../leadv2-supervise-loop.sh:27`), and
tmux adoption/prune **survived the rename** into `leadv2-lanes-snapshot.sh` (see its
line-135 header: "skips every mutation/reconciliation path in this script (sentinel write,
tmux adoption/prune, phase-backfill, truth-probe)"). So the subject moved, it did not die.
→ **Retarget `test-ensure-adopt.sh` at `leadv2-lanes-snapshot.sh`** (point `LOOP=` at the
snapshot script, keep the suite name and its SUITE_DEFS row). Do not delete it. This is
the same "don't lose coverage silently" rule the mission states for item 3.

## 2. Per-suite verdicts (subject check cited for each)

| Suite | Subject | Subject alive? | Verdict |
|---|---|---|---|
| `scripts/tests/test-supervise-v2.sh` | supervisor reconciliation loop | loop dies | **DELETE**, retarget adoption/prune/tombstone cases → new `test-lanes-snapshot.sh` (item 3) |
| `scripts/tests/test-supervise-failclosed.sh` | supervisor fail-closed | loop dies | **DELETE** + SUITE_DEFS row |
| `tests/test-supervise-fanout-guard.sh` | supervisor/lead PID isolation via `.supervise-active` | loop was the sentinel writer | **DELETE** + SUITE_DEFS row |
| `scripts/tests/test-ensure-adopt.sh` | loop ensure/adopt → **moved to lanes-snapshot** | yes (moved) | **KEEP + RETARGET** (DECISION-B) |
| `scripts/tests/test-statusline-supervisor-gate.sh` | `leadv2-lane-status-line.sh:142` supervisor-only gate — file survives; suite writes its own fixture sentinel under `LEADV2_STATE_ROOT` | yes | **KEEP unchanged** |
| `scripts/tests/test-supervisor-close-plan-mirror.sh` | close-announcement dual-surface mirror (ST-7); no loop reference | yes | **KEEP unchanged** |
| `scripts/tests/test-supervisor-mode-reinject.sh` | `hooks/leadv2-supervisor-mode-reinject.sh` — `ls` confirms the hook exists on disk | yes | **KEEP unchanged** (see risk RK-2) |
| `scripts/tests/test-supervisor-reason-honest.sh` | `supervisor:` line in `leadv2-status-surface.sh`; explicitly asserts the *absent-sentinel* rendering | yes | **KEEP unchanged** |

SUITE_DEFS rows to remove (`scripts/tests/run-core-offline.sh`, verified by grep):

```
193:  "supervisor fail-closed|||bash $TEST_DIR/test-supervise-failclosed.sh"
194:  "supervisor reconciliation|||bash $TEST_DIR/test-supervise-v2.sh"
195:  "supervisor/lead PID isolation|||bash $PLUGIN_ROOT/tests/test-supervise-fanout-guard.sh"
```
Plus line 93 — `"supervisor reconciliation"` appears a second time (a name list / expected-
suite roster). Both occurrences must go or the runner will claim a missing suite. Net row
delta: **-3, +1** (`test-lanes-snapshot.sh`), i.e. -2 against the pre-lane count.

## 3. Acceptance-grep precision (a trap in the mission text as written)

Item 5 asks for "zero references to the four deleted scripts anywhere in plugins/leadv2".
Taken as a substring grep for `supervise-loop`, that can never go green and should not: the
**state-file names are not script names** and are still written by surviving code —
`docs/leadv2/supervise-loop.log` (written by `leadv2-pulse-beat.sh:41`,
`hooks/leadv2-single-lead-beat.sh:82`, read by `leadv2-broad-status.sh:33`,
`leadv2-writes-overlap.sh:148`), `.supervise-loop.json` (`hooks/leadv2-supervisor-pump-caller.sh:81`,
`leadv2-pulse-beat.sh:53`), `.supervise-loop.heartbeat` (`leadv2-status-surface.sh:300-317`).
Renaming those state paths is a **NON-GOAL** of this lane (it is a live-state migration with
its own blast radius).

The acceptance grep must therefore be filename-anchored:

```
grep -rn 'leadv2-supervise-\(loop\|pick\|resume\|watchdog\)\.sh' plugins/leadv2 \
  --exclude-dir=node_modules
```
→ must return **zero** rows outside `plugins/leadv2/docs/` archive text (and, under A1,
zero rows for `-resume.sh` too, since it is renamed not deleted).

Getting that to zero means editing ~25 **comment** lines across
`hooks/leadv2-supervisor-pump-caller.sh`, `hooks/leadv2-single-lead-beat.sh`,
`scripts/leadv2-{active-registry,backlog-pump,broad-status,lane-heartbeat,plugin-sync,pulse-beat,status-surface,writes-overlap}.sh`,
`scripts/lib/leadv2-alarm-dedupe.sh`, `scripts/{codex-task,glm-coder,kimi-coder}.sh`,
`docs/single-lead-pulse.md`. These are prose-only ("leadv2-supervise-loop.sh already pumps
on its own cadence") and are now **actively misleading** — a future reader would believe a
live pump exists. Rewrite them to name the surviving owner
(`leadv2-pulse-beat.sh` / `hooks/leadv2-single-lead-beat.sh`) or past-tense them
("retired 2026-08-19"). Comment-only edits: `bash -n` still required, no behaviour change.

## 4. Change plan (ordered, one commit per group)

**Commit 1 — "delete the loop" (code)**
1. `git rm plugins/leadv2/scripts/leadv2-supervise-{loop,pick,watchdog}.sh`
2. A1: `git mv .../leadv2-supervise-resume.sh .../leadv2-lanes-resume.sh`; update
   `leadv2-lanes-snapshot.sh:138` (`RESUME_SH=`) and `:1394` (`resume_script =`).
3. `leadv2-plugin-sync.sh:530` — drop the two names from the curated list literal.
   Verify the list is whitespace-separated and nothing else parses positionally.
4. Comment sweep (§3) across the 14 files listed there.

**Commit 2 — "delete the suites, keep the coverage" (tests + docs)**
5. `git rm` `scripts/tests/test-supervise-v2.sh`, `scripts/tests/test-supervise-failclosed.sh`,
   `tests/test-supervise-fanout-guard.sh`.
6. New `scripts/tests/test-lanes-snapshot.sh` carrying the adoption / prune / tombstone
   cases lifted from `test-supervise-v2.sh`, retargeted at `leadv2-lanes-snapshot.sh`.
   **The symlinked fake-claude trick from `512ecda` stays verbatim** — a *copied*
   Apple-signed `sleep` is SIGKILLed on macOS (rc=137); symlink it.
7. Retarget `scripts/tests/test-ensure-adopt.sh:27` at `leadv2-lanes-snapshot.sh` (DECISION-B).
8. `run-core-offline.sh`: remove rows 193/194/195 **and** the line-93 roster entry; add
   `"lanes snapshot reconciliation|||bash $TEST_DIR/test-lanes-snapshot.sh"`.
9. `plugins/leadv2/docs/supervisor-role.md` → 3-line stub:
   `retired 2026-08-19 (founder order); reconciliation lives in
   plugins/leadv2/scripts/leadv2-lanes-snapshot.sh`. **Stub, never delete** — RK-2.
10. `plugins/leadv2/skills/leadv2-supervise/SKILL.md` → refuse-stub (one paragraph: the
    mode is retired, point at `leadv2-lanes-snapshot.sh`, instruct the model to refuse).
    12 of its references die with this rewrite.
11. `plugins/leadv2/commands/leadv2.md:72` — the `/leadv2 supervise` table row becomes
    "retired 2026-08-19 — see leadv2-lanes-snapshot.sh".

## 5. Risks

| ID | Risk | Mitigation |
|---|---|---|
| RK-1 | **Silent fail-soft on the resume composer.** Both call sites swallow a missing script into a degraded stub with exit 0 — no suite catches it. | DECISION-A1 (rename, don't delete). If A2 is chosen, delete the call sites too, so the loss is a code change and not a runtime stub. |
| RK-2 | `hooks/leadv2-supervisor-mode-reinject.sh:85` is a **registered PostCompact hook** (`hooks.json`) that points at `docs/supervisor-role.md`. Deleting that doc breaks a live hook's pointer. | Stub the doc, never `git rm` it. `test-supervisor-mode-reinject.sh` asserts the pointer — it stays green only if the file exists. |
| RK-3 | `.supervise-active` loses its writer with the loop. **Seven** readers survive: `hooks/leadv2-{supervisor-guard,supervise-bash-guard,supervise-sentinel-cleanup,supervisor-mode-reinject,supervise-fanout-guard,supervisor-pump-caller}.sh` + `scripts/leadv2-lane-status-line.sh:142` + `leadv2-status-surface.sh:19`. All fail-closed → permanent no-op dead code. | **Out of scope, explicitly.** Not a regression (fail-closed is the safe direction). Queue a follow-up "retire the .supervise-active sentinel + its 7 readers" in `docs/leadv2/open-threads.md`. Do not widen this lane. |
| RK-4 | `.supervise-loop.heartbeat` had `leadv2-supervise-watchdog.sh:48` as a writer; with it gone `leadv2-status-surface.sh` S3 renders `supervisor: OFF/STALE` forever. | Intended — that IS the retirement. `test-supervisor-reason-honest.sh` already asserts the OFF/STALE rendering is honest, so it stays green and documents the new steady state. |
| RK-5 | `test-statusline-supervisor-gate.sh`'s "gate ON" branch becomes unreachable in production (nothing writes the sentinel), while the fixture keeps it green — a test asserting a dead path. | Keep the suite (coverage of `lane-status-line.sh` is real); note the dead branch in the follow-up thread with RK-3. Do not delete on this lane. |
| RK-6 | Concurrent lanes on the same tree. T2 owns `leadv2-dispatch-product-close.sh`, V3-GLM owns the `leadv2-dispatch-code.sh` routing block — **neither appears in any grep above**, so there is no overlap. `run-core-offline.sh` is shared. | Re-`git diff run-core-offline.sh` immediately before `git add` (global rule: a parallel session can revert an edit). Touch neither off-limits file. |
| RK-7 | The mission's grep-proof as literally worded can never be green (§3). An implementer will either loop on it or fake it. | Use the filename-anchored grep in §3 verbatim; state the state-file-name carve-out in the terminal artifact. |
| RK-8 | The lane worktree carries 47 dirty files, most of them `docs/handoff/**` and `docs/leadv2/**` lock/bus state from other sessions. `git commit -a` would sweep them in. | Stage **explicitly by path**. Never `git add -A` / `git commit -a` in this worktree. |

## 6. Non-goals (do not do these)

- Do **not** rename `supervise-loop.log`, `.supervise-loop.json`, `.supervise-loop.heartbeat`,
  or `.supervise-active`. Live-state migration, separate lane.
- Do **not** delete the seven sentinel-reader hooks (RK-3) or unregister anything in
  `hooks.json`.
- Do **not** touch `leadv2-dispatch-product-close.sh` (T2 lane, live) or the
  `leadv2-dispatch-code.sh` routing block (V3-GLM lane, live). No grep hit requires either.
- Do **not** redo phase 1 (the `leadv2-supervise.sh` → `leadv2-lanes-snapshot.sh` rename and
  its caller updates are already staged in `eacd0eb5`).
- Do **not** delete `test-statusline-supervisor-gate.sh`,
  `test-supervisor-close-plan-mirror.sh`, `test-supervisor-mode-reinject.sh`,
  `test-supervisor-reason-honest.sh` — all four subjects verified alive (§2).
- No refactor of `leadv2-lanes-snapshot.sh` beyond the two resume call sites.

## 7. Evidence-contract note

Every claim above is a local-filesystem/grep claim with its artifact inline. There are no
external-system or API claims in this design, so no `UNVERIFIED:` tags are required.

acceptance:
  - surface: log_line
    observable: "The core-offline runner's final tally line in the lane shows two fewer
      total suites than before this lane and reports zero failures; the names
      'supervisor fail-closed', 'supervisor reconciliation' and 'supervisor/lead PID
      isolation' no longer appear anywhere in that run's output, while a line named for
      the lanes-snapshot reconciliation suite appears and passes."
    authored_at: 2026-08-19T23:47:20Z
  - surface: file_artifact
    observable: "In the committed tree, the plugins/leadv2/scripts directory no longer
      contains any file whose name begins leadv2-supervise- ; a reader opening
      plugins/leadv2/docs/supervisor-role.md sees a three-line retirement notice dated
      2026-08-19 pointing at leadv2-lanes-snapshot.sh instead of the old role
      description."
    authored_at: 2026-08-19T23:47:20Z
  - surface: rendered_line
    observable: "A founder typing /leadv2 supervise is answered with a single line saying
      the supervise mode was retired on 2026-08-19 and that reconciliation now lives in
      leadv2-lanes-snapshot.sh — no supervisor session starts, no lane picker is shown."
    authored_at: 2026-08-19T23:47:20Z
  - surface: rendered_line
    observable: "The <supervisor-handoff> restore block a lead sees at session start still
      lists the live lanes with their phases (it is not the text 'HANDOFF DEGRADED' and
      not an empty/degraded stub) — i.e. the resume composer still runs after the
      deletion."
    authored_at: 2026-08-19T23:47:20Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-supervise-loop.sh, plugins/leadv2/scripts/leadv2-supervise-pick.sh, plugins/leadv2/scripts/leadv2-supervise-resume.sh, plugins/leadv2/scripts/leadv2-supervise-watchdog.sh, plugins/leadv2/scripts/leadv2-lanes-resume.sh, plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/leadv2-plugin-sync.sh, plugins/leadv2/scripts/leadv2-pulse-beat.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/leadv2-writes-overlap.sh, plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/scripts/leadv2-lane-heartbeat.sh, plugins/leadv2/scripts/leadv2-active-registry.sh, plugins/leadv2/scripts/lib/leadv2-alarm-dedupe.sh, plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/glm-coder.sh, plugins/leadv2/scripts/kimi-coder.sh, plugins/leadv2/hooks/leadv2-supervisor-pump-caller.sh, plugins/leadv2/hooks/leadv2-single-lead-beat.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-supervise-v2.sh, plugins/leadv2/scripts/tests/test-supervise-failclosed.sh, plugins/leadv2/scripts/tests/test-lanes-snapshot.sh, plugins/leadv2/scripts/tests/test-ensure-adopt.sh, plugins/leadv2/tests/test-supervise-fanout-guard.sh, plugins/leadv2/docs/supervisor-role.md, plugins/leadv2/docs/single-lead-pulse.md, plugins/leadv2/skills/leadv2-supervise/SKILL.md, plugins/leadv2/commands/leadv2.md

DELIVERABLE_COMPLETE
