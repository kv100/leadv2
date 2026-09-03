# CONTROL-PLANE-HAS-NO-OWNER-01 — architect brief

Nothing owns lane state. The lead's first version of this brief counted five mechanisms; the
census below (every claim verified against a file:line on `main` at `ab9fe5ca`, 2026-09-03) finds
**24 code paths across 9 physical stores** that each hold a piece of "is this lane alive and where
is its work", written through **three different APIs plus two direct file mutations**, with
**eight independent liveness-verdict engines** that can disagree. Every expensive failure of the
last two days is a symptom of that single absence.

Estimated 3–5 days. Founder granted the lead autonomy over how to do it (2026-09-03).

**Barrier cleared.** The five-day sweep is delivered — `docs/handoff/FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01/VERDICT.md`
(commit `c0820151`). Its headline — *32 of 35 features are live only because they patched
already-wired files; every dead one was a new standalone script nobody calls* — is the binding
design constraint here: **the owner is three files already on the dispatch path, extended; the
task deletes mechanisms, and adds none.**

Path shorthand used throughout: `S/` = `plugins/leadv2/scripts/`.

## 1. The symptoms, all measured 2026-09-02..03

These are not five bugs. They are five views of one missing owner. Column 4 is what the census
found underneath each — the lane must re-verify it against a live row, not trust it.

| # | symptom | measured | root mechanism (verified file:line) |
|---|---|---|---|
| 1 | **The registry stamps the lead's PID, not the worker's.** A lane looks alive because the lead is alive. | `LANE-REGISTRY-STAMPS-THE-LEAD-PID-01` | Two writer APIs fight over the same row key `pid`. `S/leadv2-active-registry.sh:440-460` writes `pid`=dispatcher, `pid_role=lead_durable`, then `set_worker_pid` (`:734`, `:1097`) adds `worker_pid`/`worker_pid_role`. But `S/lib/leadv2-lane-state.sh:95` (`register` op, `existing.update(pid=pid, ...)`) overwrites `pid` with whatever `lane_register`/`lane_adopt_pid` was handed — the dispatcher's `$$` at `S/leadv2-dispatch-code.sh:7073` (`DISPATCH_SLOT_PID:-$$`) and the **watcher** pid at `:5704-5705` — and never touches `pid_role`. Also `S/leadv2-helpers.sh:628` (lock acquire) and `S/leadv2-gate1-prompt.sh:64,132` register the lead's own durable pid as a lane row. |
| 2 | **Liveness is read from log freshness, not from the registry.** Unregistering a row from `active.yaml` changes nothing. | verified by hand: row removed, `lane_placement_refused reason=lane_is_live` continued | `S/leadv2-lane-liveness.sh:1-3` says it in its own header: "the lane's output log is the primary signal; active.yaml supplies only the optional process identity". With no row it still resolves a stream via the lane-local `dispatch.json` (`:784`) and issues `alive` on `log_fresh` (`:964`). The refusal is emitted at `S/leadv2-dispatch-code.sh:1082` from that verdict. |
| 3 | **A worker outlives its own terminal state.** `terminal=no_work cause=empty_diff` written while the worker went on to produce 52 lines. Three more reproductions the same day. | `WORKER-OUTLIVES-ITS-TERMINAL-STATE-01`, lanes `8b995f4a` / `d7c0721d` / the WORKER-OUTLIVES lane itself | `S/leadv2-dispatch-product-close.sh:2408` decides `no_work/empty_diff` from the diff alone; `_dl_note` (`:168`) records it; nothing in the funnel `dispatch_ledger_write_terminal` (`S/leadv2-dispatch-ledger.sh:291`) checks that the producer is gone. `adf89c9b` bolted a **sonnet-only** TERM/KILL of the worker and its `finalizer_pid` onto product-close (`+94` lines) — a point fix for one arm, ungated (`SD-WORKER-OUTLIVES-VERIFY-01`). |
| 4 | **A live process holding the stream deadlocks re-dispatch.** `silent_max` is 900s and the file never goes quiet, so the lane is permanently `lane_is_live`. Only killing the PID by hand freed it. | `LANE-REGISTRY-SELF-DEADLOCK-01`, named in code | Liveness has no notion of *progress* — only stream age (`:905 is_fresh = age_s <= silent_max`) and pid state. A worker that writes bytes forever is `alive` forever (`:964`), and no mechanism ever reaps an alive-but-stuck worker: the ledger sweep only acts on `dead:*` (`S/leadv2-dispatch-ledger.sh:774`). The only bounded exit is a human `kill`. |
| 5 | **The status surface shows corpses and hides the living.** The 09:07Z and 09:37Z pulses both said "линий нет" with two lanes provably running; `leadv2-lane-liveness.sh --json` returned exactly one lane, a finalized corpse. | `STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` | Three surfaces, three derivations: `S/leadv2-broad-status.sh:158-176` counts `active.yaml` rows itself and prints "(живых линий нет)" (`:1023-1025`) when its collector returns none; `S/leadv2-status-surface.sh:1000-1017` classifies live/done/dead from the *registration* ledger dir (`:57`, `~/.claude/cache/dispatch-ledger`) — a different ledger from the terminal ledger; `S/leadv2-lanes-snapshot.sh:333` consumes liveness `--all` but also mutates `active.yaml` itself (`:997-1027`, `:1231-1281`). None of them asks one owner. |

