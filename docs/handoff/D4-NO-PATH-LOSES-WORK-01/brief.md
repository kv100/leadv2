# D4 — NO PATH LOSES WORK — BUILD MISSION BRIEF

Repo: `~/Projects/leadv2`. Binding: `docs/handoff/WAVE4/shared-constraints.md` (read it first —
three-dot deletion check, negative control inside the function body, EXTRA_SUITE_MAP append-only).

## Goal
Nothing outside a dying worker is responsible for that worker's dirty worktree. Make something
outside responsible. One night, 2026-09-03: six hand-rescues, then a host-app crash took seven
lanes with 1-2 commits and 11-20 dirty files each — nothing committed, nothing announced.

## The invariant in one sentence
**Once every process whose cwd is inside a lane worktree has exited, that worktree's dirty files
are committed onto its own lane branch by the next orphan-checkpoint pass, with no human git
command.** (Test-checkable: kill worker → run pass → `git -C <wt> log -1` shows the checkpoint.)

## Every loss path, with file:line

| # | Path | Where | Why it loses |
|---|---|---|---|
| L1 | Worker exits non-zero off the finalize path | `lib/leadv2-worker-epilogue.sh:85` is called INLINE only — `glm-coder.sh:1815`, `kimi-coder.sh:1661`, `freepool-coder.sh:1916`, `claude-subsession.sh:1128,1287` | No trap anywhere. Any exit that skips those lines skips the commit. |
| L2 | Worker SIGKILLed | same 5 call sites | Killed process never reaches its own next line. |
| L3 | Host app dies, whole tree goes | same + `leadv2-dispatch-product-close.sh:2583,2612,2665` | All three checkpoint mechanisms live INSIDE the dying process tree. Nothing external exists — the only cron on this box is `leadv2-status-collector-guard.sh`. |
| L4 | Mission declared no `LANE_WRITES` | `lib/leadv2-worker-epilogue.sh:107-114` | Bails with `foreign_dirty=undeclared_lane_writes`, commits nothing, by design. |
| L5 | Close path with empty scope CSV | `leadv2-dispatch-product-close.sh:1910-1911` (`LEADV2_STOP_GATE:-1`; `_PC_SCOPE_WRITES_CSV` empty ⇒ `return 0`) | STOP-GATE silently no-ops. |
| L6 | Turn-cap backstop is the only external one, and it is narrow | `leadv2-turncap-checkpoint-commit.sh:4-8` | Fires ONLY from `leadv2-session-runner.sh` on `--max-turns` exhaustion. Not on kill, not on crash. |
| L7 | Dirty lane is protected but never resolved | `leadv2-worktree-cleanup.sh:216-221` (`KEPT (dirty-uncommitted)`) | Sweeper correctly refuses to delete, so dirt accumulates forever, unattributed and invisible. This is the 7-lane residue. |
| L8 | Swept while starting / before first commit | `leadv2-worktree-cleanup.sh:239-241` (`worktree remove --force` + `branch -D`) | Gated today by `lv2_worktree_protected` (`:170`) + liveness (`:196`). The gate is only as good as the liveness verdict — see L9. |
| L9 | Liveness judged by log mtime | `leadv2-lane-liveness.sh:84` (`LEADV2_LANE_SILENT_MAX_S:-900`, `LEADV2_LANE_ABANDON_MAX_S:-3600`), age at `:890-895`, `no_pid_recorded` fallback at `:997` | A 13-min-idle lane and a 26-min-idle lane are both `silent:` and neither is `dead:` until 3600s. That is exactly why the seven deaths were invisible. |
| L10 | Targeted reap trusts its caller | `leadv2-worktree-cleanup.sh:471`; invoked ungated at `leadv2-dispatch-code.sh:3503` | `--name` is deliberately ungated. Today `:3498`/`:3502` pre-check clean+ahead=0, so it is safe — but nothing in the sweeper enforces that for a future caller. |
| L11 | "Landed" without commits on main | `leadv2-lane-liveness.sh:108-110` treats any commit in the lane's own worktree inside the finished-window as a completed round | A checkpoint commit now also looks like a completed round. Must stay distinguishable. |

