# PREMATURE-NO-WORK-TERMINAL-01 — architect prepass

## 0. The writer (found)

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

| ref | what |
|---|---|
| **:550** | `_pc_terminal="no_work"; _pc_cause="empty_diff"; _pc_rg_reason="no_work"` — the exact line that produced the ledger row |
| :559 | `printf 'status: blocked\nreason: %s\n...' > "${HANDOFF}/review-gate.md"` — the empty `review.diff` + `reason: no_work` artifact |
| :561 | `_dl_note "${_pc_terminal}" "${_pc_cause}"` → `leadv2-dispatch-ledger.sh write-terminal` → the jsonl row |
| :539 | `[[ -s "${diff_file}" ]] || blocked_reason="unscopable_diff"` — the measurement whose result was `empty` |
| :584 | `pc_scope_diff` — called unconditionally, immediately on process start |

**Root cause — :353-355:**

```bash
# Wait only for a positively known local PID. Other providers may expose only a durable
# job/run handle, so their lifecycle owner writes the close evidence; we never guess done.
if [[ "${AUTHOR}" == sonnet && "${HANDLE}" =~ ^[0-9]+$ ]]; then
  while kill -0 "${HANDLE}" 2>/dev/null; do sleep 2; done
fi
```

The close gate blocks on worker exit **only** for `AUTHOR == sonnet` with a numeric PID handle.
`leadv2-dispatch-code.sh:1499` (`spawn_product_close`) backgrounds this script the moment the
worker is *launched*, for every arm. For `codex` (handle = codex-companion job id
`task-mscze7da-7gcurn`), `glm`, and `kimi` there is **no wait at all** — `pc_scope_diff` runs
milliseconds after the worker starts, sees an untouched worktree, and writes
`no_work/empty_diff`. That is exactly the 0814b8c0 evidence: terminal at 08:42:49Z, worker
still running 1h42m later with 94 lines of diff in the same worktree.

The comment's premise ("their lifecycle owner writes the close evidence") is false — *this*
script is the terminal-row owner for product spawns (its own header, :30-34, says so, and
`dispatch-code.sh cmd_resolve` deliberately writes none).

## 1. Design — provider-aware `pc_await_worker_exit()`

One new function in the same file, called **immediately before** `pc_scope_diff` (:584),
replacing the :353-355 block. Everything downstream is untouched — requirement 2 is satisfied
by *ordering alone* (the diff is scoped after the await returns, i.e. at worker exit, not at
watcher wake-up). No change to `pc_scope_diff`'s body.

### 1.1 Liveness probes (per arm)

| arm | handle shape | alive test | source of truth |
|---|---|---|---|
| `sonnet` | numeric pid | `kill -0 "${HANDLE}"` | unchanged (:354) |
| `codex` | `task-<id>` job id | `leadv2-lane-liveness.sh --job "${HANDLE}" --json` → `verdict` starts with `alive` | authoritative-provider-status tool (`leadv2-lane-liveness.sh:385-420`, maps codex-task.sh status `queued|running` → alive, `completed\|done\|cancelled\|failed` → dead) |
| `glm` / `kimi` | run_id (run dir basename) | `${RUNS_DIR}/${HANDLE}/meta.yaml` has `status: running` **AND** its `pid:` is alive via `kill -0` | `glm-coder.sh:390-406` / `kimi-coder.sh` `write_meta_initial`; finalised to `complete`/`failed` at `glm-coder.sh:1432/1468` |
| any arm | job-registry corroboration | `/tmp/leadv2-job-registry/*/${HANDLE}` present | `codex-task.sh:933-947`, `glm-coder.sh:1577`, `kimi-coder.sh:1646`; entry removed on worker exit (`glm-coder.sh:1510`, `kimi-coder.sh:1579`, codex EXIT trap) |
| empty/unknown handle, unknown arm | — | **not alive** (no probe possible) | see risk R3 |

Alive = `provider_says_running` **AND** `process_handle_present`, per requirement 1
("provider-status/job-registry says done AND the launch handle's process is gone"). Either
signal saying *dead* is not enough on its own; the loop exits only when **both** say gone.
Rationale: the job-registry entry disappears on a wrapper crash while the real child lives,
and meta.yaml can lag the process by seconds.

### 1.2 Control flow

```
pc_await_worker_exit():
  [[ ${LEADV2_PC_AWAIT_WORKER:-1} == 1 ]] || return 0        # one-flip revert
  deadline = now + LEADV2_PC_WORKER_MAX_WAIT_S   (default 5400)
  loop:
    pc_worker_alive || return 0                              # provably finished -> proceed
    now >= deadline -> return 1                              # timed out while alive
    emit decision "product_close task=${TASK} status=waiting_worker author=${AUTHOR} handle=${HANDLE} waited=<s>"   # throttled: first tick + every LEADV2_PC_WORKER_LOG_EVERY_S (default 300)
    sleep ${LEADV2_PC_WORKER_POLL_S:-10}
```

Call site (replaces :353-355 region, sits just above `pc_scope_diff` at :584 so
`_PC_ASKED_INTO_VOID` resolution still precedes it):