Cost so far: **four separate rescues of committed-less work by the lead's own hands** — 25 files
(freepool), 52 lines (`b794a736`), 23 files (`adf89c9b`), and one lane resumed after its worker died
holding a finished commit it never proved. The lead should never be the mechanism that saves a
lane's work. Today it is the only one. Root mechanism: the commit epilogue
`leadv2_worker_commit_epilogue` runs only on the inline waiter path of
`S/claude-subsession.sh:1284-1288`; the detached `died-detached` fallback (`:1271-1277`) stamps
`.outcome`/`.finalized` **without** it. Kill the wrapper after spawn and the work is never committed
by anything but a human.

## 2. Census — every writer and reader of lane state (first cut, architect-verified)

Legend for "answers": Q1 alive? · Q2 terminal, and true? · Q3 where is the work? · Q4 may re-dispatch?
"Own verdict" = computes an answer from raw inputs instead of asking another mechanism.

### 2.1 Physical stores

| # | store | written by | read by |
|---|---|---|---|
| S1 | `docs/leadv2/active.yaml` (path via `S/leadv2-state-path.sh`, may live outside the worktree) | registry API (W1), lane-state API (W2), direct file mutation in lanes-snapshot (W3), fallback direct write in gate1-prompt (`:132`) | 60 non-test scripts reference it (grep `active\.yaml`), incl. every surface in §2.3 |
| S2 | `docs/leadv2/tombstones.yaml` | `S/leadv2-lanes-snapshot.sh:933,1228-1236` | `S/leadv2-lane-liveness.sh:42-45` |
| S3 | run dir `~/.claude/cache/claude-runs/<RUN_ID>/` — `pid`, `.outcome`, `.finalized`, `finalizer_pid`; pointer `docs/handoff/<tid>/.claude-session-runner.run-id` | `S/claude-subsession.sh:1215` (dir), `:1247` (pid), `:1273-1275` and `:1301-1305` (.outcome/.finalized, two racing writers), `adf89c9b` (finalizer_pid) | liveness sentinel ladder `:504-594`; product-close sonnet path (`adf89c9b`: `_pc_sonnet_run_dir_for_handle` scans the dir for a matching `pid` file) |
| S4 | terminal ledger `dispatch-terminal-ledger/<repo>.jsonl` (`S/leadv2-dispatch-ledger.sh:151-163`; write-once `landed`/`dead`) | `dispatch_ledger_write_terminal` `:291`; `dispatch_ledger_sweep_write_dead` `:555` | `_dispatch_terminal_ledger_state` `S/leadv2-dispatch-code.sh:3211` → re-dispatch gate `:3272-3282`; `dispatch_terminal_exists` `:189` |
| S5 | registration ledger dir `~/.claude/cache/dispatch-ledger/` (`S/leadv2-dispatch-code.sh:681`, `_dispatch_register_arm` `:867`; sig8 → arm/handle/state) | dispatch-code | `S/leadv2-status-surface.sh:57,1134-1169` — **a second "ledger" with the same name; the status surface reads this one, not S4** |
| S6 | journal (`emit decision` lines: `dispatch_terminal`, `dispatch_refused`, `review_gate … terminal=`, `lane_placement_refused`, `dispatch_reclaimed`) | dispatch-code, product-close (`_dl_note` `:168`), ledger | `S/leadv2-lane-pulse-watch.sh` (tails for `dispatch_terminal|dispatch_refused`), the lead's Monitors |
| S7 | worker stream file (`STREAM_OUT`; recorded as `log_path` on the row) | the worker | liveness `:753-757` (source `active.yaml:log_path`), `:905` (mtime → `is_fresh`) |
| S8 | lane-outcome token in run dir (`completed|died-with-work|died-clean|parked`) | `S/leadv2-lane-outcome.sh` (callers: glm-coder, kimi-coder, freepool-coder, `S/lib/leadv2-worker-epilogue.sh`) | product-close, status-surface |
| S9 | close-owner pidfile | `close_owner_pidfile` `S/leadv2-dispatch-product-close.sh:218,236` | `_product_close_pid_alive` `S/leadv2-dispatch-ledger.sh:678` (grace window for the sweep) |

### 2.2 Writers of lane state

