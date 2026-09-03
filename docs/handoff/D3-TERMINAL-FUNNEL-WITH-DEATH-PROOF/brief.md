# D3 — terminal funnel with a death check: implementation brief

Consumes `brief-pre-evidence.md` (this dir) and `D2-SINGLE-LIVENESS-VERDICT/brief-pre-evidence.md`.
Nothing below re-derives their evidence; every line marked **verified** was checked against the tree
at `c47a2273`. Repowise does not index this repo (`Unknown repo 'leadv2'`), so discovery here is grep.

## 0. What the tree already has — verified, and it changes the shape of the fix

| Fact | Where | Why it matters |
|---|---|---|
| `dead_with_unlanded_work` is already a legal terminal | `leadv2-dispatch-ledger.sh:318` | D3 stamps an existing enum. No schema change. |
| It is already a **TRUE terminal** → `lane_deregister` fires | `leadv2-dispatch-ledger.sh:412,436` | The cap slot is freed automatically by writing it. |
| `dispatch_ledger_write_terminal` already resolves the lane root and calls `lv2_lane_dirty` | `leadv2-dispatch-ledger.sh:299-307` | A dirty check exists — it only **downgrades** `landed`→`pass_unlanded`. It never commits. |
| `cmd_reconcile` already anti-joins reservation vs terminal and derives state | `leadv2-dispatch-ledger.sh:1004` | The enumeration D3 needs is built. |
| `_dl_derive_lane_state` ORs a dirty tree into **`landed`** | `leadv2-dispatch-ledger.sh:~960` | **This is the incident.** A SIGKILLed lane with 573 uncommitted lines is stamped `landed`. That is exactly "reads as finished, was killed mid-task". |
| The dirty probe is scoped to `pathspec` from `lane_writes`; empty CSV ⇒ `dirty` never set | same fn | Same disease as `pc_stop_gate_autocommit`'s `[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] \|\| return 0` (`leadv2-dispatch-product-close.sh:1910`) — **second location, same self-disable.** |
| `bash "${LEDGER_BIN}" sweep` is already invoked from dispatch | `leadv2-dispatch-code.sh:6734` | **The seam into the held file already exists.** D3 needs zero edits to `leadv2-dispatch-code.sh`. |
| `leadv2-worker-epilogue.sh` contains **no `trap`** | grep, 0 hits | Confirms the pre-evidence root cause. |
| `leadv2-lane-liveness.sh` CLI: `--project-root R --lane <id>` → `alive\|starting:*\|silent:*\|dead:*` | `:23-31`, consumed by `_dl_derive_lane_state` | This is D2's seam. D3 calls this CLI and nothing else. |

**Consequence:** D3 is not a new subsystem. It is one new verb, one reordered decision, and one commit
action, all inside `leadv2-dispatch-ledger.sh`.

## 1. Where the funnel runs — decision and trade-offs

New verb: **`leadv2-dispatch-ledger.sh reap [--lane <id>] [--all] [--dry-run]`**. It never runs in the
lane's process tree; it is always invoked by a process that outlived the lane.

| Actor | Trigger | Latency | Dies when | Verdict |
|---|---|---|---|---|
| Ledger sweep at the front of every dispatch | already wired, `dispatch-code.sh:6734` | next dispatch | never (a new dispatch is a new process) | **PRIMARY** — no held-file edit |
| `leadv2-stale-sweeper.sh` at `/leadv2` startup | SessionStart | next lead session | never | **SECONDARY** — covers "lead died, lanes orphaned" |
| `leadv2-single-lead-beat-loop.sh`, `LEADV2_SINGLE_LEAD_BEAT_LOOP_S` (default 300) | periodic | ≤5 min | it is a child of the lead | **TERTIARY** — the only one that catches the incident *while it is happening* |
| launchd / cron | OS | ≤1 min | never | **REJECTED as primary**: no launchd in the linux container, per-repo install burden, and a plugin shipped to 3 repos cannot own a machine-level agent. Revisit only if the three above measure insufficient. |