**`leadv2-dispatch-code.sh` is READ-ONLY for this lane.** The natural fix site — the
front-of-dispatch ledger sweep that already calls `leadv2-lane-liveness.sh --all` — is inside it.
Do not touch it. Prescribed nearest permitted seams: `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh`
(already a SessionStart hook, so no `settings.json` edit) and `leadv2-phase8-close.sh:654`
(already resolves and invokes the sweeper). A cron line is a follow-up ledger row, not lane work.

## What existing machinery already covers
1. `leadv2_worker_commit_epilogue` (`lib/leadv2-worker-epilogue.sh:85`) — clean voluntary exit,
   scoped to `LANE_WRITES`. Covers nothing once the process is killed.
2. `pc_stop_gate_autocommit` (`leadv2-dispatch-product-close.sh:1909`) — writes
   `wip(<sig8>): auto-checkpoint on worker exit (STOP-GATE)`, temp-index, scope-safe, dedup-safe
   (`diff --cached --quiet` ⇒ no empty commit). **This is the commit the fleet already carries.**
   `leadv2-dispatch-code.sh:3158-3185` already consumes it as cutoff proof. It is good code.
   Its only defect is *when* it runs: in-process, close path, and only with a non-empty scope CSV.
3. `leadv2-turncap-checkpoint-commit.sh` — external to the killed worker, turn-cap only.

**Do not reinvent any of these.** The gap is not the commit logic; it is that no *external,
periodic* actor ever invokes it. Reuse `lib/leadv2-mission-writeset.sh` for scope resolution and
copy `pc_stop_gate_autocommit`'s temp-index + `diff --cached --quiet` discipline verbatim.

## Mechanism chosen + its blind spot
**External orphan-checkpoint sweeper**, `plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh`.
1. A periodic in-lane commit dies with the lane; it cannot survive its own host.
2. An EXIT/trap handler does not run on SIGKILL and does not run when the host app tears down the
   whole process tree — the two failures actually observed. It cannot satisfy the invariant alone.
3. Only an actor outside the dying tree survives all three deaths, so the sweeper is the primary.
4. It is also the only one that can retire L7: a protected-dirty lane becomes a committed lane.
5. The trap is kept as a cheap SECOND commit (below), never as the guarantee.

**Blind spot, stated plainly:** the sweeper protects only what reached the filesystem, and only
after its next pass. Edits still in model context are lost exactly as before; and between the death
and the next pass the work is as fragile as today — a `rm -rf`, a disk loss, or an ungated `--name`
reap (L10) inside that window still destroys it. Latency is bounded by invocation frequency, not
by the mechanism. It also cannot attribute dirty files the mission never declared; those go to a
quarantine branch, never silently into the lane's own history.

## Liveness rule
**Authoritative: a lane is ALIVE iff some process's current working directory is inside the lane
worktree path.** Not mtime, not argv, not a status field.

- mtime is not it: `leadv2-lane-liveness.sh:84` calls 13-min and 26-min idleness both `silent:`
  and neither `dead:` until 3600s — the measured cause of the invisible loss.
- A bare process count is not it either: 14 unrelated `claude` processes were running.
- argv / `pgrep -f <worktree>` is not it: **measured on this machine 2026-09-03** — 22 pids
  matched, including pid 9721, an interactive `/bin/zsh` in a tests subdirectory. Over-counts.
- **Verified prescription (measured, same run):** one global pass
  `/usr/sbin/lsof -a -d cwd -Fpn` returns the pid→cwd map for all ~801 processes in **<1s**;
  prefix-match cwd against `<repo>/.claude/worktrees/<lane>`. Per-pid confirmation is
  `/usr/sbin/lsof -a -d cwd -p <pid> -Fn`; both returned correct cwds for live lane workers.
- **Trap: do NOT pass the directory to lsof.** `lsof -a -d cwd -- <dir>` matches EXACT cwd only —
  it returned 0 rows here while 22 processes were live under that tree. Global pass, then filter.
- Fail-closed: if `lsof` is missing or the pass errors, treat every lane as ALIVE and checkpoint
  nothing this pass. Same posture as `lv2_wt_protect_prime`'s rc 5.
- Do not weaken `leadv2-lane-liveness.sh`. Add the cwd rung as a new signal; the sweeper consults
  cwd-liveness FIRST and only falls through to the existing verdict when cwd says "no process".