| # | writer | what it writes | answers | notes / where I am unsure |
|---|---|---|---|---|
| W1 | `S/leadv2-active-registry.sh` (1388 lines, 25 non-test callers). Ops: register/unregister/update_phase/update_pulse/heartbeat/mark_finished/set_writes/set_attempt/set_worker_pid (`:5-18`) | row fields at register `:440-460`: `session_id task_id worktree branch started_at phase class pulse_log pid pid_birth pid_role parent_session_id daemon_mode last_pulse_at stale note`; later ops add `worker_pid worker_pid_birth worker_pid_role writes attempt_id log_path dead_at heartbeat/finished/outcome rendered_at` | Q1 (identity), Q2 (`mark_finished`), Q4 (admission `check_limits`, writeset `:303-309`) | Python flock + atomic rename. **This is the writer to keep.** |
| W2 | `S/lib/leadv2-lane-state.sh` (5 callers). Ops register/transition/deregister/reconcile/count/alive (`:78-158`), `lane_adopt_pid` `:158-161` | SAME file S1, DIFFERENT schema on the same row: `pid pid_start_time lead_session_id phase dead_at updated_at recovered lane_events` (`:95-100`, `:138-139`) | Q1 (`alive()` `:57-65` = kill -0 + `pid_start_time` birth match), Q2 (`deregister`), Q4 (`reconcile` marks dead / "recovers live orphans" `:112-139`) | Header claims "Shared authoritative lane-attempt state". Call sites: dispatch-code `:3516,5573-5574,5704-5705,6737,7073`; product-close `:3342`; session-runner `:198-200`; codex-session-runner `:102-104`. **Unsure (U1):** whether `:5705` really lands the watcher pid in `pid` at runtime — call site verified, live row not observed. |
| W3 | `S/leadv2-lanes-snapshot.sh` (1745 lines, 5 callers) | prunes tombstoned rows (`:997-1027`, `os.replace`) and abandons lanes (`:1231-1281`) under its own flock; writes S2 | Q2, Q4 | A *view* that mutates the registry directly, bypassing W1. |
| W4 | `S/claude-subsession.sh` epilogue | S3: `pid` `:1247`; `.outcome`+`.finalized` from the inline waiter `:1301-1305` (after `leadv2_worker_commit_epilogue` `:1284-1288`) **and** from a detached kill-0 poller `:1271-1277` (`died-detached`, no epilogue); cost marker waiter `:1255-1258` | Q2 (producer-side proof), Q3 (commit epilogue — inline path only) | Three concurrent finalizers; only one commits work. |
| W5 | `S/leadv2-dispatch-ledger.sh` | S4 rows via `dispatch_ledger_write_terminal` `:291` (downgrades `landed`→`pass_unlanded`/`refused` on dirty lane `:296-312`); `cmd_sweep` `:732` consumes liveness `--all --json` `:744-747`, overlays its own rules (`pid_alive` override `:787-790`, `age_s` indeterminate `:797-800`), writes `dead` `:819`; `cmd_reconcile` `:1004` derives landed/dead/no_work itself (`_dl_derive_lane_state` `:906`) and writes `:1134-1149` | Q2, Q3 (dirty → `pass_unlanded`, `dead_with_unlanded_work`), Q4 (sweep frees a lane) | Sweep is the only existing "worker gone → dispatchable" path. Its overlay is a second verdict on top of liveness. |
| W6 | `S/leadv2-dispatch-product-close.sh` | `_dl_note` `:168` → terminal+cause → S4 + S6 `review_gate` line; `no_work/empty_diff` `:2408`, `report_missing` `:2238`, `arm_produced_nothing` `:2558`; sonnet-only reap of worker+finalizer (`adf89c9b`); `lane_deregister` on `close_landed` `:3342` | Q2, Q3, Q4 | `lv2_lane_dirty() { return 0; }` at `:91` — **unsure (U8)** whether that is a fail-closed fallback stub or ever the live definition. |
| W7 | `S/leadv2-dispatch-code.sh` | W1 register `:7044` (+ second register `:7216-7218`), `set_worker_pid` `:5567-5574` (worker) and `:5695-5702` (watcher, role `watcher`); W2 `lane_register` `:7073`, `lane_adopt_pid` `:5574,5705`, `lane_reconcile` `:6737`, `lane_deregister` `:3516`; S5 `_dispatch_register_arm` `:867`; S6 lines | Q1, Q2, Q4 | Registers BEFORE spawn (`:7044`), stamps worker pid AFTER spawn (`:5571`). |
| W8 | `S/leadv2-lane-heartbeat.sh` (PULSE-01) `beat`/`finish` `:76,:82` → W1 heartbeat/mark_finished | heartbeat, finished/outcome fields | Q1, Q2 | Callers: beat-owner, single-lead-beat-loop, pulse-beat. |
| W9 | unregister sites outside the dispatch path: `S/leadv2-backlog-pump.sh:681`, `S/leadv2-stale-sweeper.sh:265`, `S/leadv2-phase8-close.sh:590`, `S/leadv2-fanout.sh:1716,1758,1944-1966`, `S/leadv2-fanout-lane-launcher.sh:325-498` (7 sites), `S/leadv2-helpers.sh:650`, `S/leadv2-fork-session.sh:206` (register), `S/leadv2-provider-canary.sh:273-274` (register) | row removal | Q4 | **Unsure (U2/U7):** which of these are on the single-lead live path vs supervisor-era (`fanout*`, `stale-sweeper` via `outcome-watch`). |

