# GLM-DIED-WITH-WORK-RESUME-01 — architect prepass

Scope: `~/Projects/leadv2` (canonical plugin). Design only; no implementation.

## 0. Verified ground truth (read on this main)

| Fact | Evidence |
|---|---|
| Classifier writes `outcome: completed\|died-with-work\|died-clean` into `<run_dir>/meta.yaml` + `<run_dir>/.outcome` | `plugins/leadv2/scripts/leadv2-lane-outcome.sh:183-187`, `:171-178` |
| It also writes `outcome_next: continue` for `died-with-work` | `leadv2-lane-outcome.sh:162-166` |
| Both coders call it identically at finalize | `glm-coder.sh:1504`, `kimi-coder.sh:1573` |
| product-close reads `meta.yaml` for `status`/`pid` only — never `outcome` | `leadv2-dispatch-product-close.sh:441-454` |
| Flow after worker exit goes straight to diff gating | `leadv2-dispatch-product-close.sh:831-839` |
| `_PC_ASKED_INTO_VOID` is resolved from `HANDLE` *before* the wait | `leadv2-dispatch-product-close.sh:822-829` |
| glm-coder's internal revive is reachable only from `cmd_supervise` and is gated on `${run_dir}/.stalled` + empty `revived_from` | `glm-coder.sh:1319-1371` |
| The only external launch entrypoints are `bg` / `run`; there is **no** `resume <run_dir>` subcommand | `glm-coder.sh:1560-1580` dispatch table; `kimi-coder.sh:1588` |
| `cmd_bg` calls `glm_launch_gate || exit $?` **before** acquiring the lock, and the gate's real code (1=reroute, 2=peak) propagates | `glm-coder.sh:1561`, `:122-137` |
| `bg` prints the new run-id on stdout; run dir is `${RUNS_DIR}/${run_id}` | `glm-coder.sh:1570-1580`, usage block `:143` |
| The finalize path releases the repo lock before returning, so a fresh `bg` on the same cwd can acquire | `glm-coder.sh:1506` (`release_lock`) |
| `run-core-offline.sh` currently registers **26** suites (`grep -c '^run_check '`) | `plugins/leadv2/scripts/tests/run-core-offline.sh` |
| Test seams already in use by the sibling suite: `GLM_RUNS_DIR`, `KIMI_RUNS_DIR`, `LEADV2_PC_RUNS_ROOT`, `LEADV2_JOB_REGISTRY_ROOT`, `LEADV2_JOURNAL_BIN`, `LEADV2_DISPATCH_LEDGER_BIN` | `tests/test-no-work-terminal.sh:181-418` |

### Key design consequence

**The internal revive path is not callable from outside.** Reaching it would mean fabricating
`${run_dir}/.stalled` and invoking `glm-coder.sh __supervise <run_dir>` — which would re-enter
`cmd_supervise` on an already-finalized run dir, re-fork `__run_child`, re-acquire the lock it
already released, and re-run `finalize_meta` over a completed `meta.yaml`. That is a corruption
path, not a resume path.

The design therefore takes the mission's explicit fallback: **relaunch the worker on the SAME
worktree via the provider's own `bg` entrypoint, with a resume prefix.** This is not a fresh
dispatch (no `leadv2-dispatch-code.sh`, no new lane, no new ledger claim, no new worktree) — it is
the same close gate, the same lane, the same cwd, waiting on a second run handle. Crucially, `bg`
runs `glm_launch_gate` / `kimi_launch_gate` itself, so **quota-gate parity is obtained by
construction**, not by re-implementing the gate call in product-close.

---

## 1. Layers affected

| Layer | Change |
|---|---|
| `leadv2-dispatch-product-close.sh` | New helper block + one call site between worker-exit and diff scoping |
| `leadv2-lane-outcome.sh` | **none** (non-goal 5) |
| `glm-coder.sh` / `kimi-coder.sh` | **none** — consumed through the existing `bg` contract |
| `leadv2-dispatch-code.sh` | **none** — hard non-goal (LANDED-AT-SPAWN-01 may be in flight) |
| `tests/` | one new suite + one registration line |

