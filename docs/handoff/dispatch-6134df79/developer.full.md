verdict: APPROVE
next_action: review_round_2

# D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF — developer full report (dispatch-6134df79)

## Starting state

Lane `D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF` had two prior "died mid-task" rescue commits:
- `577283e8` — 382 rescued lines in `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`
- `f5fec3e3` — 46 more rescued lines

Reading the rescued diff showed the funnel was, in fact, essentially COMPLETE: `cmd_reap`,
`_dl_reap_one_lane` (the full ordered §2 funnel: enumerate → prove death via
`LEADV2_REAP_LIVENESS_BIN`/`LANE_LIVENESS_BIN` only → lock → re-check liveness under lock →
unscoped `git status --porcelain -uall` → rescue commit iff dirty → terminal write last),
`_dl_reap_rescue_commit` (unmistakable rescue commit: `rescue@leadv2.invalid` author,
`Leadv2-Rescue`/`Leadv2-Lane`/etc trailers, `RESCUE-UNREVIEWED` tracked marker, credential-path
exclusion), `_dl_reap_active_attempt` (cap-slot-free plumbing), and the `_dl_derive_lane_state`
fix (dirty tree routes to `dead_with_unlanded_work` via liveness instead of being OR'd into
`landed`). The full 7-case suite `test-reap-funnel-death-proof.sh` (C1/C1b/C2/C3/C4/C5/C6/C7) was
already present and already registered in `tests/run-all.sh`'s `EXTRA_SUITE_MAP` (two rows,
`leadv2-dispatch-ledger.sh:` and `leadv2-lane-liveness.sh:` → the suite, appended at the end of the
existing map — append-only respected by the prior worker).

## What I actually did this session

1. Read `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/brief.md` and `brief-pre-evidence.md` in
   full (no `context.yaml` exists for this lane — the mission text in `lane-mission.md` is the
   contract; there were no `decisions`/`off_limits` beyond what's in the mission's own §8/negative-
   control sections, which this report follows).
2. Verified, did not re-derive: ran the suite standalone — 19/19 green.
3. Ran the mandated negative control using the **real** `plugins/leadv2/scripts/leadv2-mutation-control.sh`
   tool (never hand-rolled sed timing games), mutation strictly inside `_dl_reap_one_lane`'s
   function body: `exit 11` inserted immediately before the `# Step 3: resolve the worktree...`
   comment (unique anchor, verified with `grep -c` = 1 before applying), which makes the funnel
   short-circuit to the clean-tree/`no_work` exit path as soon as death is confirmed, before it
   ever inspects the worktree — exactly the brief's instruction ("move the
   `dispatch_ledger_write_terminal` call from step 5 to before step 3"). Result:
   `baseline_rc=0`, `mutated_rc=1`, red line is C1's failure
   (`expected dead_with_unlanded_work/rescued=1, got: ...terminal=no_work...`). The tool mutates
   a scratch copy only — `git status --porcelain` on the real file was empty before and after,
   so there is nothing to "revert"; the suite is green again on the very next run (shown in
   `report.md`).
4. Found and fixed a **local-only** gotcha (matches my memory `run-all-scope-changed-state-file`):
   this worktree's `.git/worktrees/<lane>/leadv2-run-all-last-checked-sha` had already advanced to
   this lane's own HEAD from an earlier `run-all.sh` invocation by one of the dying workers, so
   `--scope changed` computed an empty range and selected nothing. Reset that file (local git
   metadata, not a tracked/shared path) back to the merge-base with `main`, then proved selection
   via the non-executing `LEADV2_RUN_ALL_SELECT_ONLY=1` seam:
   `[SELECT] .../test-reap-funnel-death-proof.sh`. Did not run the full always-on suite set
   (`run-core-offline.sh` alone is 10+ minutes per my own memory) — selection proof is sufficient
   and is what the brief asked for ("Prove with `tests/run-all.sh --scope changed` ... and paste
   the selection line").
5. `bash -n` on every shell file in the diff scope — all clean (no Python files were touched by
   this diff; the ledger's pre-existing `active.yaml` Python heredocs are untouched).
6. Wrote `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/report.md` (git-tracked, survives the
   `docs/handoff/*/*` gitignore blanket per line 50 of `.gitignore`) with all of the above pasted
   verbatim, plus the mutation-control artifact copied to
   `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/mutation-control/reap-funnel-negative-control.txt`
   (force-added past the directory-level gitignore, per my own memory on this exact gotcha).
7. Committed only `report.md` + the mutation-control artifact (`235d472c`) — the ledger script,
   suite, and `run-all.sh` rows were already committed by the two prior rescue commits; `git diff`
   confirmed zero uncommitted delta on those three files before I started. Commit pathspec
   deliberately excluded the shared control-plane files this worktree shows as dirty
   (`docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`) — those are concurrent-
   session state, not this lane's work, and the DoD gate's item (d) forbids touching them.

## Acceptance fixtures — verified against the live suite, not asserted

| # | Fixture | Suite case | Result |
|---|---|---|---|
| 1 | SIGKILL + dirty tree → `dead_with_unlanded_work`, rescue commit, no filtered deletions, `main...HEAD` diff-filter=D empty | C1 | PASS (4/4 sub-assertions) |
| 2 | Zero non-anchor commits + dirty tree → still `dead_with_unlanded_work` | C1b | PASS (2/2) — also independently covered by the pre-existing `leadv2-merged-worktree-sweep.sh`, whose `ahead!=0` and `real_dirt` checks are separate gates, not one conflated check, so a zero-commit dirty lane is never treated as deletable |
| 3 | Cap slot freed; resume accepted | C3 | PASS (4/4, incl. R1: original sig8 stays write-once-blocked but a fresh sig8 is never refused) |
| 4 | Mirror — clean tree, no artifacts → ordinary terminal, not "always rescue" | C2 | PASS (2/2) |

D2 consumption: verified by inspection — the ONLY two liveness calls in `_dl_reap_one_lane` are
both `bash "${liveness_bin}" --project-root ... --lane ...` (pre-lock probe and the R2 re-check
under the lock); no `ps`, `kill -0`, or mtime anywhere in the diff. `grep -n 'kill -0\|ps -\|pgrep'`
over the diff scope returns nothing.

## Known gap (reported, not fixed — see report.md "Known gap" section for full reasoning)

The brief's PRIMARY/SECONDARY automatic-trigger actors are not fully wired: `leadv2-stale-sweeper.sh`
(the brief's SECONDARY actor) is not registered in `plugins/leadv2/hooks/hooks.json` at all (grep, 0
hits), so nothing currently calls `reap` automatically at SessionStart ahead of the worktree GC. The
two *already-existing*, pre-D3 mechanisms (`dispatch_ledger_sweep_write_dead`'s dirty-aware terminal
choice, and the worktree sweeper's independent dirt-check) still prevent the original incident
(false `landed`/`no_work`, and premature worktree deletion) without `reap` ever running — but the
actual git rescue commit (this task's centerpiece audit trail) only happens when `reap` is invoked,
and today that's manual-only. I did not wire `hooks.json` myself: several other active sessions are
concurrently touching that file (visible in this turn's active-session list — multiple hook-parity
tasks in `review:fail`/`review:blocked`), and the brief's only explicit file lock is
`leadv2-dispatch-code.sh` — extending it to `hooks.json` felt like a call for the reviewer/founder,
not something to silently absorb into this diff. Recommend a narrow follow-up task.

DELIVERABLE_COMPLETE