**When the actor is itself dead:** the rescue is *deferred, never lost*. The funnel derives 100% of its
input from disk (worktree, `arm-registered` PIDs, the two ledgers), holds no memory, and is idempotent
— a second run finds the row the first wrote. The one real deadline is the SessionStart worktree
sweeper, which deletes worktrees with no unmerged commits (pre-evidence §incident). **Ordering
constraint, blocking:** in `hooks.json` the `reap` call must run **before** any worktree GC on
SessionStart. If it runs after, D3 rescues nothing on the exact path it exists for.

## 2. The transition — ONE ordered sequence, one lock, no interleaving

Per lane, inside a single `flock` on the terminal-ledger lock (`dispatch_terminal_ledger_lock_file()`),
in exactly this order. Steps 2–5 are one atomic unit; a terminal write reachable before step 3 is a
failed design.

1. **Enumerate.** Reservation rows with no TRUE terminal (the existing `cmd_reconcile` anti-join),
   plus `active.yaml` rows with no reservation (stale-registry case).
2. **Prove death from outside.** `bash leadv2-lane-liveness.sh --project-root R --lane <id>` →
   `alive|starting:*|silent:*` ⇒ **STOP, write nothing.** Only `dead:*` continues. D3 computes no
   liveness itself: no `ps`, no `kill -0`, no mtime, not even a "small helper". Multi-PID semantics
   ("any recorded PID alive ⇒ alive") are D2's to own inside that binary.
3. **Inspect the worktree.** `leadv2-lane-worktree.sh path-of <founder_task_id>`, then
   `git -C <root> status --porcelain -uall` **unscoped**. Not `lane_writes`-scoped: an empty
   `lane_writes` must never silence the probe (§0, row 6). `lane_writes` is still used to *classify*
   dirt as owned vs foreign in the commit message — never to decide whether to look.
4. **Rescue iff there is a diff.** Non-empty status ⇒ `git add -A` + one commit (§3). Empty status ⇒
   no commit, ever; `--allow-empty` is banned.
5. **Write the terminal**, and only now:
   - rescue commit made → `dead_with_unlanded_work`, `commit=<sha>`;
   - clean tree, no artifacts → `no_work`;
   - clean tree, prior commits on the lane branch → the ordinary existing verdict (`landed`).
   **`no_work` may never be written on a path where step 3 returned non-empty.** Enforce it as a
   literal guard, not a comment: the `no_work` branch is reachable only under `[[ -z "${status_out}" ]]`.
6. **Free the cap slot.** No new code — `dead_with_unlanded_work` is a TRUE terminal and
   `leadv2-dispatch-ledger.sh:412` already drops the `active.yaml` row via `lane_deregister`.
7. **Emit one operator line** carrying the barrier (§4).

Also fix, in the same diff, the source of the misread: `_dl_derive_lane_state` must stop printing
`landed` when `dirty=1`. Dirty ⇒ route into this funnel, not into `landed`.

## 3. The rescue commit — unmistakable, by three independent signals

A reader who checks *none* of the machine signals still cannot misread the subject line.

| Field | Value |
|---|---|
| Subject | `RESCUE(unreviewed): <lane-id> killed <UTC-ts> — DO NOT MERGE` |
| Author | `leadv2-rescue <rescue@leadv2.invalid>` — via `git -c user.name= -c user.email=` on this commit only; never mutates lane git config, never the founder's identity |
| Committer | same |
| Trailers | `Leadv2-Rescue: true` · `Leadv2-Lane: <id>` · `Leadv2-Terminal: dead_with_unlanded_work` · `Leadv2-Reviewed: no` · `Leadv2-Dead-Pids: <csv>` · `Leadv2-Foreign-Dirty: <n>` |
| Marker file | `docs/handoff/<lane-id>/RESCUE-UNREVIEWED`, committed in the same commit. Survives `git log` reformatting and is visible in a plain `ls`. |
| Body | the `git status --porcelain` output, verbatim, capped at 200 lines |

Three orthogonal detectors: `%ae == rescue@leadv2.invalid`; `git log --grep='^Leadv2-Rescue: true'`;
the tracked marker path. A merge guard keys on the trailer (cheapest, unambiguous).
Out of scope for D3: *building* that merge guard.