---

## 2. Data flow (numbered)

1. `pc_await_worker_exit` returns 0 — the first worker (`HANDLE`, `AUTHOR`) is provably finished.
2. **[NEW]** `pc_dwr_resume_once` runs. Fast-exits (return 1 = "no resume happened") when any of:
   - `LEADV2_PC_DWR_RESUME` != `1` (kill switch), or
   - `AUTHOR`/`HANDLE` empty, or
   - the resolved run dir has no `meta.yaml`, or
   - `outcome:` from that `meta.yaml` is anything other than `died-with-work`, or
   - `${HANDOFF}/.dwr-resume-attempted` already exists.
3. Otherwise: read `cwd`, `max_turns`, `timeout` from the dead run's `meta.yaml`; require `cwd` to
   be an existing directory (else `launch_failed reason=no_cwd`).
4. Build `${HANDOFF}/.dwr-resume-prompt.txt` = a 4-line resume prefix + verbatim
   `<old_run_dir>/prompt.txt`. If `prompt.txt` is missing/empty → `launch_failed reason=no_prompt`.
5. **Write the marker `${HANDOFF}/.dwr-resume-attempted` BEFORE launching** (content:
   `from_run=<id>`, `at=<iso8601>`, `by=<pid>`). Ordering is deliberate: a crash between marker and
   launch costs one lost resume; the reverse ordering costs an unbounded resume loop.
6. Launch: `bash <launcher> bg "@${HANDOFF}/.dwr-resume-prompt.txt" --cwd <cwd> --max-turns <n>
   --timeout <s>`, stdout+stderr captured to `${HANDOFF}/.dwr-resume-launch.log`, rc captured with
   `|| rc=$?` (never `!`, so gate codes survive — same idiom as `glm-coder.sh:1349`).
7. Classify the launch:
   - `rc == 0` **and** stdout yields a run-id matching `^[0-9]{6}-[0-9]{6}-` → `new_run=<id>`.
   - `rc` in `1,2` → `new_run=blocked_by_gate` (the quota gate refused, exactly as
     `REVIVE_BLOCKED_BY_GATE` does internally).
   - any other non-zero rc (incl. `75` lock-busy), or rc 0 with no parseable run-id →
     `new_run=launch_failed`.
8. Journal one line in all three cases (§4).
9. On success only: `HANDLE="${new_run_id}"`, re-resolve `_PC_ASKED_INTO_VOID` from the new handle,
   then re-enter `pc_await_worker_exit` under the second-wait budget. On `blocked_by_gate` /
   `launch_failed`: fall through untouched — gating proceeds on the partial diff exactly as today.
10. `pc_scope_diff` and everything downstream run unchanged, on whatever the final tree holds.

### Text diagram

```
pc_await_worker_exit (run A)
        |
        +-- ret 1 (ceiling) --> worker_timeout branch  [UNCHANGED]
        |
       ret 0
        |
  [NEW] pc_dwr_resume_once
        |
        +-- not died-with-work / marker present / kill switch --> (no-op)
        |
        +-- died-with-work, first time
                |
                +-- write marker
                +-- <author>-coder.sh bg @resume-prompt --cwd <same worktree>
                        |
                        +-- gate refuses (rc 1|2) --> journal blocked_by_gate --> (no-op)
                        +-- launch fails            --> journal launch_failed  --> (no-op)
                        +-- run B started           --> journal new_run=B
                                                        HANDLE=B
                                                        re-resolve _PC_ASKED_INTO_VOID
                                                        pc_await_worker_exit (run B)
                                                            |
                                                            +-- ret 1 --> worker_timeout [UNCHANGED]
                                                            +-- ret 0 --> fall through
        |
   pc_scope_diff  --> e2e --> review   [UNCHANGED]
```

