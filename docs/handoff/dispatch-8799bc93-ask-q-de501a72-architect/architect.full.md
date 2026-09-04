# Architect decision — lane ownership, PROMISE-GUARD-TURN-IT-ON-01

DECISION_OPTION: a
RATIONALE: active.yaml registers a live, non-stale worker (s-20260901T191543Z-58137-3926, pid 91307, phase=e2e, born 22:16:41Z) on this exact worktree — the "unknown writer" is the lane's legitimate owner, so this session must not race it.

## Evidence (probed 2026-09-01 ~22:26 local)

1. `docs/leadv2/active.yaml:303-318` — registered session on this lane:
   - `task_id: PROMISE-GUARD-TURN-IT-ON-01`, worktree/branch = this worktree
   - `session_id: s-20260901T191543Z-58137-3926`, `pid: 91307`, `pid_birth: Tue Sep 1 22:16:41 2026`, `pid_role: worker`, `phase: e2e`, `stale: false`
2. `plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh` mtime `Sep 1 22:25` — inside the live session's window (born 22:16:41), consistent with pid 91307 writing it, not with an orphan.
3. Git log on this lane: `fa1fd31 salvage(PROMISE-GUARD-TURN-IT-ON-01): worker finished with uncommitted work`, `5f657a4 … (salvaged by lead)`, `af18aaa … round 3 — make suite failures real failures` — the lane already went through a lead-side salvage; the round-3 "honesty fixes" this session didn't write are that salvage/finisher lineage, not corruption. Reverting them (as the earlier header edit did) was wrong; they are canonical lane work.

## Why (a) and not (b)

- The other writer is not stale: it is registered in active.yaml with a live pid and `stale: false`, started 70 minutes ago and actively writing (mtime within its lifetime). Option (b) would have this session clobber the registered owner's round-3 fixes — exactly the parallel-writer hazard already burned on this repo (lane salvage-commit hazard, 2026-08-31).
- Two writers on one lane file is the defect; (a) removes one writer without discarding either side's work. The round-3 honesty fixes and this session's header edit can be reconciled by the owner at its commit, or by lead at merge.
- This session's mandate after standing down is still productive: verify-only — run the falsifiable gate + suites read-only, report results — no edits, no commits, no reverts of the other writer's bytes.

## Residual risk

- If pid 91307 dies mid-write, the lane has no writer; mitigation: this session reports that in its verify report and lead re-salvages (established path, fa1fd31).
- This session's already-reverted header edit stays reverted; if the header change mattered, it goes through lead as a note, not a silent re-edit.

DELIVERABLE_COMPLETE