```
if ! pc_await_worker_exit; then
  printf 'status: blocked\nreason: worker_timeout\nbase: %s\n' "${_pc_base_used:-HEAD}" > "${HANDOFF}/review-gate.md"
  emit decision "review_gate task=${TASK} status=blocked reason=worker_timeout terminal=dead cause=timeout"
  _dl_note dead timeout "waited=${_waited}s author=${AUTHOR} handle=${HANDLE}"
  _stamp_review_terminal blocked
  exit 5
fi
pc_scope_diff
```

`dead/timeout` is the only terminal the timeout path may write — never `no_work`. `exit 5`
keeps the existing caller contract.

### 1.3 New env vars (all `LEADV2_*`, checked against existing naming)

| var | default | purpose |
|---|---|---|
| `LEADV2_PC_AWAIT_WORKER` | `1` | kill switch, `0` = exact pre-fix behaviour |
| `LEADV2_PC_WORKER_POLL_S` | `10` | poll interval |
| `LEADV2_PC_WORKER_MAX_WAIT_S` | `5400` | hard ceiling → `dead/timeout` |
| `LEADV2_PC_WORKER_LOG_EVERY_S` | `300` | journal throttle for the waiting line |
| `LEADV2_LANE_LIVENESS_BIN` | `${SCRIPT_DIR}/leadv2-lane-liveness.sh` | test seam for the codex probe |

`LEADV2_PC_RUNS_ROOT`, `GLM_RUNS_DIR`, `KIMI_RUNS_DIR` already exist (:576-583) — **reuse
them, do not introduce a second runs-root resolution**. No `LEAD_V2_*` drift; no existing
grep hit for any of the five new names.

## 2. Requirement 3 — why the false terminal caused the duplicate dispatch

Chain, as evidenced by `d7cf9e71` and `0814b8c0` carrying the **same** `task_id`
(`FEED-SCAN-USABLE-CANDIDATES-01`) under **different** `task_sig`s:

1. `no_work` is in the **retryable** terminal class (same bucket as `refused`/`parked`,
   per the `leadv2-dispatch-ledger.sh` taxonomy referenced at product-close.sh:544-547).
2. A retryable terminal releases the founder-task claim (product-close's EXIT trap unclaims
   `FOUNDER_TASK_ID`) and returns the task to the dispatchable pool.
3. The duplicate-dispatch guard is keyed on **task_sig** = hash of the mission text
   (`cmd_resolve`: `sig="$(printf '%s' "${mission}" | compute_sig)"`, sig8 = first 8 hex).
   Re-dispatch regenerates the mission → different text → different sig → **different sig8**
   (`d7cf9e71` vs `0814b8c0`). The guard is structurally incapable of firing on a
   re-dispatch of the same *task_id*.
4. Result: a second worker on a task whose first worker never stopped — the audited
   supervisor-era "empty dispatch" disease, now reproduced from inside the close watcher.

**Requirement 1 closes it at step 1:** no `no_work` row is emitted while the worker is alive,
so the claim is never released, so step 2 never happens and the sig-keyed guard is never asked
a question it cannot answer. The guard itself needs **no change** — it was never the hole.

*Implementer must verify, not assume:* confirm the guard's key by reading it
(`leadv2-dispatch-ledger.sh` reserve/claim path + `leadv2-dispatch-code.sh`
`atomic_dispatch_reserve_spawn_confirm`) and report the **file:line** proving it is sig8-keyed
with no task_id-keyed sibling. If a task_id-keyed guard *does* exist, that is a finding to
report — it does not change this design.

## 3. Tests — `plugins/leadv2/scripts/tests/test-no-work-terminal.sh` (extend)

The suite already has a `glm`-free harness; add a `fake_glm_run()` helper that materialises
`${RUNS}/glm-runs/<handle>/meta.yaml` with `status: running` + `pid: <pid of a background
sleep>`, plus the `/tmp/leadv2-job-registry/<sid>/<handle>` line. Drive product-close with
`AUTHOR=glm HANDLE=<handle>` and `LEADV2_PC_RUNS_ROOT` / `GLM_RUNS_DIR` pointed at the sandbox.
Existing cases 1-3 stay byte-identical (they use `sonnet` with an empty handle → probe says
not-alive → await returns immediately → same behaviour).

| case | setup | assertion |
|---|---|---|
| 4 — **alive → no terminal** | stub sleeps 30s, meta `status: running`, live pid; run close in background, wait ~5s | `review-gate.md` **absent**, journal has **no** `terminal=no_work`, journal **does** have `status=waiting_worker` |
| 5 — **diff at exit, not at wake** | same, but stub writes to a LANE_WRITES path then exits | after close finishes: terminal is **not** `no_work`; `review.diff` is non-empty |
| 6 — **genuinely empty → allowed** | stub exits immediately, writes nothing | `terminal=no_work cause=empty_diff`, exit 5 (regression guard for the existing behaviour on the glm arm) |
| 7 — **timeout while alive** | stub sleeps 30s, `LEADV2_PC_WORKER_MAX_WAIT_S=2`, `LEADV2_PC_WORKER_POLL_S=1` | terminal `dead` cause `timeout`, review-gate `reason: worker_timeout`, **never** `no_work` |
| 8 — **codex probe seam** | `LEADV2_LANE_LIVENESS_BIN` → stub emitting `{"verdict":"alive"}` twice then `{"verdict":"dead:provider_completed"}` | close waits ≥2 polls then proceeds; asserts the codex branch actually calls the liveness tool |

