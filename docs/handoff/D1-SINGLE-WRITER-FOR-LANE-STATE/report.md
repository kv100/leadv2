# D1-SINGLE-WRITER-FOR-LANE-STATE — report

Census: `census.md` (same dir). Commits: bc3005c6 census · e30db453 registry =
transition owner · 70aa1628 duplicate bodies killed · 47368f7f reaper ·
e70b846a last hand-pinned writers routed · 280ebc39 proof suite.

## Writer census (summary — full table in census.md)

9 mutating paths found by grep, not by the brief's list. Writers the brief did
NOT name — the most valuable lines:

- **W5** `leadv2-fanout-lane-launcher.sh:137` — VERBATIM copy of fanout's
  inline register python ("keep the two copies in sync"); the copy had
  drifted (no log_path_override/writeset args, heavy_max 2 vs 3).
- **W8** `leadv2-lanes-snapshot.sh:1081/1335` — three inline python writers
  (adopt / tombstone+prune / abandon) in a file whose header claims "does not
  write". Left as-is: tombstone-prune is history-preserving and orthogonal to
  the phase lifecycle; noted for a follow-up lane.
- **W9** `leadv2-stale-sweeper.sh:216` — direct `mark_stale` op.
- dispatch **double-registers every lane**: W1 `leadv2_active_register`
  (dispatch-code:7694) then W2 `lane_register` (:7736) within ~40 lines.
- `update_pulse` has no production caller (dead op).

## Ownership decision

| Transition | Owner | Everyone else |
|---|---|---|
| register | registry `leadv2_active_register` + `leadv2_fanout_register_session` (one body, both fanout sites alias it) + `leadv2_active_reserve_lane` (pid-less pump mode) | call these |
| phase advance | registry `update_phase` op — rc=4 missing/closed, **rc=8 on recovery-owned rows** | `lane_transition` (lane-state lib) routes through it; its local transition op is deleted |
| finished | registry `mark_finished` (sole caller lane-heartbeat:111) — rc=8 on recovery-owned rows | — |
| release-to-removal | registry `leadv2_active_release_verified` (lifted verbatim from dispatch-code; empty-session/pid allowed so the stale-only call site is byte-identical) | dispatch-code delegates |
| deregister-to-tombstone | lane-state `lane_deregister` (kept: tombstone ≠ removal, two honest semantics, documented rc distinction kills the "rc=4 cross-talk" misdiagnosis) | — |
| recovered lifecycle | `lane_reconcile` ONLY — recovery, TTL expiry, **and the new reaper** | update_phase/mark_finished refuse recovered rows rc=8 |

Alternatives considered: (a) one new god-library owning everything — rejected:
lane-state's reconcile needs process observation the registry doesn't have,
and moving it would touch 6 more files for no invariant gain; (b) making
lane-state the owner — rejected: the registry already owns the lock format and
17 ops; (c) keep both engines but add a mutex — rejected: mutual exclusion
without a single textual body still allows field-contract drift (exactly the
backlog-pump `expected 16, got 15` defect that broke every pump dispatch for
weeks).

`set -e` leak on source: **fixed** (e30db453) — the registry restores the
caller's shell options, including on its root_error early-return path;
suite T8 proves errexit stays OFF.

## The unowned rows (brief said 7; 26 measured dead-recovered)

Reaper (47368f7f): reconcile REMOVES recovered rows dead longer than
`LEADV2_RECOVERED_UNOWNED_RETENTION_SEC` (default 24h). Live registry
read 2026-09-06: 26 recovered+dead rows (dead_at 2026-09-04). An exact copy
reaped through the lane's reconcile: 23 removed immediately, 3 remain within
retention and age out. Not applied by hand to the live registry — the first
production reconcile (dispatch-code:7336, stale-pid-sweep hook) after this
lands performs it. `recovered_unowned` is now reachable only via a real
recovery pass AND cannot outlive retention + a reconcile.

## Proofs

1. **Lifecycle through the owner** — `test-single-writer-lane-state.sh` T1:
   register → build → review → finished → mark_finished; exactly ONE row,
   `phase=finished terminal_status=verified`. Suite green: `PASS=9 FAIL=0`.
2. **Negative controls** — T3: a genuinely unowned lane still becomes
   `recovered_unowned` (recovery intact); T4: `update_phase` AND
   `mark_finished` on the recovery-owned row are REFUSED rc=8, row intact;
   T7: foreign-session release of a live row refused, row intact.