### 2.3 Readers that compute their OWN verdict (each one is a mechanism that can disagree)

| # | reader | inputs | own verdict on | notes |
|---|---|---|---|---|
| R1 | `S/leadv2-lane-liveness.sh` (1065 lines; 20 non-test callers: dispatch-code `:3029,5004`, ledger sweep, product-close `:843`, lanes-snapshot `:333`, status-surface, backlog-pump, worktree-cleanup, lane-status-line-tail, lane-detail, stale-sweeper, codex-planner, one-copy-convert, writes-overlap, status-cache, claude-subsession, codex-task, lane-watch-v2, lanes.sh) | S7 mtime + `LEADV2_LANE_SILENT_MAX_S`(900)/`ABANDON_MAX_S`(3600)/`STARTING_MAX_S`(300)/`FINISHED_WINDOW_S`(1800) `:84-111`; row `worker_pid`+birth identity `:651-674` (gated on `worker_pid_role`≠watcher `:669`, `pid_source`∉{lead_durable,watcher} `:944`); `.finalized` sentinel ladder `:504-594`; provider status `:905-925`; tombstones; child-suffix fold `:632`; git commit age `:705`; lane-local `dispatch.json` `:784` | **Q1** — verdicts `alive` / `starting:N` / `silent:N` / `finished:Ns` / `dead:{sentinel_finalized,no_handoff_dir,no_log_artifact,log_stat_failed,provider_*,wedged_STAT=*,silent_Ns_abandoned,silent_Ns_no_process}` / `child` (`:594-1007`); codex jobs mapped `running/done` `:1014` | The most complete engine and already on the front of every dispatch. Not the owner today: stream-first, no progress notion, no Q2/Q3/Q4. |
| R2 | `S/leadv2-active-registry.sh` `_pid_alive` `:266-269` | row `pid` (lead_durable!) | Q4 (admission; writeset pending `:303-309`) | Own kill -0, on the wrong pid. |
| R3 | `S/lib/leadv2-lane-state.sh` `alive`/`reconcile` `:57-65,112-139` | row `pid` + `pid_start_time` | Q1, Q4 | Second identity implementation. |
| R4 | `S/leadv2-lane-heartbeat.sh status` `:114-150` | heartbeat age vs `STALE_MIN` | Q1 | Third liveness engine; header `:2-14` calls itself "ONE reader that computes a verdict the SAME way for every arm". Rollback flag `LEADV2_LANE_LIVENESS_LEGACY`. |
| R5 | ledger `cmd_sweep` overlay `:787-800` + `_product_close_pid_alive` `:678` | R1 JSON + pid + S9 | Q1 (override), Q4 | Fourth engine (on top of R1). |
| R6 | ledger `cmd_reconcile` / `_dl_derive_lane_state` `:906-994` | lane artifacts | Q2, Q3 | Fifth: derives terminal from files. |
| R7 | product-close sonnet path (`adf89c9b`): run-dir `pid`/`finalizer_pid`/`.finalized` | S3 | Q1, Q2 | Sixth, one arm only. |
| R8 | `S/leadv2-status-surface.sh` (READ-ONLY `:15`) `is_terminal(status, ledger_state)` `:1000-1017` | S1 + S5 + S8 | Q1, Q2 | Seventh; reads the *registration* ledger, not S4. |
| R9 | `S/leadv2-broad-status.sh:158-176` (+ `S/leadv2-status-collector.sh`, 425 lines, not read — **U4**) | S1 rows directly | Q1 (count) | Eighth. Produces the founder pulse via `S/leadv2-pulse-beat.sh`. |
| R10 | `S/leadv2-dispatch-code.sh` `_dispatch_evidence_exists` `:3283` (`unattributed_empty`), `_arm_no_work_signal` `:5778`, codex verdict map `:3027-3046` | S4/S5/arm output | Q3, Q4 | **Unsure (U3):** `_dispatch_evidence_exists` semantics not read. |
| R11 | `S/lib/leadv2-lane-guard.sh` `lv2_lane_dirty`, containment | git porcelain | Q3 | Used by W5 `:296-312`, W6 `:1568,2354`. This is the right Q3 primitive; keep. |
| R12 | statusline `S/leadv2-lane-status-line.sh` / `-tail.sh` (`--no-codex` R1) | S1 + R1 | Q1 | View. |
| R13 | `S/leadv2-lane-pulse-watch.sh` (detached per lane, started at `worker_spawned`) | S6 | Q2 | Its own pid is stamped on the row as `worker_pid_role=watcher` (`:5695-5702`). |
| R14 | worktree safety: `S/leadv2-worktree-cleanup.sh`, `S/lib/leadv2-worktree-protected.sh`, `S/leadv2-lane-worktree.sh` | S1 + R1 | Q1 (prune safety) | The path that killed two live lanes once. |
| — | dead: `S/leadv2-lanes.sh` (341 lines, **0 callers**), `S/leadv2-lane-watch-v2.sh` (**0 callers**) | | | Audit-1 shape: standalone scripts nobody calls. Delete. |