**Credential rule:** the commit body is `git status` output only — never env, never a diff of a
`.env` / `*.enc` / `*secret*` path. Those paths are excluded from `git add -A` and counted in
`Leadv2-Foreign-Dirty` instead. No credential value is ever printed or logged.

## 4. The four barriers, made distinguishable

One `emit decision` line per reaped lane, plus the same fields on the terminal row's `cause`/`evidence`.
Today all four print as "the lane just didn't come up", and each is re-derived by hand.

| Barrier | Detection (all from disk) | `barrier=` value | `resumable=` |
|---|---|---|---|
| Lead-session lane cap | `active.yaml` row live, liveness `dead:*` | `cap_slot_held_by_dead_lane` | `yes` — the funnel's own deregister frees it |
| Dedup ledger | reservation for sig8 exists, TRUE terminal exists | `duplicate_task_signature` | `no` — needs `--task-id` **and** `--resume-lane` on a fresh sig |
| Stale registry row | `active.yaml` row, no reservation, liveness `dead:*` | `stale_registry_row` | `yes` |
| Dispatch `rc=0`, worker then died | reservation with `handle=PID=`, no terminal, every PID dead | `spawned_then_died` | `yes` |

Line shape:
`lane_reaped task=<sig8> lane=<id> barrier=<v> terminal=<t> rescued=<0|1> commit=<sha|none> resumable=<yes|no>`.
A lane is **never** called live because dispatch returned 0 — liveness is only the D2 verdict.

## 5. Where state is written — and why D1 will not have to undo it

D3 adds **zero new stores**. Every write lands in a store that already exists and already has a lock:

| Fact | Store | Writer |
|---|---|---|
| Terminal state | terminal-ledger JSONL, `dispatch_terminal_ledger_file()` | `dispatch_ledger_write_terminal` (existing, locked, write-once) |
| Cap release | `active.yaml` | `lane_deregister`, already triggered by TRUE terminals |
| Barrier / diagnosis | the same terminal row's `cause` + `evidence`, plus the journal line | same call |
| Rescue | git, in the lane worktree | the funnel |

