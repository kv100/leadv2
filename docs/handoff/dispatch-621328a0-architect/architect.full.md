# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 — implementation design

Repo: `~/Projects/leadv2` (plugin). Branch only. bash 3.2 throughout.

## 1. What is actually on disk (verified, not assumed)

| Fact | Evidence |
|---|---|
| `no_work` already exists in the terminal vocabulary, retryable, NOT write-once | `leadv2-dispatch-ledger.sh:19,45-51,151,201` |
| product-close already emits `no_work` for the empty-diff case | `leadv2-dispatch-product-close.sh:1070` (`cause=empty_diff`) |
| lane-dirty helper already exists and already excludes `docs/leadv2/`,`docs/handoff/` | `…product-close.sh:932-940` (`_pc_lane_dirty`) |
| stream path | `leadv2-dispatch-code.sh:953` → `${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/developer.stream.jsonl` |
| close gate already computes the same handoff dir | `…product-close.sh:83` `HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"` |
| close gate already resolves the lane worktree | `…product-close.sh:865-870` (`_lane_root`, `diff_root`) |
| close gate already knows the arm that ran | `…product-close.sh:15` `AUTHOR="${3:?author}"` |
| the candidate chain is journalled once, at `…dispatch-code.sh:2625` | `candidate_chain task=<sig8> arms=…` |
| `LEADV2_DISPATCH_REVIEWER_ARMS` (today's chain-shaped env into the close gate) is **declared dead** | `…dispatch-code.sh:2666-2673` — do not reuse it |
| `spawn_product_close` is the single env/arg seam into the close gate | `…dispatch-code.sh:1621-1661` |
| the lane's mission text is **not** persisted anywhere the close gate can read | `ls docs/handoff/dispatch-c91e8cca/` → no mission file |
| suites are registered by `run_check` lines | `tests/run-core-offline.sh:100-107` |

### 1a. Why the silent lane reached the e2e gate at all
`pc_scope_diff` already exits 5 with `no_work` on an empty diff, so a *literally* empty
lane should never have reached e2e. It did, because the diff for lane `b0370efc` was not
empty in the byte sense the gate measures — the gate's emptiness test is a **diff over
declared writes**, and the silent-arm signal (no stream file at all) is a *different*
signal that the gate never looks at. Fix 1 is therefore **not** a refinement of the
empty-diff branch; it is a new, earlier probe on a different observable, placed where
neither the diff scoping nor the e2e gate can pre-empt it.

## 2. Design — Fix 1: silent arm is `no_work`, never `dead`

### Placement
In `leadv2-dispatch-product-close.sh`, a new function `pc_silent_arm_probe`, called
**after** the worker-exit wait and the died-with-work resume (i.e. after `:1129`) and
**before** `pc_scope_diff` (`:1131`). This ordering is load-bearing:

- after `pc_await_worker_exit` → the worker has demonstrably exited, so "silent" cannot
  be confused with "still running";
- before `pc_scope_diff` → the lane retires with the truthful cause
  `arm_produced_nothing` rather than the generic `empty_diff`, and the e2e gate at
  `:1151` is structurally unreachable.

### Predicate (all three must hold)
```
silent :=  worker_exited
       AND stream_absent_or_no_assistant_events
       AND NOT _pc_lane_dirty(<lane root>)
```

1. **stream** — `${HANDOFF}/developer.stream.jsonl`.
   - file missing → silent-side true;
   - file present but `grep -c '"type":"assistant"'` == 0 → silent-side true;
   - ≥1 assistant event → **not silent**, return immediately.
2. **growth guard** (the "slow but working arm" clause). Even with zero assistant
   events, if the stream file's mtime is within `LEADV2_PC_SILENT_GROWTH_S` (default
   `60`) of now, treat as **working**, not silent, and return. bash-3.2-safe mtime:
   `stat -f %m` (darwin) with `stat -c %Y` fallback (linux); on any stat failure, treat
   as *working* (fail-open — never manufacture a silent verdict from a broken probe).