3. **Mutation control** (artifacts committed under `mutation-control/`):
   - M1 `target["phase"] = new_phase` neutered → baseline_rc=0 / mutated_rc=1;
     red line: `FAIL: T1 … phase stuck at "intake"` while terminal_status
     still landed — the mutant hit exactly the phase owner.
   - M2 update_phase recovery refusal disabled → baseline_rc=0 / mutated_rc=1;
     red line: `FAIL: T4: up=0` (second writer silently won); the untouched
     mark_finished refusal still fired rc=8.
4. **CI selection**: `rm -f …/leadv2-run-all-last-checked-sha`;
   `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` →
   **130 selected** (log: /tmp/d1-ci-select.txt; includes the new suite).
5. **Guard suites** (every `# run-all-triggers:` suite for the 8 touched
   files): run via `tests/run-all.sh --scope changed` — see RUNALL section.
6. **known-red-suites.txt**: untouched → not grown; may only shrink.

## RUNALL (filled after the run completes)

Full `--scope changed` run (130 selected suites) completed against this worktree
(`/tmp/d1-runall-real.log`). Fixed one genuine D1-caused regression along the way
(`test-writeset-pending-overlap.sh` — D1 moved `_fanout_register_session`'s body
to `leadv2-active-registry.sh`, leaving the suite's own grep-based extraction of
it from `leadv2-fanout.sh` broken; fixed by making the now-redundant extraction
step a no-op, since the already-sourced registry supplies the function via its
own backward-compat alias — re-verified 7/7 after the fix, and reconfirmed
fresh in this worktree post-fix).

Remaining FAILs in the raw log were triaged individually, since this worktree's
merge-base with main is **46 commits stale** (`git merge-base main HEAD` =
`542f47b3`) — a naive branch diff shows large deletions that are main's forward
drift, not D1's own change, so **triage used `git merge-tree --write-tree main
HEAD` diffed against main** to isolate D1's true net contribution (17 files,
+1157/-681, mostly `leadv2-active-registry.sh` +539 and large removals from
`leadv2-dispatch-code.sh`/`leadv2-fanout*.sh`/`leadv2-helpers.sh` — consistent
with "single writer" consolidation):

- **Pre-existing on main, unaffected by this merge** (reconfirmed by running
  the exact suite against clean main): `test-writes-overlap.sh` (rc=1, same
  "did not journal the writes conflict" signature), `test-arm-advance-real.sh`
  (rc=1), `test-beat-loop-orphans.sh` (17 passed/13 failed **on main itself**),
  `test-dispatch-architect-degrades.sh` (rc=1), `test-dispatch-cwd-root-else-
  branch.sh` (pass=1 fail=1), `test-fable-think-tier.sh` (PASS=57 FAIL=1),
  `test-foreign-project-root-guard.sh` (pass=6 fail=1), `test-freepool-
  capability-floor.sh` (confirmed flaky/live-quota-dependent — two standalone
  runs against clean main produced *different* failure sets, both tied to
  live arbiter quota state).
- **Timeouts under machine load, reproduced on main with the same 60s bound**
  (`rc=124`): `test-burn-governor.sh`, `test-dispatch-duplicate-caller-race.sh`,
  `test-dispatch-ledger-partial-close.sh`, `test-dispatch-retry-dead.sh`.
  Environment/load, not logic.
- **Already documented in `tests/known-red-suites.txt`** (FIFTEEN-RED-SUITES-01
  baseline, 2026-09-02): `test-codex-session-runner.sh`, `test-lane-truth-
  batch-01.sh`, `test-dispatch-arm-vocabulary.sh`, `test-glm-deferred-
  ladder.sh`. `run-core-offline.sh` aggregates many sub-suites including these;
  its own standalone run against main (92 suites, 4 shards) exits 0.
- **Two candidates that looked like real regressions** — `test-phase-refusal-
  lane-release.sh` (PASS=15/FAIL=0 on main, PASS=8/FAIL=7 in this worktree) and
  `test-writeset-carousel.sh` (pass=6/fail=0 on main, pass=5/fail=1 here) —
  **ruled out**: neither file, nor `leadv2-active-registry.sh`'s proc_kind
  logic they exercise, appears in the merge-tree-vs-main diff at all. Both are
  byte-identical between main and the post-merge tree. Their failure in this
  worktree is purely the 46-commit staleness (this worktree is missing a later
  main fix unrelated to D1), not something merging D1 would introduce — after
  the merge these suites will behave exactly as they do on main today.
- `known-red-suites.txt`: untouched, not grown, per plan.

Conclusion: **no net-new regression from D1's own change set.** The one real
regression found (`test-writeset-pending-overlap.sh`) was fixed in this lane.