## Files allowlist
CREATE — `plugins/leadv2/scripts/leadv2-orphan-checkpoint.sh`
CREATE — `plugins/leadv2/scripts/lib/leadv2-lane-worker-alive.sh` (the cwd probe; one inode,
sourceable, no side effects on source; `lv2_lane_cwd_prime` / `lv2_lane_worker_alive <wt_path>`)
CREATE — `plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh`
EDIT — `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh` (invoke checkpointer BEFORE any sweep)
EDIT — `plugins/leadv2/scripts/leadv2-phase8-close.sh` (at the `:654` sweep block, same ordering)
EDIT — `tests/run-all.sh` (EXTRA_SUITE_MAP: APPEND at end of block, never reorder)
EDIT (2nd commit, optional) — `lib/leadv2-worker-epilogue.sh` + one line each in `glm-coder.sh`,
`kimi-coder.sh`, `freepool-coder.sh`, `claude-subsession.sh` to arm the EXIT trap
READ-ONLY — `leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`,
`leadv2-lane-liveness.sh`, `leadv2-worktree-cleanup.sh`, `lib/leadv2-worktree-protected.sh`

## Steps
1. Build `lib/leadv2-lane-worker-alive.sh`: one global `lsof` pass primed per sweep, prefix-match
   per worktree, fail-closed to ALIVE. Bound the call with a timeout — an unbounded probe at the
   front of a hook is the `LANE-LIVENESS-CODEX-TIMEOUT-01` mistake repeated.
2. Build `leadv2-orphan-checkpoint.sh`. Per worktree under `.claude/worktrees/`, in order:
   (a) skip if `lv2_lane_worker_alive` — never race a running worker;
   (b) skip if clean (`git status --porcelain --untracked-files=all` empty) — no empty commits;
   (c) resolve scope via `lib/leadv2-mission-writeset.sh`; in-scope paths commit to the lane
       branch, out-of-scope dirty paths go to `orphan-quarantine/<lane>` and are journaled, never
       merged into the lane's own history (same hazard class as `foreign_dirty`);
   (d) commit through a throwaway `GIT_INDEX_FILE` (`read-tree HEAD` → `add -- <concrete paths>`),
       abort on `diff --cached --quiet` — lift this verbatim from
       `leadv2-dispatch-product-close.sh:1990-2020`;
   (e) message `wip(<lane>): auto-checkpoint on orphan sweep (ORPHAN)` — a DISTINCT token from
       `(STOP-GATE)` so L11 stays decidable and `_dispatch_checkpoint_commit_cutoff`'s exact-string
       grep (`leadv2-dispatch-code.sh:3175`) is unaffected;
   (f) journal one line per lane (`checkpointed` / `skipped_alive` / `skipped_clean` /
       `quarantined`) and print a summary — silence is what made the seven deaths invisible;
   (g) `--dry-run` and `LEADV2_ORPHAN_CHECKPOINT=0` one-flag rollback.
3. Wire it ahead of both sweep invocations (hook + phase8). Checkpoint-then-sweep ordering is
   load-bearing: sweeping first is the `b413968c` discard-then-remove incident.
4. Recovery is a command, not a runbook: after checkpoint, the lane re-attaches with
   `leadv2-dispatch-code.sh --task-id <founder-id> --resume-lane` (both flags required). State it
   needs: the worktree at `leadv2-lane-worktree.sh path-of <id>`, the checkpoint commit on
   `worktree-<lane>`, and the four re-dispatch stores cleared (session-id, receipt, `active.yaml`
   row, task lock). The checkpointer must PRINT that exact command per checkpointed lane.
5. Append EXTRA_SUITE_MAP rows and prove selection.

## Acceptance (re-runnable; each must kill the real failure)
- **A1 SIGKILL worker.** Scratch worktree, worker writes dirty tracked + untracked files,
  `kill -9 <worker>`. Run the checkpointer. Assert the files are in `git log -1` of the lane
  branch. No manual git command anywhere in the test.
- **A2 whole tree dies.** Spawn parent + child in one process group, dirty the tree,
  `kill -9 -<pgid>`. Run the checkpointer. Same assertion. This is the seven-lane case.
- **A3 idempotent.** Run the checkpointer twice on A1's lane. Assert exactly ONE `(ORPHAN)` commit
  and that pass 2 exits 0 with `skipped_clean`.