3. **worktree** — reuse `_pc_lane_dirty "${_lane_root:-}"`. Dirty → not silent
   (the arm produced something the diff scoping should classify; that is
   `unscoped_lane_work`'s job at `:1065`, untouched). When no lane worktree resolved
   (`_lane_root` empty), the worktree half is treated as *clean* only if
   `_pc_lane_dirty "${ROOT}"` is also false — but note this is the pre-existing
   main-checkout ambiguity; to stay conservative the probe **returns not-silent when no
   lane worktree resolved at all**, so a lane without a worktree keeps today's behaviour
   exactly.

### Terminal
Existing vocabulary only — no new terminal word:

| field | value |
|---|---|
| terminal | `no_work` (retryable; `dead` is write-once and must not be spent here) |
| cause | `arm_produced_nothing` |
| evidence | `arm=<AUTHOR> stream=<absent\|no_assistant_events> lane=<basename lane_root>` |
| exit code | `5` (identical to every other blocked branch — no caller-contract change) |

Artifacts written, mirroring the existing blocked branches:
```
${HANDOFF}/review-gate.md   ->  status: blocked
                                reason: arm_produced_nothing
                                arm: <AUTHOR>
emit decision "review_gate task=<sig8> status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=<AUTHOR>"
_dl_note no_work arm_produced_nothing "<evidence>"
_stamp_review_terminal blocked
```

## 3. Design — Fix 2: the chain advances, from the close gate

**Verdict: fix 2 CAN live in the close gate**, but only if two inputs are threaded to it,
because neither exists on disk today: the candidate chain, and the mission text.

### 3a. Two new threads through `spawn_product_close` (`…dispatch-code.sh:1621-1661`)
1. `LEADV2_DISPATCH_CANDIDATE_ARMS="${reviewer_arms}"` — the same CSV, under a name that
   means what it is. (The chain is also recoverable from the journal
   `candidate_chain task=<sig8> arms=…`; that grep stays as the **fallback** when the env
   is empty, e.g. a close gate spawned by an older dispatcher. Explicit-first,
   journal-fallback — I am threading it explicitly and saying so, per the mission.)
2. `LEADV2_DISPATCH_LANE_MISSION="${_mission_path}"` — dispatch-code persists the lane's
   mission once, at spawn, to `${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-mission.md`
   (new artifact) and passes the path. Without this the close gate has nothing to
   re-dispatch; there is no mission text in the lane dir today.

### 3b. New dispatch-code subcommand: `advance-arm`
```
leadv2-dispatch-code.sh advance-arm --sig8 <sig8> --arm <next_arm> \
    --mission-file <path> --task-id <founder_task_id> [--worktree <lane_root>] [--writes <csv>]
```
It reuses the existing spawn machinery (`spawn_worker` + `_stamp_active_phase` +
`spawn_product_close`) and **deliberately skips `dispatch_reserve`**: the sig8 is already
confirmed to *this* lane, and the duplicate-signature guard (`arc=2`, `…:2650-2661`)
exists to stop two *independent* dispatchers racing one mission — not to stop one lane
continuing its own chain. Re-running `cmd_resolve` instead would be refused with
`dispatch_refused reason=duplicate_task_signature` and the chain would still not advance;
this is the reason a new subcommand is required rather than a plain re-invocation.

On success it emits:
```
arm_advance task=<sig8> from=<silent_arm> to=<next_arm> reason=arm_produced_nothing
worker_spawned by=arm_advance model=<next_arm> handle=<handle>
```
and spawns a fresh close gate for the new worker (same lane worktree, same writes).

### 3c. One-shot discipline
- Marker `${HANDOFF}/.arm-advanced-<silent_arm>` written **before** the advance is
  attempted. Its presence → no advance for that arm, ever again
  (`emit decision "arm_advance_skipped task=<sig8> arm=<silent_arm> reason=already_advanced"`).
- The next arm is `the element after AUTHOR in the chain`. If AUTHOR is the last element,
  or absent from the chain, or the chain has one element →
  `arm_advance_skipped … reason=chain_exhausted`. No wrap-around.
- The advance fires **only** from the silent-arm branch — never from `empty_diff`,
  `unscoped_lane_work`, `asked_into_void`, `timeout`, or any e2e verdict.
- Ordering inside the branch: `_dl_note no_work arm_produced_nothing` **first**, then the
  marker, then the advance, then `exit 5`. The `no_work` row must exist before a second
  worker starts, so the ledger never shows a live lane with no recorded prior attempt.
- Kill switch: `LEADV2_ARM_ADVANCE=0` → probe still classifies (fix 1 intact), advance is
  skipped with `reason=kill_switch`. Fix 1 and fix 2 are independently disableable.

## 4. Data flow (numbered)

1. `dispatch-code cmd_resolve` resolves chain `glm,sonnet`; journals `candidate_chain`.
2. Before spawning, it writes `docs/handoff/dispatch-<sig8>/lane-mission.md`.
3. `arc=0` for `glm` → `spawn_product_close` passes `LEADV2_DISPATCH_CANDIDATE_ARMS`
   and `LEADV2_DISPATCH_LANE_MISSION` alongside today's env. Dispatcher exits 0.
4. glm produces nothing; close gate's `pc_await_worker_exit` returns.
5. `pc_silent_arm_probe` → stream absent, mtime probe n/a, lane clean → **silent**.
6. Close gate writes `review-gate.md`, journals `review_gate … terminal=no_work
   cause=arm_produced_nothing`, calls `_dl_note no_work arm_produced_nothing`.
7. Marker `.arm-advanced-glm` written; next arm = `sonnet`.
8. `dispatch-code advance-arm --arm sonnet …` spawns sonnet on the same worktree and a
   fresh close gate; journals `arm_advance … from=glm to=sonnet`.
9. Close gate exits 5. The e2e gate never ran for the glm attempt.
10. Sonnet's own close gate gates normally. If sonnet is *also* silent, its probe fires,
    writes `.arm-advanced-sonnet`, finds no successor → `chain_exhausted`, lane retires
    `no_work`. A repeat of glm can never happen (marker + no wrap-around).

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| False silent on a slow arm → we kill working work | Probe runs only after `pc_await_worker_exit`; plus mtime growth guard; plus stat-failure is fail-open (not silent). |
| Two close gates alive for one sig8 after an advance | The advancing gate `exit 5`s immediately after spawning; the new gate writes its own close-owner pidfile via `spawn_product_close`'s existing atomic pidfile write (`…:1648-1658`). |
| Infinite advance loop | Per-arm marker + strictly-forward chain walk, no wrap. Two independent bounds. |
| `no_work` row then a landing sonnet run | `no_work` is retryable by design (`ledger.sh:45-51`); write-once only guards `landed|dead`. Verified, not assumed. |
| Skipping `dispatch_reserve` reopens the race the reservation closed | Scoped to `advance-arm`, which requires an existing confirmed row for that sig8; the subcommand must refuse (exit 4, `arm_advance_refused reason=no_confirmed_reservation`) if none exists. |
| New env var naming drift | Both new vars use the `LEADV2_DISPATCH_*` prefix matching the ten existing vars in the same `spawn_product_close` env block. |
| Concurrent access: `${HANDOFF}` is written by worker and close gate | The marker filename is arm-scoped and written only by the close gate; `lane-mission.md` is written only by dispatch-code, before the worker starts. No shared mutable file. |
| bash 3.2 | No `declare -A`, no `${var^^}`, no `mapfile`, no `<<<`. Chain walk uses `IFS=,` + `set --`/positional iteration, not arrays-with-associative-lookup. |

## 6. Non-goals (out of scope for the implementer)

- No change to `leadv2-dispatch-ledger.sh` vocabulary — `no_work` is reused verbatim.
- No change to `leadv2-lane-liveness.sh` / `leadv2-supervise-loop.sh` (supervise is paused).
- No change to `LEADV2_LANE_SILENT_MAX_S` semantics.
- No change to the e2e gate itself, its root resolution, or any existing verdict path.
- No revival of `LEADV2_DISPATCH_REVIEWER_ARMS`.
- No `run-core-offline.sh` execution (founder order); the new suites are *registered*
  in it but run standalone for this lane.
- No commit, push, or merge.

## 7. Tests (all new, all offline, no network, no real worker)

`tests/test-dispatch-silent-arm.sh`
1. no stream file + clean worktree → `review-gate.md` says `arm_produced_nothing`,
   ledger row is `no_work`, and **no** `e2e_gate` line exists in the journal.
2. real stream file with assistant events + real diff → byte-identical verdict to today
   (regression lock).
3. stream file present, worktree clean, mtime = now → **not** silent; falls through to
   today's path.
4. stream file present with zero assistant events, mtime old, worktree clean → silent.

`tests/test-dispatch-arm-advance.sh`
5. silent glm with chain `glm,sonnet` → exactly one `arm_advance from=glm to=sonnet`,
   and `.arm-advanced-glm` exists.
6. re-run the same close gate on the same lane → zero new `arm_advance` lines,
   one `arm_advance_skipped … reason=already_advanced`.
7. silent sonnet at chain tail → `arm_advance_skipped … reason=chain_exhausted`.
8. `LEADV2_ARM_ADVANCE=0` → classification still `no_work/arm_produced_nothing`,
   zero `arm_advance` lines.

Both registered with `run_check` lines in `tests/run-core-offline.sh`.
Syntax gate: `bash -n` and `/bin/bash -n` on every touched `.sh`.
Suites to run and paste in full: the two new suites, plus
`test-dispatch-product-close-exit-trap.sh`, `test-dispatch-ledger-partial-close.sh`,
`test-dispatch-ledger-task-id.sh`, `test-leadv2-dispatch-outcome-ledger.sh`,
`test-t-core-dispatch-ledger.sh`.

acceptance:
  - surface: log_line
    observable: In the dispatch decision journal for a lane whose arm wrote no stream file and left a clean worktree, a human reads "review_gate task=<sig8> status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing" and finds no "e2e_gate task=<sig8>" line anywhere for that lane.
    authored_at: 2026-08-04T00:00:00Z
  - surface: file_artifact
    observable: docs/handoff/dispatch-<sig8>/review-gate.md opens with "status: blocked" and "reason: arm_produced_nothing" naming the arm that stayed silent, instead of the e2e_regression text it shows today.
    authored_at: 2026-08-04T00:00:00Z
  - surface: log_line
    observable: The same lane's journal shows exactly one "arm_advance task=<sig8> from=glm to=sonnet reason=arm_produced_nothing" followed by a "worker_spawned by=arm_advance model=sonnet" line; on a second silence of the same arm the journal instead shows "arm_advance_skipped task=<sig8> arm=glm reason=already_advanced" and no second advance.
    authored_at: 2026-08-04T00:00:00Z
  - surface: log_line
    observable: For a lane whose arm wrote a real stream file with assistant events, the journal is indistinguishable from today's — the same e2e_gate and review_gate lines in the same order, with no arm_produced_nothing and no arm_advance line present.
    authored_at: 2026-08-04T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh, plugins/leadv2/scripts/tests/test-dispatch-arm-advance.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
