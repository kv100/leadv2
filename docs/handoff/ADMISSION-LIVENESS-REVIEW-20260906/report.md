# ADMISSION-LIVENESS-REVIEW — 2026-09-06

Adversarial cross-file review of the lane ADMISSION and LIVENESS path (canonical plugin source, worktree `ADMISSION-LIVENESS-REVIEW-01`, base `de49c66e`). Read-only on code. All paths relative to `plugins/leadv2/scripts/` unless absolute.

Known-true defects NOT re-reported (per mission): (1) `_lv2_ws_overlaps` bare-string comparison; (2) four root authorities; (3) `_lane_writes_guard` four satisfiers, three leave no disk trace; (4) `near_reset_wait` uncapped (16.8h on 168h window).

## Findings

| Sev | Finding | Files | Divergent input | Blast radius |
|-----|---------|-------|-----------------|--------------|
| CRIT | Two copies of the lane-row release decision; the unverified one wins at runtime | `leadv2-dispatch-code.sh:6858-6871,6913,8605,8874-8887,4965-5095`; `leadv2-fanout-lane-launcher.sh:431,495-508`; `leadv2-fanout.sh:2005-2010`; `leadv2-active-registry.sh:701-703` | `dispatch_confirm` write fails after a verified-live spawn → arc=5 → dispatch-code preserves row, disarms slot, `exit 1` → launcher/fanout `*` arm unregisters the preserved row by bare task_id | Orphaned live worker (invisible to placement probe → duplicate dispatch, worktree clobber), task unclaimed and re-dispatched, write-once `dead` terminal poisons failure memory; fanout also relaunches a full cycle → two workers on one lane |
| HIGH | Funnel finalize rows carry worktree=PROJECT_ROOT + pid=null, so the `finished:` rung measures the MAIN checkout | `leadv2-fanout-lane-launcher.sh:436-462`; `leadv2-fanout.sh:886+`; `leadv2-lane-liveness.sh:854-862,670-688` | A funnel worker dies with no commit; any commit lands on MAIN within 1800s (founder work, another lane's merge) | Dead-uncommitted lane resolves `finished:Ns` on the board — silent lost work, no re-dispatch, deliverable unlanded; fabricated for every such row on every main commit |
| HIGH (live now) | Fanout cap counts every non-stale row; nothing ever sets `stale`; dead_at is ignored by every cap reader | `leadv2-fanout.sh:335,361,662-664`; `leadv2-stale-sweeper.sh:168`; `skills/leadv2-close/SKILL.md:226`; `lib/leadv2-lane-state.sh:172-299` | Live registry: 39 non-stale rows vs `hard_limit=3` (probe below) | Every fanout launch hard-refused `hard_limit reached`, not `--force`-bypassable; funnel backlog starves while 37 provably-dead rows still count |
| HIGH | Admission conflict path exits 5 with no liveness/kind/birth check and no TTL | `leadv2-active-registry.sh:528-538,549,398-403,301-307` | A with-writes row whose pid is recycled/bystander → overlapping dispatch | Lane permanently undispatchable (exit 5 forever); only manual registry surgery clears it — extends the bystander-pid defect into the with-writes path |
| MED | `leadv2_active_check_limits` is a dead gate presented as the fleet cap | `leadv2-active-registry.sh:1496-1592` (zero callers, twice-derived) | — | Reader believes caps are enforced at register; actually only fanout selection (buggy counter, above) and lane-state per-lead cap (default 64) exist |
| MED | Dedup signature is mission-text-only | `leadv2-dispatch-code.sh:2184` (`compute_sig`) | One-word mission change → new sig | Ledger `duplicate_task_signature` guard bypassed; backstop = writeset intersect on rows that are 98% writes-empty live, compared bare-string (known #1) — the CACHE-TRUTH-01 duplicate-dispatch shape |
| LOW-MED | Registry mutators silently no-op for unregistered tasks | `leadv2-active-registry.sh` update_phase/update_pulse/set_writes (for-loop, no else) | Row already unregistered (e.g. by F1's `*` arm) | Phase/pulse truth vanishes with rc=0; callers cannot detect they are writing into the void |
| LOW | Journal appends fail as success; render dir collides per-second | `leadv2-journal.sh:11` (`trap 'exit 0' ERR`); `/tmp/lv2-render-$(date +%s)` | mkdir/permission failure on append | Journal loss is invisible to every caller (rc=0); same-second renders overwrite each other |

## F1 — CRITICAL — the unverified release copy wins

`atomic_dispatch_reserve_spawn_confirm` (`leadv2-dispatch-code.sh:6872-7038`) documents its own contract at `:6858-6871`: rc 5 = "worker may be live but unrecorded… caller MUST treat this hard". `dispatch_confirm`'s failure returns 5 at `:6913` — the code's own comment reads `# live worker, but confirmation write failed` — **after** the worker was verified spawned. The candidate loop honors it: the `5)` arm (`:8874-8887`) clears `DISPATCH_SLOT_REG_ID` (disarm) and `exit 1`; the re-arm case (`:8604-8605`) deliberately excludes 5 (`2|3|4|6` only).

dispatch-code's own release path is hardened: `_release_registered_lane` (`:4965-5095`) is an owner-verified compare-and-delete (session_id + pid + pid_role under flock). The launcher and fanout bypass it with the registry's bare `leadv2_active_unregister` (`leadv2-active-registry.sh:701-703` — unconditional `[s for s in sessions if s.get("task_id") != task_id]`):

- Launcher `*` arm (`leadv2-fanout-lane-launcher.sh:495-508`): rc 1 matches none of `0|2|3|6`, so it unclaims (`:497`), **unregisters the row dispatch-code just preserved** (`:498`), writes the write-once `dead "dispatch_code_failed_rc_1"` terminal (`:499`), reaps the worktree if unused.
- Fanout `*` arm (`leadv2-fanout.sh:2005-2010`): same unregister (`:2008`, gated on `_reserve_rc -eq 0`), then `_fanout_launch_full_cycle` (`:2009`) — a second full cycle against a possibly-live worker.

Which copy wins: the unverified one — it runs after dispatch-code exits and is rc-blind.

Observability (honest): the live `dispatch-ledger.jsonl` carries **0** `dispatch_code_failed_rc_*` rows (grep, 2026-09-06); the only occurrence in the state tree is one string inside a deferred-message file (`~/.claude/leadv2-state/leadv2/glm-deferred.d/b22dc98b.md`). The divergence is structural, not yet observed on the ledger.

## F2 — HIGH — the finished rung reads MAIN's HEAD for funnel rows

On rc=0 the launcher finalizes (`:436-462`) by unregistering its interim row and calling `_fanout_register_session`, which writes `worktree=$PROJECT_ROOT` (`leadv2-fanout.sh:886+`); `pid_val` stays `"null"` unless the handle is `PID=<n>` form. Nothing later corrects the field: `leadv2_active_set_worktree` has zero callers (verified by tree grep + `git log -S`, twice-derived).

`leadv2-lane-liveness.sh`'s `finished:` rung (`:854-862`) fires when the row's pid is gone and `commit_age_s(session.get("worktree"))` (`:670-688` — `git -C <worktree> log -1 --format=%ct`) is ≤1800s. For a funnel row that is `git -C $PROJECT_ROOT` — the **main checkout**. Any main commit within 30 minutes — the founder's own edit, another lane's merge, a status-surface commit — makes a funnel lane whose worker died *uncommitted* resolve `finished:<age>`: the third state designed to mean "completed round" is satisfied by someone else's commit on a different worktree. The lane leaves the re-dispatch pool silently; the unlanded deliverable is the only trace. Secondary: the unregister→re-register pair at `:453-455` leaves a no-row window a concurrent placement probe can observe.

## F3 — HIGH, live now — a cap that counts rows nothing clears

Fanout's inline selection (`leadv2-fanout.sh:335`) filters `not s.get("stale")`, counts `total_active = len(sessions)` (`:361`), and hard-refuses at `:662-664` — with no `--force` bypass (force only skips rows).

Every input to that count is broken on today's tree:

- `stale` is set by exactly one setter — `leadv2-stale-sweeper.sh:168` — and the sweeper has **no invoker**: no hook, no command, no script references it (verified by tree grep of `plugins/leadv2` + `hooks/` + `commands/`). `skills/leadv2-close/SKILL.md:226` claims the sweep "runs automatically at every SessionStart" — false on this tree.
- `dead_at` (written by `lane_reconcile`, `leadv2-lane-state.sh:172-299`) is read by no cap counter: fanout filters `stale` only; the registry's own `check_limits` (F5) is dead code.
- `reconcile` re-creates `recovered`/`recovered_unowned` visibility rows on every pass over an existing worktree; they accumulate (26 in live state, 0 with declared writes).

Live probe (read-only, 2026-09-06, `~/.claude/leadv2-state/leadv2/active.yaml`): **39 rows, `stale`=0 on all, 37 with `dead_at` set, 26 `recovered_unowned`, meta `hard_limit=3`**. 39 ≥ 3 → every fanout launch through this path refuses with "hard_limit reached" while 37 of the counted rows are provably dead.

## F4 — HIGH — admission's conflict exit trusts any row with writes

The register admission loop (`leadv2-active-registry.sh:477-538`) reaches `:535-538`: writeset intersect → print + `sys.exit(5)` — with **no** `_pid_alive`, no `_proc_kind`, no birth corroboration, no TTL. `_lv2_ws_live_worker` (`:398-403`, the interactive-lead exclusion) is consulted only on the NO-writes path. The refresh branch (`:549`) at least checks `_pid_alive` — bare `kill -0` (`:301-307`), no birth.

Consequence: a row that declares writes and whose pid is a recycled or bystander pid permanently refuses every overlapping dispatch — no pending-window expiry applies (the `_lv2_ws_pending` window ages out no-write rows; the with-writes conflict path fires before it matters), nothing reaps it, and the only exit is hand-editing the registry. This is the with-writes extension of the bystander-pid defect already filed for the no-writes path. Context: there are six implementations of "is this pid the lane's process" (registry admission `:301-307`; registry refresh `:549`; lane-state `alive()` `lib/leadv2-lane-state.sh:106-114` — kill-0+birth; liveness `pid_state` `leadv2-lane-liveness.sh:238-280` — kill-0+birth+lstart; `lib/leadv2-lane-worker-alive.sh` — kill-0+cwd; dispatch's sonnet check `leadv2-dispatch-code.sh:3173-3240` — bare kill-0 on a handle). The admission side — the gate that decides whether work may start at all — is the weakest of the six.

## F5 — MED — dead gate presented as the fleet cap

`leadv2_active_check_limits` (`leadv2-active-registry.sh:1496-1592`) filters `not s.get("stale")` (same broken predicate as F3) and has **zero callers** — derived twice: (a) tree-wide grep over `plugins/leadv2`, `hooks/`, `commands/`; (b) `git log -S "check_limits"` shows no call site ever added beyond the definition. It is the same disease as the self-documented dead `REQUIRE_MISSION_WRITESET=0` gate (`leadv2-dispatch-code.sh:4141-4167`): a reader auditing the registry believes per-class caps are enforced at admission; the only live caps are fanout's buggy selection count (F3) and lane-state's per-lead cap (`lib/leadv2-lane-state.sh:144-149`, default 64).

## F6 — MED — dedup key is the mission text

`compute_sig` (`leadv2-dispatch-code.sh:2184`): `tr -d '\r' | tr -s '[:space:]' ' ' | sed … | shasum -a 256` over the mission string only. A one-word re-wording of the same task produces a new sig8, so the ledger's `duplicate_task_signature` refusal never fires for it. The backstops are the writeset intersect — live rows are 98% writes-empty (registry census above) — and `_lv2_ws_overlaps`' bare-string compare (known #1). Net: the duplicate-dispatch shape of CACHE-TRUTH-01 is reachable by editing one word of a mission.

## F7 — LOW-MED — mutators no-op silently for unregistered tasks

In `leadv2-active-registry.sh`, `update_phase`/`update_pulse`/`set_writes`/… iterate `for s in sessions: if s.get("task_id") == task: …` with no else and no not-found signal; the bash wrappers return 0 when the yaml is absent. A row removed by F1's `*` arm (or any unregister) makes every later phase/pulse write vanish with rc=0 — the dispatcher records nothing and reports success. The dispatch-ledger sweep then sees artifactless rows and can attribute `dead:no_*` terminals to lanes whose phase truth was never written.

## F8 — LOW — journal loss reports success

`leadv2-journal.sh:11` sets `trap 'exit 0' ERR`: a failed append (mkdir/permission/enospc) always returns 0, so no caller — including the durable-journal writers that back the rc contract in F1 — can ever detect that the disk-truth record was not written. Same family: render temp dirs named `/tmp/lv2-render-$(date +%s)` collide for same-second renders.

## Uncertainties (one settling command each)

- Whether the funnel path is load-bearing in production for this repo: `grep -c 'single-worker funnel launch' ~/.claude/leadv2-state/leadv2/*.jsonl ~/.claude/cache/leadv2-events/leadv2.jsonl`.
- F1 real-world frequency (confirm-write failures): `grep -c 'dispatch_rollback_failed\|confirm_failed' ~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl`.
- F3's blast assumes the live registry at `~/.claude/leadv2-state/leadv2/active.yaml` is the one fanout reads (it is — `leadv2-state-path.sh` resolves there; `docs/leadv2/active.yaml` in-repo is a stale render, known).

## Evidence artifacts

- Live registry census (read-only python over `~/.claude/leadv2-state/leadv2/active.yaml`, 2026-09-06): 39 rows; stale=0; dead_at=37; recovered_unowned=26 (0 with writes); meta hard_limit=3, heavy_max=2, light_max=3, standard_max=2; session id prefixes f-/s-/recovered mixed; worktree field is main-repo for every f- row.
- `grep -c 'dispatch_code_failed_rc_' ~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl` → 0.
- Twice-derived zeros: `check_limits` callers (tree grep + `git log -S`); `stale-sweeper` invokers (tree grep over scripts/hooks/commands); `set_worktree` callers (tree grep + `git log -S`).

## Falsification set

- Code files changed by this review: **none** (read-only mission). `bash -n` and `python3 -m py_compile` over changed shell/python files are therefore vacuous — no changed file exists to check. `git status` clean before the report was written.
- Changed-scope test runner (`tests/run-all.sh --scope changed`, this worktree, 2026-09-06):

```
<RAW_OUTPUT_PENDING>
```

## Most dangerous thing not in the known-true list

F1: the lane-row release decision exists in two copies with opposite contracts — dispatch-code's owner-verified compare-and-delete versus the launcher/fanout's rc-blind unregister-by-task-id — and the unverified copy is the one that runs last, so on exactly the input where the hardened copy was built to hold the line (arc=5, worker verified live, row deliberately preserved), the other copy deletes the row, unclaims the task, writes an unretractable `dead` terminal, and (fanout) starts a second worker against the same worktree.