- **A4 clean lane.** Untouched worktree. Assert `rev-parse HEAD` is unchanged and no empty commit.
- **A5 live worker protected.** A process with cwd inside the worktree, still running. Assert the
  checkpointer skips it (`skipped_alive`) and commits nothing.
- **A6 out-of-scope dirt.** A dirty file outside `LANE_WRITES`. Assert it lands on
  `orphan-quarantine/<lane>` and NOT in the lane branch.
- Keep the production function REAL: fake only `lsof` (one level lower, via a stub on PATH).
  A test that stubs the checkpoint function proves nothing.
- Report exit codes on macOS AND in a linux container.

## Negative control
Suite: `plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh`
Mutation, applied INSIDE the body of `lv2_orphan_checkpoint_lane()` in
`leadv2-orphan-checkpoint.sh` (never at file top level): change the dirty probe
`--untracked-files=all` → `--untracked-files=no`. A killed worker's NEW files become invisible and
A1/A2 must go RED. Show RED with the mutation, revert, show GREEN, record both exit codes verbatim.
Second control (optional, same body): delete the `diff --cached --quiet` guard → A4 must go RED.

EXTRA_SUITE_MAP rows to APPEND at the end of the block (`tests/run-all.sh:134+`):
```
leadv2-lane-liveness:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-worktree-cleanup:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-phase8-close:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-merged-worktree-sweep:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
leadv2-worker-epilogue:plugins/leadv2/scripts/tests/test-leadv2-orphan-checkpoint.sh
```
Prove selection: paste `tests/run-all.sh --scope changed` output showing the suite in the selected
set. Stem match alone covers only `leadv2-orphan-checkpoint.sh`; every other guarded file needs
its row.

## Out of scope
- Any edit to `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`,
  `leadv2-claude-profile-select.sh`, `tests/known-red-suites.txt`.
- Rewriting `pc_stop_gate_autocommit` or `leadv2_worker_commit_epilogue` semantics. Reuse them.
- Changing `LEADV2_LANE_SILENT_MAX_S` / `ABANDON_MAX_S` or any existing liveness verdict string —
  `test-lane-liveness-authoritative.sh` locks them. Add a rung, do not retune.
- Deleting or loosening any sweeper protection gate. The sweeper keeps dirty lanes; that stays.
- crontab / launchd installation (founder-owned; file a scheduled-decisions row instead).
- Merging any lane branch to main. Recovery re-attaches a lane; it does not land it.
- Auto-committing anything in `~/MythicalGames` or m3's tracked `.claude/settings.json`.

---

## LEAD ADDENDUM — liveness has TWO cases, and the suite must catch BOTH false answers

The `lsof -a -d cwd` rule above is right for the sweeper's case: scanning a worktree when you hold
no handle for its worker. It is not the only case, and the lane must not collapse the two.

When the handle IS available, use it. The dispatcher already prints
`handle=PID=<pid> LABEL=developer-dispatch-<sig>-<ts>`; `kill -0 <pid>` then asks the kernel
directly and depends on nothing about the command line. Measured 2026-09-03 on four live lanes:
four PIDs, four distinct sigs, no duplicates, instant.

Both false answers are real and were both observed the same evening, so the suite asserts against
each by name:

- **False zero** — `ps`/`pgrep` on a narrow pattern (`worktrees/<lane>`) reports 0 while a worker
  is alive, because the lane name does not sit next to `worktrees/` in every process's argv.
- **False life** — the same probe widened to the bare lane name reports several processes when
  none is a worker: the dispatcher itself and its helpers carry the lane name in argv because it
  was passed as `--task-id`. This is the more dangerous of the two: a dead lane looks busy, so
  nobody resumes it. A false zero at least sends someone to look.

Acceptance is therefore NOT "the liveness function returns something". It is: construct a lane
whose worker is alive but invisible to the narrow pattern, and a lane whose worker is dead while
the wide pattern still matches its dispatcher, and assert the chosen rule gets BOTH right. A fix
that only cures the false zero has swapped one wrong answer for a worse one.

Finally: the brief's own finding — that all three existing checkpoint mechanisms run INSIDE the
dying process tree — is the whole reason this row exists. Keep it at the top of the report. It
explains, precisely, why six hand-rescues and seven dead lanes happened despite the machinery
that was already there.