D1 ("one writer for lane state") is free to collapse the 24 paths without touching D3: D3 is a *reader*
of liveness and a *caller* of the one existing terminal writer. It introduces no 25th path.

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Write-once poisons the resume.** `dead_with_unlanded_work` is a TRUE terminal; `leadv2-dispatch-ledger.sh:601` then `exit 2`s a re-dispatch of that sig. The funnel that frees the cap can hand the lane straight to `duplicate_task_signature` — barrier 1 traded for barrier 2. | Blocking. The `lane_reaped` line must carry `resumable=yes` **and** the exact resume invocation (`--task-id <id> --resume-lane`). Suite case C3 asserts that invocation is **accepted**. If it is refused, D3 has not delivered. |
| R2 | Worker not actually dead (D2 verdict racy) → funnel commits under a live worker. | Step 2 gates on `dead:*` only; `starting:*`/`silent:*` are non-terminal. Re-check liveness *after* acquiring the lock and before `git add`. |
| R3 | Two reap actors run concurrently (dispatch sweep + beat loop). | Single lock, and idempotence by structure: the second finds the terminal row and returns. Never two rescue commits — check `Leadv2-Rescue` on `HEAD` first. |
| R4 | PID reuse: the kernel hands a dead worker's PID to something else ⇒ false life ⇒ lane never reaped. | D2's problem, not D3's. `lib/leadv2_pid_birth.py` exists for exactly this. Name it in the D2 handoff; D3 must not paper over it with a timeout. |
| R5 | Foreign dirt (files outside the lane's write-set) swept into the rescue commit. | `git add -A` inside the lane worktree only; count and name foreign paths in the trailer; exclude credential-shaped paths outright. |
| R6 | `--allow-empty` creeps in "for consistency" and every clean lane grows a rescue commit. | C2 asserts `git log --grep='Leadv2-Rescue'` returns 0 commits on a clean lane. |
| R7 | Rescue commit deletes files (a worker killed mid-`rm`). | Assert `git diff --diff-filter=D --name-only main...HEAD` (three dots) empty; a delete-carrying rescue is still `dead_with_unlanded_work` but flagged `deletions=<n>` for human review. |
| R8 | SessionStart hook ordering regresses and the worktree GC wins. | The ordering is asserted in the suite by reading `hooks.json` order, not by hoping. |

## 7. Suite — `plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh` (to-create)

Every case drives the **real** `leadv2-dispatch-ledger.sh reap` against a real git fixture repo; only
`leadv2-lane-liveness.sh` is faked, one level lower, via `LEADV2_REAP_LIVENESS_BIN` (new; grep confirms
no `LEADV2_REAP*` collision in `plugins/`, `tests/`, `.claude/`).

| # | Case | Assertion |
|---|---|---|
| C1 | Worker `SIGKILL`ed — never SIGTERM, which a trap could catch, evaporating the proof — with an uncommitted diff | terminal `dead_with_unlanded_work`; a commit carrying `Leadv2-Rescue: true` exists; `git diff --diff-filter=D --name-only main...HEAD` empty; **no** `no_work` row for that sig |
| C2 | Mirror: clean tree, no artifacts | `no_work`; zero rescue commits |
| C3 | Cap slot freed | `active.yaml` row gone after reap, and a resume with `--task-id … --resume-lane` is **accepted**, not refused with `lead_session_lane_cap` (R1) |
| C4 | Multi-PID, one alive | liveness returns `alive` ⇒ funnel writes **nothing** |
| C5 | Dispatch `rc=0`, then `SIGKILL` | reported dead; `barrier=spawned_then_died` |
| C6 | **Empty `lane_writes` CSV + real diff** | still rescued — the `_PC_SCOPE_WRITES_CSV` self-disable is not reproduced (§0 row 6) |
| C7 | Rescue commit is unmistakable | author `rescue@leadv2.invalid`, trailer present, `RESCUE-UNREVIEWED` marker tracked |

**Negative control, inside the funnel's body:** move the `dispatch_ledger_write_terminal` call from
step 5 to before step 3 (terminal write before worktree inspection). C1 and C6 must go red. Proof in
the deliverable: `baseline_rc=0`, `mutated_rc!=0`, the literal red suite line, then reverted and green
with both exit codes pasted. Insert the mutation *inside* the function body — a top-level line-number
insert reddens everything for the wrong reason and reads as a pass (2026-08-25).

**Registration:** two `EXTRA_SUITE_MAP` rows in `tests/run-all.sh` (string-row form at `:134`) —
`leadv2-dispatch-ledger.sh:` and `leadv2-lane-liveness.sh:` → this suite. Prove with
`tests/run-all.sh --scope changed` after touching the ledger, and paste the selection line.

**Portability:** macOS bash 3.2 and the linux container. No `mapfile`, no associative arrays, no
`${var,,}`, no GNU-only `stat`/`date`. PID lists iterate through `while read -r` — never an unquoted
`$pids`, which does not word-split under zsh and reported every lane dead during the D2 investigation.

## 8. Out of scope — the implementer must not do these

- **Do not edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh`** (held). Not needed: `:6734` already
  calls `bash "${LEDGER_BIN}" sweep`; the funnel hangs off that existing call.
- **Do not edit `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`** (another architect).
- Do not modify liveness detection anywhere — that is D2. Consuming its CLI is the whole contract; a
  second opinion fails acceptance.
- Do not collapse the 24 state-write paths — that is D1.
- Do not build the merge guard that reads `Leadv2-Rescue`; D3 only makes the signal exist.
- No commits to `main` from a lane; no edits to `tests/known-red-suites.txt`; no weakened assertions;
  nothing under `~/MythicalGames`.

## 9. Self-check (architect)

- Env vars: `LEADV2_REAP_LIVENESS_BIN`, `LEADV2_REAP_ENABLED` — `LEADV2_*` prefix, no `LEAD_V2_*`
  drift, no collision found.
- Paths: every path cited was grep-verified at `c47a2273`; the suite file is `(to-create)`.
- `claude -p`: not applicable — the funnel spawns no model process.
- Concurrent access: R2/R3 name the two races (funnel vs resurrected worker, funnel vs funnel); both
  resolve on the existing terminal-ledger `flock`.
- Config contradiction: none — D3 stamps an existing enum and reuses an existing writer.

DELIVERABLE_COMPLETE
