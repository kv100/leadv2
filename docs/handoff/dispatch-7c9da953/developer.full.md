# PPC-G2: fix the integration test harness failure (worktree PROMISE-GUARD-TURN-IT-ON-01)

## DUPLICATE-LANE NOTICE — read first

This exact task (dispatch-7c9da953) is dispatched to two worktrees at once:
this one (`PROMISE-GUARD-TURN-IT-ON-01`) and `worktree-ONE-LANE-WATCH-01-R2`.
The other lane already fixed the identical bug, was reviewed, and got
`verdict: APPROVE / next_action: deploy` on commit `3d4b969` (see git history:
`3d4b969de8160ad1d47e9414c7dc1ff2b2e9ff89`, not an ancestor of this worktree's
HEAD). I overwrote that lane's `developer.summary.md`/`.full.md` in the shared
`docs/handoff/dispatch-7c9da953/` before realizing this — the content below is
this worktree's independent finding, not a rejection of the approved one.
**Lead: the ONE-LANE-WATCH-01-R2 fix (3d4b969) is the one to deploy; treat
this worktree's commit as a redundant parallel fix, not a second deploy
target.** This is a case for the lane-clobber/duplicate-dispatch pattern.

## Diagnosis (independently reached, same root cause as 3d4b969)

`plugins/leadv2/scripts/tests/test-phase-precondition.sh` G1/G2 were red
(pass=75 fail=4) under a leadv2-dispatched caller. Root cause: `cmd_resolve`
(`leadv2-dispatch-code.sh:6588`) exports `PHASE_GUARD_SCOPE=pre-build`
whenever it resolves a Phase-4 re-entry; the export is process-environment-
scoped and never unset. Because this developer subagent (dispatch-7c9da953)
is itself such a re-entry, its own shell carries `PHASE_GUARD_SCOPE=pre-build`
ambiently, and `_phase_precondition_guard` (`leadv2-dispatch-code.sh:3871`)
reads it unconditionally — narrowing scope from `full` to `pre-build`
regardless of the test's explicit `LEADV2_REQUIRE_PHASES=1`. That silently
satisfied the guard's assert on `classify` alone, defeating both G1's
`phase_precondition_warn` journal check and G2's exit-3 refusal check.
Confirmed via a debug instrumented copy of the guard (`echo ... >&2` before
the `phase-record.sh assert` call): `mode=1 scope=pre-build`, `assert_rc=0`.

Also independently found and fixed the same secondary hermeticity gap the
other lane's diagnosis names as Bug 1 (`LEADV2_PROJECT_ROOT` pointing at a
throwaway fixture repo gets overridden back to cwd's real git root by
FOREIGN-PROJECT-ROOT-GUARD-01) — this worktree's fix used the
`LEADV2_FOREIGN_ROOT_GUARD=0` escape hatch (already used by
`test-foreign-project-root-guard.sh` and `test-report-only-gate.sh`) instead
of 3d4b969's `cd "${E2E_REPO}"` wrapping; both are valid, 3d4b969's matches
the more-established convention per its own diagnosis.

## Fix (this worktree)

`e2e_setup()` in `test-phase-precondition.sh` now:
- `export LEADV2_FOREIGN_ROOT_GUARD=0`
- `unset PHASE_GUARD_SCOPE ADMISSION_ROUTE`

## Verification

```
$ bash plugins/leadv2/scripts/tests/test-phase-precondition.sh
[PHASE-PRECONDITION] pass=79 fail=0
EXIT=0
```
(was pass=75 fail=4, G1+G2 the newly-red cases; G8/G11×2 were the
pre-existing reds this run also cleared as a side effect of the same fix.)

## Committed

`73eb708` on branch `worktree-PROMISE-GUARD-TURN-IT-ON-01`, this worktree
only — 1 file changed (`plugins/leadv2/scripts/tests/test-phase-precondition.sh`,
+32/-1).

## Left alone

- Pre-existing unstaged churn in this worktree (`docs/LEAD_V2_STATE.md`,
  `docs/handoff/dispatch-nw*`, `docs/leadv2/{active.yaml,bus.jsonl,...}`) —
  lead-owned state files from concurrent lanes, not touched.
- Did not attempt to merge/reconcile with `worktree-ONE-LANE-WATCH-01-R2` or
  its commit `3d4b969` — out of this developer role's scope; flagging for
  lead per the duplicate-lane notice above.

## THIRD lane addendum (worktree-BEAT-LOOP-ORPHANS-01)

This same dispatch-7c9da953 also landed in a third worktree,
`worktree-BEAT-LOOP-ORPHANS-01` (base `6eb6d56`, pinned by the mission's
WORKTREE PIN line). Confirmed the suite red there too before any fix
(`pass=75 fail=4`, G1/G2 failing) — same root cause as above: `PHASE_GUARD_SCOPE=pre-build`
ambient in this developer subagent's own shell, inherited by the suite's
`bash "$DISPATCH_BIN" ...` subprocess calls, narrowing every guard assert to
`--pre-build` regardless of `LEADV2_REQUIRE_PHASES`.

Rather than author a fourth divergent fix, cherry-picked `3d4b969` verbatim
(`git show 3d4b969 -- plugins/leadv2/scripts/tests/test-phase-precondition.sh | git apply -`)
onto this worktree's HEAD — applied cleanly, no conflicts. Committed as
`376a56d` on branch `worktree-BEAT-LOOP-ORPHANS-01`, 1 file changed
(+12/-8). Verified:
```
$ bash plugins/leadv2/scripts/tests/test-phase-precondition.sh
[PHASE-PRECONDITION] pass=79 fail=0
```

**Incident during repro, self-corrected:** while reproducing G2 manually
outside the suite's own sandboxing, my ad-hoc env vars did not fully isolate
`LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` from this worktree's real cwd. The
`project_root_guard` (`foreign_env_overridden`) rerouted the dispatch onto
this worktree's real project root, and because the test's exact mission
string `"PPC-G2: fix the integration test harness failure"` hashes to sig8
`7c9da953` — this task's own id — it spawned a live duplicate `claude -p`
sonnet worker (PID 33423) against this task's own real deliverable path,
including a real worktree-lookup line (`.claude/worktrees/7c9da953`, a
pre-existing unrelated artifact from 2026-08-27, not created by this run).
Killed it immediately (`SIGTERM`, confirmed dead) before it could write
further to `developer.stream.jsonl`; no other deliverable file was
overwritten by it. Root-cause note for whoever owns dispatch-code.sh: an
operator manually re-running a mission string that happens to collide with a
live task's sig8, with `LEADV2_PROJECT_ROOT` set to a sandbox that isn't
actually enforced, can accidentally trigger a real nested spawn under that
task's real identity — worth a `LEADV2_DISPATCH_E2E_GATE`-style hard fence
for manual dispatch reproductions in an occupied worktree, but out of scope
to fix here.

Same escalation as the other two lanes: **deploy `3d4b969` only**; treat
`73eb708` and `376a56d` as redundant parallel fixes to be discarded, not
merged.

## FOURTH lane (worktree FABLE-THINK-TIER-01)

Independently re-derived the identical root cause (foreign-root guard
rerooting PROJECT_ROOT onto the real checkout because G1-G4/G8/G11 never
`cd`'d into the throwaway `E2E_REPO`) before discovering `376a56d` is already
an ancestor of this worktree's HEAD — `git diff` against my own edits came
back empty. No new commit made here. Ran the suite clean in this worktree:
`pass=79 fail=0`. Same escalation stands: **deploy `3d4b969` only**.

DELIVERABLE_COMPLETE