**Count.** Q1 has eight independent verdict engines (R1-R9 minus R6). Q2 has seven places a
terminal is recorded (S1 `mark_finished`/`dead_at`, S1 lane-state `deregister`+`lane_events`, S3
`.outcome`/`.finalized`, S4, S5 state, S6 lines, S8 token). Q3 has five (R11, W4 epilogue, W5
dirty downgrades, W6 `empty_diff`, R10) plus the lead's hands. Q4 has eight decision points (W7
`:3272`, `:1082`; R2; W5 sweep; W3 prune/abandon; W9 unregister sites; R3 reconcile;
worktree-protected). If the lane's own census finds more, that is a finding — record it, do not
trim the table to look tidy.

## 3. The owner — shape, argued against the census

**Do not write a new component.** Audit 1's finding is that a new standalone script nobody calls is
exactly how work in this plugin dies. Three files already sit on the dispatch path and already hold
the best implementation of each question; the owner is those three, with a contract that every
other mechanism must obey — and everything that violates the contract is deleted.

| role | the file (exists, on the dispatch path today) | becomes |
|---|---|---|
| **the row** — single writer | `S/leadv2-active-registry.sh` (W1) | the ONLY code that mutates `active.yaml`/`tombstones.yaml`. Row gains `run_dir` (stamped at spawn, so nobody scans `claude-runs/` for a pid file again) and `progress_fp`/`progress_at` (see Q4). `pid`/`pid_role=lead_durable` stays as "who dispatched" — never liveness evidence. |
| **the verdict** — single reader | `S/leadv2-lane-liveness.sh` (R1) | the ONLY code that answers Q1, and it answers **from the worker's identity first**: a registered row with `worker_pid` → `pid_state(worker_pid, birth)` decides alive/dead; stream age becomes an *annotation* (`alive+silent:N`), never a verdict. No row → `unregistered` (not alive, not refusable). Worker alive but no progress past `ABANDON_MAX` → `stuck` (a new verdict, the input to the bounded reap). Output gains `terminal`, `work`, `dispatchable` fields so callers never derive Q2-Q4 themselves. |
| **the terminal funnel** — single recorder | `dispatch_ledger_write_terminal` in `S/leadv2-dispatch-ledger.sh:291` (W5) | the ONLY path that records a terminal, with a **producer-gone precondition** for every arm: worker pid dead by identity, `finalizer_pid` dead or absent, `.finalized` present or settle-then-reap (TERM→KILL, `LEADV2_TERMINAL_SETTLE_S`, default 15). It then calls `leadv2_active_mark_finished` and emits the S6 line itself — S1's finished fields and the journal become *outputs of the funnel*, not parallel records. |

Why not a single new file: it would be the fourth standalone thing with zero callers on day one,
and the 20+25+9 existing callers of these three would keep their own derivations until someone
migrated them — i.e. the mechanism count would go **up**. Why not "the registry alone": Q1 needs
process probing and provider shell-outs that must never run inside the registry's flock (Codex
status can block 20s, `:60-70`), so verdict and row stay two files with one contract.

**Contract (write it as `docs/leadv2/lane-state-owner.md` in D1, then enforce it in code):**