Every stub must be reaped in the case's teardown (`kill`+`wait`) so a failing assertion cannot
leave a 30s sleep behind.

Register the suite in `plugins/leadv2/scripts/tests/run-core-offline.sh` (currently 22
`run_check` lines; `test-no-work-terminal.sh` is **not** among them — it has never run in
core-offline). **Baseline note:** this makes the suite count 23, so the
CORE-OFFLINE-8-FAILS-ON-MAIN-01 baseline comparison must be "same 8 pre-existing failures,
one additional passing suite" — not "same total".

## 4. Concurrency / race surface

| surface | risk | mitigation |
|---|---|---|
| `review.diff` | close gate reads while the worker writes the tree | this fix *is* the mitigation — the read now happens strictly after worker exit |
| close-owner pidfile | already atomic (temp+rename, :112-118) | none needed; the longer-lived close process makes the sweep's liveness check *more* accurate, not less |
| `_dl_note` write-once + EXIT-trap retry | a long await widens the window in which a kill lands before any terminal | already handled: the EXIT trap writes `dead/crashed_unfinished` when `_PC_TERMINAL_STATE` is empty; that is a **correct** terminal for a killed close gate |
| worktree shared with a concurrent lane | HEAD can move during a long await | already handled by the `LANE_START_SHA` base ladder (S-3 round 3) |

## 5. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | Close gates now live for the worker's whole lifetime (hours) instead of seconds → many more long-lived bash processes | bounded by `LEADV2_PC_WORKER_MAX_WAIT_S`; one process per lane, same count as today, only longer-lived; the close-owner pidfile the ledger sweep reads is already refreshed |
| R2 | A wedged probe (codex-task.sh hanging) stalls the await | wrap the liveness shell-out in `timeout 20`; a probe that fails to answer counts as **alive** (conservative — never a false terminal), and the `MAX_WAIT_S` ceiling still bounds it |
| R3 | Unknown arm / empty handle → no probe → treated as "not alive" → today's behaviour (may still write a premature `no_work`) | **Explicit assumption:** every real product spawn passes a handle (`spawn_product_close` arg 3). Treating unknown as not-alive preserves today's semantics for direct/manual invocations and tests instead of hanging them for 90 minutes. Journal `worker_liveness=unknown` on that path so it is greppable if it ever fires in production. Flagged for the founder as the one place the "provably finished" rule is relaxed. |
| R4 | `LEADV2_PC_WORKER_MAX_WAIT_S=5400` may be shorter than a real codex worker's timeout → a healthy lane closes as `dead/timeout` | pick the default by reading the actual worker timeout in `codex-task.sh`/`glm-coder.sh` (`timeout_s`) and set the ceiling to **worker timeout + 10 min** grace; if they disagree, take the max and say so in the report |
| R5 | Adding the suite to run-core-offline shifts a count another test asserts | grep for suite-count assertions before adding; if one exists, update it in the same diff |

## 6. Non-goals (implementer: ignore)

- No admission-guard, kimi-arm, SwiftBar, or supervisor-loop changes.
- No change to the duplicate-dispatch guard itself (§2 — verify only).
- No change to `pc_scope_diff`'s diff-scoping logic, the base ladder, the e2e gate, or the
  review-arm pool.
- No change to the ledger's terminal taxonomy or to `no_work`'s retryable classification.
- No commit, no push.

## 7. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >-
      For a lane whose worker process is still running, the file
      docs/handoff/dispatch-<sig8>/review-gate.md does not exist. Opening the lane's
      handoff directory while the worker is mid-run shows no review-gate.md and no
      review.diff at all.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >-
      The dispatch journal for a still-running codex/glm/kimi lane shows a line reading
      "product_close task=<sig8> status=waiting_worker author=<arm> handle=<handle>"
      instead of "review_gate ... terminal=no_work cause=empty_diff".
    authored_at: 2026-08-03T00:00:00Z
  - surface: prod_db_row
    observable: >-
      The dispatch ledger jsonl contains no row with terminal "no_work" and cause
      "empty_diff" whose timestamp precedes its own worker's exit; a worker that ran past
      the ceiling appears instead as terminal "dead", cause "timeout".
    authored_at: 2026-08-03T00:00:00Z
  - surface: file_artifact
    observable: >-
      After a worker that wrote 94 lines into a LANE_WRITES path exits, the lane's
      review.diff is non-empty and review-gate.md either is absent or reads a reason other
      than no_work.
    authored_at: 2026-08-03T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-no-work-terminal.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