Second death of any kind produces no third run: the marker was written in step 5 and
`pc_dwr_resume_once` is called exactly once, unconditionally, from one call site.

---

## 3. Interface contracts

### 3a. New functions in `leadv2-dispatch-product-close.sh`

| Function | Args | Returns | Side effects |
|---|---|---|---|
| `_pc_run_dir_for` | `<author> <handle>` | run dir path on stdout (empty if unresolvable) | none |
| `_pc_resolve_asked_into_void` | — | — | sets global `_PC_ASKED_INTO_VOID` from current `AUTHOR`/`HANDLE` (extracted from today's inline block at `:822-829`, called there **and** after a successful resume) |
| `_pc_lane_outcome` | `<run_dir>` | `completed\|died-with-work\|died-clean\|""` on stdout | none; reads `meta.yaml` via existing `_pc_meta_value`, falls back to `<run_dir>/.outcome` (`outcome=` form) when `meta.yaml` lacks the key |
| `_pc_resume_launcher_for` | `<author>` | absolute path to `<author>-coder.sh` on stdout, empty if not a regular file | none |
| `pc_dwr_resume_once` | — | `0` = a resume was launched and `HANDLE` was reassigned; `1` = no resume | may write marker, prompt file, launch log; may `emit decision`; may mutate globals `HANDLE`, `_PC_ASKED_INTO_VOID` |

`_pc_lane_outcome` is the **generic** key. Nothing in the decision reads a provider name; the
provider name is used only to resolve *where the run dir is* and *which launcher exists* — both of
which are already provider-keyed in this file today (`:823-828`). Any future provider that calls
`leadv2-lane-outcome.sh` and ships `<name>-coder.sh` with a `bg` subcommand inherits this behaviour
with zero further edits (`_PC_RUNS_ROOT/<author>-runs/<handle>` is already the generic fallback at
`:827`).

### 3b. Provider `bg` contract consumed (must not be broken by any implementer)

```
bash <author>-coder.sh bg "@<prompt-file>" --cwd <dir> --max-turns <int> --timeout <int>
  stdout : one line, the new run-id
  rc 0   : launched
  rc 1|2 : quota gate refused (reroute | peak)
  rc 75  : repo lock busy
  other  : launch failure
```
Verified against `glm-coder.sh:1519-1580` and `kimi-coder.sh:1588-1661`; both accept `@file` for
the prompt (both write `${run_dir}/prompt.txt` from a `resolved_prompt`).

### 3c. New env vars (all `LEADV2_*`, per convention)

| Var | Default | Meaning |
|---|---|---|
| `LEADV2_PC_DWR_RESUME` | `1` | Kill switch. `0` ⇒ `pc_dwr_resume_once` returns 1 immediately; behaviour is byte-for-byte today's. |
| `LEADV2_PC_RESUME_LAUNCHER_BIN` | *(empty)* | Test seam — overrides `_pc_resume_launcher_for` with a stub launcher for all providers. |
| `LEADV2_PC_RESUME_MAX_WAIT_S` | value of `LEADV2_PC_WORKER_MAX_WAIT_S` (itself 4200) | Ceiling for the **second** wait only. Exported into the re-entered `pc_await_worker_exit` by assigning `LEADV2_PC_WORKER_MAX_WAIT_S` for the second call. |

Checked for collisions: no existing `LEADV2_PC_DWR_*`, `LEADV2_PC_RESUME_*`, or `LEADV2_*_RESUME_*`
usage anywhere in the plugin. `LEADV2_PC_WORKER_MAX_WAIT_S` semantics are unchanged for the first
wait.

### 3d. File artifacts (all under the existing `${HANDOFF}` = `${ROOT}/docs/handoff/dispatch-${TASK}`)

| Path | Written when | Content |
|---|---|---|
| `.dwr-resume-attempted` | before the launch attempt, once per lane | `from_run=<id>`\n`at=<iso>`\n`by=<pid>` |
| `.dwr-resume-prompt.txt` | before the launch attempt | resume prefix + verbatim original `prompt.txt` |
| `.dwr-resume-launch.log` | at the launch attempt | combined stdout/stderr of the `bg` call |

These are runtime artifacts under an already-gitignored/`--exclude`d tree
(`_pc_git_diff` excludes `docs/handoff` at `:654-660`), so they cannot pollute the lane diff.

---

## 4. Journal contract

Exactly one `decision` line per lane, grammar as specified by the mission:

```
dwr_resume task=<sig8> from_run=<run_id> new_run=<run_id>
dwr_resume task=<sig8> from_run=<run_id> new_run=blocked_by_gate rc=<1|2>
dwr_resume task=<sig8> from_run=<run_id> new_run=launch_failed rc=<n> reason=<no_cwd|no_prompt|no_launcher|bad_rc|no_run_id>
```

Emitted via the file's existing `emit decision "..."` (`:173-176`), so it lands in the lead's
journal and on stderr. The `rc=`/`reason=` suffixes are additive — the required
`dwr_resume task= from_run= new_run=` prefix is byte-identical in all three forms, so a grep on the
required grammar matches every case.

No line is emitted when no resume was considered (outcome != died-with-work, kill switch off) —
silence stays the normal case. When the **marker** short-circuits a second resume, emit
`dwr_resume task=<sig8> from_run=<run_id> new_run=skipped reason=already_attempted` so the "we
deliberately did not resume twice" decision is visible rather than invisible.

---

## 5. DB changes

None. This system has no database; `meta.yaml` is the only state surface touched, and it is
**read-only** here.

## 6. Migration plan

No migration. The change is additive and self-disabling:
- lanes whose meta predates the classifier have no `outcome:` key ⇒ `_pc_lane_outcome` returns
  empty ⇒ no resume;
- `sonnet`/`codex` authors have no `<author>-coder.sh` ⇒ `_pc_resume_launcher_for` returns empty ⇒
  `launch_failed reason=no_launcher` is **not** emitted (guard before the marker write, so those
  authors are a pure no-op with no journal noise);
- `LEADV2_PC_DWR_RESUME=0` restores the exact current behaviour in one flip.

Rollback: `git checkout` of the three touched files.

---

## 7. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Unbounded resume loop** if the marker write is skipped or races. | Marker written **before** launch, in `${HANDOFF}` which is per-lane and stable; `pc_dwr_resume_once` has exactly one call site and no loop around it. Worst case on marker-write failure: treat write failure as `launch_failed reason=marker_write` and do **not** launch — fail closed, never loop. |
| R2 | **Close-gate wall clock doubles** (4200s → 8400s worst case), stretching the lane's lease and the founder's wait. | Second wait uses `LEADV2_PC_RESUME_MAX_WAIT_S` (own knob, default equal to the first). `_pc_refresh_founder_lease` already runs inside `pc_await_worker_exit` and will keep extending the claim across the second wait — no lease expiry regression. Document the doubled ceiling in the script header. |
| R3 | **Double preamble** — the resume prompt is the already-wrapped `prompt.txt` (AGENT_BAN_PREAMBLE + FINISH_CONTRACT_TRAILER at `glm-coder.sh:1592`), and `bg` wraps again. | Accepted: the duplicated text is the same ban/contract boilerplate, idempotent in meaning. Reconstructing the raw mission from `${HANDOFF}` would be less faithful to what the worker actually ran. Flagged for the critic as a known, deliberate cost. |
| R4 | **Repo lock still held** by the dying run ⇒ `bg` exits 75. | `release_lock` runs in the coder's finalize path (`glm-coder.sh:1506`) and `pc_await_worker_exit` returned only after terminal provider evidence, so the lock is released in the normal case. If it is not, rc 75 is classified `launch_failed` and gating proceeds — no hang, no retry. |
| R5 | **`_PC_ASKED_INTO_VOID` points at the dead run** after `HANDLE` is reassigned ⇒ a stale `.asked_into_void` from run A would park a lane that run B unblocked. | The resolution block at `:822-829` is extracted into `_pc_resolve_asked_into_void` and re-invoked after every successful resume. This is a **required** part of the change, not an optional cleanup. |
| R6 | **Concurrent access to `${HANDOFF}`**: this close gate writes the marker while a resumed worker writes deliverables into the same directory. | Distinct filenames, no shared file. The only true race would be two close gates for the same `TASK` — already prevented by the `dispatch-close-owner/<sig8>.pid` ownership record (`:85-115`). No new lock needed; note the reliance explicitly. |
| R7 | Resume launched while the founder task lease is mid-refresh. | `_pc_refresh_founder_lease` is idempotent and best-effort (`:470-496`); the resume does not touch `docs/tasks.yaml`. |
| R8 | `bg` inherits the close gate's environment, including any test seams. | Intentional and required for the test suite; in production the close gate's env is the dispatch env, which is what a fresh worker should see. |
| R9 | `outcome:` appears **twice** in `meta.yaml` if a run were classified twice. | `_pc_meta_value` uses `head -n 1` (`:373-375`) — first-wins, deterministic. Classifier appends once per run (`leadv2-lane-outcome.sh:183-187`). |
| R10 | Resumed run is itself killed by the same stall guard, producing another `died-with-work`. | By design: marker present ⇒ `new_run=skipped reason=already_attempted` ⇒ gate the partial diff. Exactly once, as specified. |

### Mandatory constraint checklist

1. **Env-var naming** — `LEADV2_PC_DWR_RESUME`, `LEADV2_PC_RESUME_LAUNCHER_BIN`,
   `LEADV2_PC_RESUME_MAX_WAIT_S`: all `LEADV2_*`, all matching the file's existing `LEADV2_PC_*`
   family. No `LEAD_V2_*` drift. ✅
2. **File paths** — all three write targets verified on disk except the new suite, marked
   `(to-create)`. ✅
3. **`claude -p`** — none introduced. N/A. ✅
4. **Concurrent access** — R6 above; no new lock required, existing close-owner pidfile covers it. ✅
5. **Config contradiction** — grepped: no prior `DWR`/`RESUME` env usage in the plugin;
   `LEADV2_PC_WORKER_MAX_WAIT_S` semantics unchanged for the first wait, deliberately reused (by
   assignment, not redefinition) for the second. ✅

---

## 8. Test plan

New suite **`plugins/leadv2/scripts/tests/test-dwr-resume.sh` (to-create)**, modelled on
`test-no-work-terminal.sh` (same `ok`/`bad`/`assert_eq` helpers, same `new_repo`/`make_stubs`
sandbox idiom, same `GLM_RUNS_DIR` / `KIMI_RUNS_DIR` / `LEADV2_PC_RUNS_ROOT` /
`LEADV2_JOB_REGISTRY_ROOT` / `LEADV2_JOURNAL_BIN` / `LEADV2_DISPATCH_LEDGER_BIN` seams).

Stub launcher (`LEADV2_PC_RESUME_LAUNCHER_BIN`): records its argv to a file, seeds a new run dir
with `status: complete` + `outcome: completed` under the fake runs root, prints the new run-id,
exits with a per-case configurable rc.

| Case | Setup | Assertion |
|---|---|---|
| (a) resume once | glm meta `outcome: died-with-work`, no marker, stub rc 0 | stub invoked exactly once; argv contains `bg`, `--cwd <worktree>`; `.dwr-resume-attempted` exists; journal has `dwr_resume ... new_run=<newid>`; gating ran on the final tree |
| (b) marker present | same, but `.dwr-resume-attempted` pre-created | stub invoked **zero** times; journal has `new_run=skipped reason=already_attempted`; gating proceeded |
| (c) not eligible | two sub-cases: `outcome: completed`, `outcome: died-clean` | stub invoked zero times; **no** `dwr_resume` line at all; terminal row identical to a run without the feature |
| (d) gate refuses | `outcome: died-with-work`, stub rc 2 | journal has `new_run=blocked_by_gate rc=2`; no `HANDLE` reassignment; partial diff still gated (review/e2e path runs, terminal row written as today) |
| (e) kimi parity | `AUTHOR=kimi`, `KIMI_RUNS_DIR` meta with `outcome: died-with-work` | identical to (a); proves the decision keys off `outcome:`, not the provider name |

Extra (cheap, worth having): (f) `LEADV2_PC_DWR_RESUME=0` with a died-with-work meta ⇒ stub zero
invocations, no journal line — proves the one-flip rollback.

**Registration:** one `run_check "product-close resumes a died-with-work lane once" bash
"$TEST_DIR/test-dwr-resume.sh"` line in `run-core-offline.sh`, placed immediately after the existing
`"product-close waits for worker exit"` line. Baseline on this main is **26** `run_check` entries →
expected **27** after the change. `syntax_all` picks up the new file automatically (it globs
`*.sh` under the plugin root), so `bash -n` coverage needs no separate wiring.

**Portability:** the suite must run under both bash 5 and `/bin/bash` 3.2 — no `declare -A`, no
`${var,,}`, no `mapfile`, no `[[ -v ]]`. Same constraint applies to the production edit.

---

## 9. Out of scope (implementer: ignore these)

- Any edit to `leadv2-lane-outcome.sh` — classification is correct and stays as-is.
- Any edit to `glm-coder.sh` / `kimi-coder.sh`, including the internal `revived_from` machinery.
- Any edit to `leadv2-dispatch-code.sh` — **hard stop**, LANDED-AT-SPAWN-01 may be in flight in
  another lane.
- Write-once ledger semantics, `_dl_note`, `_PC_TERMINAL_*` — untouched. A resumed lane simply
  reaches its terminal row later, and the row is whatever the final diff earns.
- Multi-resume, exponential backoff, resume budgets — exactly once, marker-guarded.
- Supervisor, `leadv2-supervise*`, SwiftBar/status-surface changes.
- Making the internal stall-revive externally callable (rejected in §0 — corruption path).
- Committing. The implementer reports; the lead commits.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      In the lead's journal for a lane whose run meta says outcome: died-with-work,
      a line reading "dwr_resume task=<sig8> from_run=<old run id> new_run=<new run id>"
      appears after the first worker finishes and before any review/e2e verdict for
      that lane, and the lane's close gate then goes on to report a verdict about the
      SECOND run's work rather than burying the first run's partial diff.
    authored_at: 2026-08-03T16:30:23Z
  - surface: file_artifact
    observable: >
      The lane's handoff directory docs/handoff/dispatch-<sig8>/ contains a file named
      .dwr-resume-attempted recording the run id the resume came from and a timestamp;
      on a lane that died a second time, that file is still the only one and no second
      resume line appears in the journal.
    authored_at: 2026-08-03T16:30:23Z
  - surface: log_line
    observable: >
      When the quota gate refuses the resume, the journal shows
      "dwr_resume task=<sig8> from_run=<old run id> new_run=blocked_by_gate" and the
      lane still receives its normal review/e2e verdict on the partial work instead of
      stalling or silently disappearing.
    authored_at: 2026-08-03T16:30:23Z
  - surface: log_line
    observable: >
      A full run of the offline core suite prints 27 named checks with zero FAILED and
      zero MISSING lines, one of which is the new product-close resume suite, and the
      26 checks that existed before the change all still report as passing.
    authored_at: 2026-08-03T16:30:23Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-dwr-resume.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