1. Only `leadv2-active-registry.sh` writes S1/S2. A test greps the tree for `active.yaml` writers.
2. Only `leadv2-lane-liveness.sh --json` answers Q1. Every reader consumes its JSON (`--no-codex`
   on hot paths). `pid_state()` (kill -0 + birth identity) exists in **one** place; the registry's
   admission check imports or re-invokes it — never a third copy (lane's call which file owns it).
3. Only `dispatch_ledger_write_terminal` records Q2. It refuses (rc≠0, journal line) while the
   producer can still produce; it reaps within a bound; it writes S1 finished fields and S6 itself.
4. Q3 is one function in `S/lib/leadv2-lane-guard.sh`: `lv2_lane_work <lane_root>` →
   `committed:<sha>` | `dirty:<n>` | `none`. The funnel stamps `commit=` from it. The commit
   epilogue (`leadv2_worker_commit_epilogue`) runs on **every** exit path of the wrapper, including
   died-detached.
5. Q4 = `dispatchable` in the liveness JSON: true iff no row, or row terminal, or verdict
   `dead:*`/`stuck` after the sweep reaped it. The sweep (`cmd_sweep`) is the bounded path from
   "worker gone/stuck" to dispatchable: it loops over verdicts and calls the funnel — **no judgment
   of its own** (`:787-800` deleted).

**What gets deleted (named; the count must go down, not sideways):**

| delete | replaced by |
|---|---|
| `S/lib/leadv2-lane-state.sh` (entire file, W2/R3) and its 8 call sites | W1 ops (`set_worker_pid` already exists; `unregister`/`mark_finished` for deregister; `lane_reconcile` → ledger sweep) |
| `S/leadv2-lane-heartbeat.sh status` verb (R4) | R1 JSON; `beat`/`finish` stay as thin W1 wrappers |
| registry `_pid_alive` on `pid` for admission (R2 `:266-309`) | the one `pid_state()` on `worker_pid` |
| ledger sweep overlay `:787-800` (R5) and `cmd_reconcile`'s own derivation `:906-994` (R6) | R1 verdict + funnel; reconcile becomes "replay unrecorded terminals through the funnel" |
| product-close sonnet-only reap + `_pc_sonnet_run_dir_for_handle` scan (`adf89c9b`, R7) | funnel precondition (all arms) + row `run_dir` |
| status-surface `is_terminal`/S5 classification (R8), broad-status direct row count (R9 `:158-176`), lanes-snapshot's own `active.yaml`/`tombstones.yaml` mutations (W3) | R1 JSON + S4; snapshot prune/abandon become W1 ops |
| the detached `died-detached` finalizer (`:1271-1277`) and the cost-marker waiter (`:1255-1258`) as separate paths | one finalizer function called from both the inline waiter and the survivor path, always running the epilogue before `.finalized` |
| `S/leadv2-lanes.sh`, `S/leadv2-lane-watch-v2.sh` (0 callers), `S/leadv2-stale-sweeper.sh` (if U7 confirms supervisor-era) | nothing |
| supervisor-era unregister sites in `fanout*.sh` (W9) if U2 confirms dead path | nothing; otherwise routed through W1 unchanged |

After: Q1 engines 8 → 1. Q2 records 7 → 1 funnel + 2 derived outputs (S1 finished fields, S6 line)
+ 1 producer-side input (S3 `.finalized`). Q3 5 → 1 function + 1 epilogue. Q4 decision points 8 →
1 field. Writers of S1: 3 APIs/paths → 1.

## 4. Deliverables — ordered, each committed in the lane before the next starts

This task is long enough that a single dead worker must not cost more than one deliverable.
Each D ends with: suites green on macOS **and** in the Linux container (exit codes pasted), the
negative control run and reverted (mutation named, red shown, green shown), the suite registered
in `tests/run-all.sh` `EXTRA_SUITE_MAP` (`:82-84`, `add_suite` `:86`) and proven selected by
`tests/run-all.sh --scope changed`, then `git commit` in the lane. Linux = the same
`ubuntu-latest` job as `.github/workflows/test-suites.yml:25` (`tests/ci-gate.sh` reconciles
against `tests/known-red-suites.txt` — which is off limits).

| D | deliverable | proof (acceptance) | negative control (name it in the suite header) |
|---|---|---|---|
| **D0** (≤2h) | **Baseline + census correction.** Run the existing suites for these mechanisms (`test-lane-liveness-{authoritative,lies,sentinel}.sh`, `test-lane-registry-{self-deadlock,outlives-dispatcher}.sh`, `test-dispatch-terminal-deregisters-lane.sh`, `test-dispatch-ledger-*.sh`, `test-worker-outlives-terminal-state.sh`, `test-lane-placement-pin.sh`, `test-status-surface*.sh`, `test-broad-status-*.sh`, `test-lanes-snapshot.sh`, `test-leadv2-lane-heartbeat.sh`) on both OSes; resolve U1–U8 against a live row / the code; write `census.md` with corrections to §2. | exit codes for both OSes; `census.md` committed; every U resolved with a file:line or a live row. | none — measurement only |
| **D1** | **Single writer, wired and proven live.** Delete `S/lib/leadv2-lane-state.sh`; replace its 8 call sites with W1 ops; stamp `run_dir` on the row at spawn (W7 `:5567`); remove the lead-pid registrations that are not lanes (`helpers.sh:628`, `gate1-prompt.sh:64,132`) or mark them `pid_role=lead_durable` with no `worker_pid`. Write `docs/leadv2/lane-state-owner.md` (the contract in §3). | A **live dispatch** of a trivial task; paste the `active.yaml` row: `pid_role=lead_durable`, `worker_pid_role=worker`, `run_dir` set, no `pid_start_time`/`lane_events` keys. Suite `test-lane-owner-single-writer.sh`: greps the tree for any `active.yaml` writer outside W1; asserts the watcher pid never lands in `pid`/`worker_pid` with role `worker`. | re-add one `lane_adopt_pid "$WATCHER_PID"` call (symptom 1 shape) → red; revert → green |
| **D2** | **One verdict, from the worker's identity.** R1 under `LEADV2_LANE_OWNER=1` (default on; `0` = exact prior ladder, one-flip rollback): identity-first; stream age annotates; `unregistered` for no row; `stuck` = alive + `progress_fp` unchanged past `ABANDON_MAX` (fingerprint = worktree `git status --porcelain` + HEAD, stamped by the sweep — bytes in the stream are not progress); JSON gains `terminal`/`work`/`dispatchable`. Delete R2's `pid` probe, R4 `status`, R5 overlay. Admission and `lane_placement_refused` (`:1082`) consume `dispatchable`. | `test-lane-owner-verdict.sh` with fake workers (`sleep` processes + pid/birth files, temp state dir via `LEADV2_PROJECT_ROOT`): registered+alive → `alive` even with a 2h-old stream; registered+dead pid → `dead:*` even with a fresh stream; no row → `unregistered` and **no** `lane_is_live` refusal (symptom 2); alive + stream written every second + fingerprint unchanged past a 5s test `ABANDON_MAX` → `stuck` → sweep reaps → `dispatchable=true` with no human step (symptom 4), elapsed bounded. | (a) restore `is_fresh` precedence over pid identity → symptom-2 case red; (b) delete the `stuck` branch → symptom-4 case red; revert → green |
| **D3** | **Terminal funnel with a producer-gone precondition, all arms.** Extend `dispatch_ledger_write_terminal` per §3 rule 3; make it call `mark_finished` and emit S6; route `_dl_note`, sweep, reconcile through it (they already call it — remove their side records); delete the `adf89c9b` sonnet-only reap once the funnel covers it (keep `test-worker-outlives-terminal-state.sh`, re-point it at the funnel). Subsumes `WORKER-OUTLIVES-ITS-TERMINAL-STATE-01` / `SD-WORKER-OUTLIVES-VERIFY-01`. | For sonnet, glm, codex shapes (fake workers): after any terminal row is written, `kill -0 worker_pid` fails within `SETTLE+reap` seconds; a write attempted while the worker is alive and unfinalized returns rc≠0 and journals `terminal_refused_producer_alive`; S1 `finished`/`outcome` and the S6 line exist only after the S4 row. | comment out the precondition inside the funnel body (not at file top level — the 2026-08-25 lesson) → red; revert → green |
| **D4** | **Work survives every path.** `lv2_lane_work` in lane-guard; one finalizer function in `claude-subsession.sh` used by the inline waiter and the survivor path, epilogue-before-sentinel on both; funnel stamps `commit=`; `_dispatch_evidence_exists`/`unattributed_empty` (`:3283`) consume `work`. | Reproduce the four rescue shapes — worker killed mid-write; wrapper killed right after spawn; worker exits 0 with uncommitted files; worker dies holding a finished commit — and show the commit lands and the S4 row carries its sha, **with the lead touching nothing**. | remove the epilogue call from the survivor path → "wrapper killed after spawn" case red; revert → green |
| **D5** | **Readers become views, one at a time, each with its own proof:** status-surface (R8), broad-status + status-collector (R9), lanes-snapshot (W3 → W1 ops), lane-status-line(-tail) (R12), backlog-pump, worktree-cleanup/-protected (R14), lane-detail; delete `lanes.sh`, `lane-watch-v2.sh`, `stale-sweeper.sh` (per U7), supervisor-era W9 sites (per U2). Closes `STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01`. | Symptom-5 suite: seed one finalized corpse + one registered live fake worker → `broad-status` renders exactly one row (never "(живых линий нет)"), `status-surface` classifies live/dead identically to R1, `lanes-snapshot --json` matches R1 lane-for-lane. Grep proves no reader parses `active.yaml` for a verdict any more. | make broad-status count rows directly again → red; revert → green |
| **D6** | **Harness + kill rate.** All suites in `EXTRA_SUITE_MAP` and `--scope changed` output pasted; ubuntu job green; `mutations.md` in this handoff dir listing every mutation from D1–D5 with its red/green run output. leadv2 has **no** `tests/mutations/catalog.yaml` today (verified: absent) — check `tests/test-run-all-carrier-map.sh` for the repo's convention (**U6**) before creating one; a catalog nobody runs is the audit-1 shape. Kill rate may not go down: no mutation from this table is dropped. | `tests/run-all.sh --scope changed` selecting each new suite; `tests/ci-gate.sh` exit 0 on ubuntu; `mutations.md` complete. | — |

Deliverables 1–4 each close one of the four filed defects as a *symptom*; a point fix already
landed for any of them does not remove it from the census or from the negative controls.

## 5. Risks and mitigations

| risk | mitigation |
|---|---|
| **Unregistered live workers.** Making "no row → not alive → dispatchable" authoritative is only safe if every live spawner registers before spawning. dispatch-code does (`:7044` before `:5571`); `fork-session.sh:206`, `session-runner.sh:198`, `codex-session-runner.sh:102`, `gate1-prompt.sh:64` may not, or may register the lead. | D1 includes a spawner census (every `claude-subsession.sh`/`*-session-runner.sh` invocation) with proof each registers a worker row; until then `unregistered` must NOT be prune-safe for worktrees (R14 keeps its stream check as a second gate for one deliverable). |
| Lock ordering: the funnel (ledger lock) now calls W1 (registry flock). | Rule: ledger → registry only; W1 never calls the ledger or R1. A test asserts no `dispatch-ledger` reference inside `leadv2-active-registry.sh`. |
| R1 `--all` sits at the front of every dispatch; Codex status can block 20s (`:60-70`). | Hot paths use `--no-codex`; the codex shell-out only when the row has a codex handle. Measure `--all` wall time before/after in D2. |
| Tests that touch the LIVE registry kill live lanes (it happened with worktree pruning). | Every suite sets `LEADV2_PROJECT_ROOT` to a temp dir and asserts the resolved `active.yaml` path is under it before writing. |
| macOS bash 3.2 vs Linux bash 5; no `timeout(1)` on macOS; `mktemp` forms differ (`CI-SUITES-ARE-MACOS-ONLY-01`). | Run both from D0 on; never `declare -A`, never `mktemp --suffix`. |
| Pid reuse. | Birth identity (already in R1 `:133`, `:674`) — one implementation, never bare `kill -0`. |
| Dropping lane-state.sh's schema keys (`pid_start_time`, `lane_events`, `lead_session_id`, `recovered`). | Grep all readers of those keys in D0; W1 must ignore-and-preserve unknown keys on rewrite. |
| Two things named "ledger" (S4 vs S5). | Name them `terminal ledger` and `registration ledger` in code comments and in `lane-state-owner.md`; status-surface reads S4 after D5. |
| A stuck worker reaped by the sweep loses in-flight work. | The funnel's reap runs the commit epilogue on the lane worktree before KILL; `dead_with_unlanded_work` stays write-once and pins the worktree (`ledger.sh` header). |

## 6. Sequencing

The four defects already filed — `LANE-REGISTRY-STAMPS-THE-LEAD-PID-01`,
`WORKER-OUTLIVES-ITS-TERMINAL-STATE-01`, `LANE-REGISTRY-SELF-DEADLOCK-01`,
`STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` — are this task's symptoms, not separate work. Any of
them already landed when this starts is a symptom that must still appear in the census and in the
negative controls; a point fix does not remove the need for the owner. Note that
`WORKER-OUTLIVES-ITS-TERMINAL-STATE-01` has committed but **ungated** work (`adf89c9b`) pending
`SD-WORKER-OUTLIVES-VERIFY-01` — treat it as unproven until that row closes; D3 replaces it.
`LANE-PLACEMENT-PIN-RED-01` (`b794a736`) is the same family: its test stays.

Order is D0→D6 strictly; D5's per-reader migrations may be split into separate commits and may
be picked up by a fresh worker after a death without re-doing D1–D4 — that is the point of
committing per deliverable.

## 7. Off limits

`main`; `tests/known-red-suites.txt`; weakening or deleting any assertion; raising `silent_max`
(or `ABANDON_MAX`) to paper over symptom 4; pruning worktrees while any lane runs (that has already
killed two live lanes); committing inside any MythicalGames repo; **adding a new standalone script
as "the owner"**; a third implementation of pid identity; editing shared trees under
`~/.claude/` or any repo's `.claude/leadv2*` symlinks; `--permission-mode` or hook changes.

## 8. Where the architect is unsure — re-derive, do not trust

- **U1** `lane_adopt_pid` at `dispatch-code:5705` overwriting `pid` with the watcher pid — call site verified, runtime row not observed.
- **U2** Whether `helpers.sh:628/650`, `gate1-prompt.sh:64/132`, `fanout*.sh` registrations run on the single-lead live path.
- **U3** `_dispatch_evidence_exists` (`dispatch-code:3283`) — semantics not read.
- **U4** `leadv2-status-collector.sh` (425 lines) — the exact producer of the 09:07Z/09:37Z "линий нет" pulse was not traced past `broad-status.sh:1023`.
- **U5** `leadv2-lane-outcome.sh` token ↔ ledger terminal mapping — header only.
- **U6** Whether leadv2 has a kill-rate catalog convention (`tests/test-run-all-carrier-map.sh` mentions it; no `tests/mutations/catalog.yaml` exists).
- **U7** `stale-sweeper.sh` callers (`outcome-watch.sh`, `fanout.sh`) — live or supervisor-era.
- **U8** `lv2_lane_dirty() { return 0; }` at `product-close.sh:91` — fallback stub or live definition.
- Whether the row-authoritative rule ("no row → not alive") is safe for every spawner (§5 row 1) — the single biggest design risk in this brief.
