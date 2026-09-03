# D3 — terminal funnel with death proof: report

Continues from `577283e8` (382 rescued lines) and `f5fec3e3` (46 rescued lines). This session
verified the funnel already assembled on the lane, fixed the automated-selection gotcha in the
local test-runner state, ran the mandated negative control with the real `leadv2-mutation-control.sh`
tool (not hand-rolled), and committed.

## What was already on the lane (verified, not re-derived)

- `cmd_reap`, `_dl_reap_one_lane`, `_dl_reap_rescue_commit`, `_dl_reap_active_attempt` in
  `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh` — the full ordered funnel (brief §2): liveness
  gate via `LEADV2_REAP_LIVENESS_BIN`/`LANE_LIVENESS_BIN` only (no local liveness computation), lock,
  re-check liveness under the lock, unscoped `git status --porcelain -uall`, rescue commit iff dirty,
  terminal write last.
- `_dl_derive_lane_state`'s `landed` branch no longer ORs in a dirty tree — a dirty-no-commit lane
  now falls through to liveness and comes back `dead_with_unlanded_work`, never a false `landed`.
- `plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh` — 7 cases (C1/C1b/C2/C3/C4/C5/C6/C7)
  against the brief's four acceptance fixtures, driving the real `reap` subprocess against real git
  fixture repos, faking only `leadv2-lane-liveness.sh` one level lower.
- `EXTRA_SUITE_MAP` rows in `tests/run-all.sh` (`leadv2-dispatch-ledger.sh:` and
  `leadv2-lane-liveness.sh:` → the new suite) — already appended, at the end of the map (append-only
  respected).

## What this session did

1. Read `brief.md` and `brief-pre-evidence.md` in full, including the two addendum sections (the
   "zero non-anchor commits" incident shape) — already reflected in the suite as case C1b.
2. Ran the suite standalone — green, 19/19. Full output:

```
$ bash plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
[leadv2-dispatch-ledger] reap: lane=dispatch-c4c4c4c4 sig=c4c4c4c4 verdict=alive -- alive, writing nothing
[TEST] PASS: C1: SIGKILL+diff (with prior commit) -> dead_with_unlanded_work, rescued=1
[TEST] PASS: C1: terminal ledger row recorded
[TEST] PASS: C1: no no_work row for this sig
[TEST] PASS: C1: rescue commit carries no deletions (R7 n/a here)
[TEST] PASS: C1b: zero non-anchor commits + dirty tree -> dead_with_unlanded_work, rescued=1
[TEST] PASS: C1b: exactly one (rescue) commit ahead of main -- worker itself made zero
[TEST] PASS: C2: clean dead tree -> no_work, rescued=0
[TEST] PASS: C2: zero rescue commits on a clean lane
[TEST] PASS: C3: cap slot freed -- reaped lane's active.yaml row is gone
[TEST] PASS: C3: unrelated lane's active.yaml row untouched
[TEST] PASS: R1/C3: original sig8 stays write-once-blocked (by design)
[TEST] PASS: R1/C3: a fresh sig8 (resume's own mission text) is never refused by the terminal ledger
[TEST] PASS: C4: liveness=alive -- reap prints nothing
[TEST] PASS: C4: no terminal row written for an alive lane
[TEST] PASS: C5: --all reservation anti-join -> barrier=spawned_then_died, reported dead
[TEST] PASS: C6: empty/absent lane_writes CSV -- still rescued (unscoped probe, LANE-WRITES-IS-EMPTY-98-PERCENT-01 not reproduced)
[TEST] PASS: C7: rescue commit author is rescue@leadv2.invalid
[TEST] PASS: C7: Leadv2-Rescue: true trailer present
[TEST] PASS: C7: RESCUE-UNREVIEWED marker is tracked in the rescue commit

[TEST] 19 passed, 0 failed
```

3. **Negative control**, via the real `leadv2-mutation-control.sh` tool (never hand-rolled), mutation
   inside the funnel's body — the exact instruction from the brief ("move the
   `dispatch_ledger_write_terminal` call from step 5 to before step 3"). Concretely: `exit 11`
   (the clean-tree/`no_work` exit code) inserted immediately before the `# Step 3: resolve the
   worktree...` comment line, inside `_dl_reap_one_lane`'s locked subshell — so the funnel now
   short-circuits to a `no_work` write as soon as death is confirmed, before it ever runs
   `git status`. One occurrence, verified unique before applying (`grep -c` = 1).

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh \
    plugins/leadv2/scripts/leadv2-dispatch-ledger.sh \
    '/# Step 3: resolve the worktree via the real resolver/i\
      exit 11' \
    /tmp/d3-mc-run
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh file=plugins/leadv2/scripts/leadv2-dispatch-ledger.sh red_line=[TEST] FAIL: C1: expected dead_with_unlanded_work/rescued=1, got: lane_reaped task=c1c1c1c1 lane=dispatch-c1c1c1c1 barrier=cap_slot_held_by_dead_lane terminal=no_work rescued=0 commit=none resumable=yes diff_hash=... lane_diff_hash=...
```

Artifact (full, unedited): `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/mutation-control/reap-funnel-negative-control.txt`

```
suite=plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
file=plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
anchor=/# Step 3: resolve the worktree via the real resolver/i\
      exit 11
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: C1: expected dead_with_unlanded_work/rescued=1, got: lane_reaped task=c1c1c1c1 lane=dispatch-c1c1c1c1 barrier=cap_slot_held_by_dead_lane terminal=no_work rescued=0 commit=none resumable=yes
diff_hash=db807742b92d70804df1509dd733b77e3b004f36ab0d81b8c7a79dd3388844f9
lane_diff_hash=b6c33162b05a7c01cbf3e771db5237a1ed8147b1f4a18398ffb5fc769bd0ef46
```

`baseline_rc=0`, `mutated_rc=1` — C1 is the case that goes red (`red_line` above), exactly the case the
brief predicted ("C1 and C6 must go red"). The mutation-control tool applies the mutant in a scratch
copy only; the real file in this worktree was never touched — confirmed by `git status --porcelain`
on the file being empty both before and after the run. Revert is therefore implicit (nothing to
revert), and the suite is green again on the very next unmutated run — shown above (step 2) and
reconfirmed after this run:

```
$ bash plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh; echo "rc=$?"
... (same 19 PASS lines) ...
[TEST] 19 passed, 0 failed
rc=0
```

4. **Registration proof**, `--scope changed` selection only (no execution), after resetting this
   worktree's local `leadv2-run-all-last-checked-sha` marker back to the lane's merge-base with
   `main` (it had advanced to this lane's own HEAD from an earlier run by a prior dying worker,
   which made `--scope changed` see an empty range — a local git-metadata file under
   `.git/worktrees/<lane>/`, not a tracked repo file, so resetting it does not touch any other
   lane):

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep dispatch-ledger
[SELECT] .../plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh
```

5. Self-check — `bash -n` on every shell file touched, all clean:

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-ledger.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
```

No Python files were touched by this diff (the ledger script's existing Python heredocs for
`active.yaml` reads were pre-existing and unmodified by this session).

## Diff scope (this session's commit)

```
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh   | 432 ++++++++++++++++++++-
.../scripts/tests/test-reap-funnel-death-proof.sh  | 329 ++++++++++++++++
tests/run-all.sh                                   |   2 +
3 files changed, 752 insertions(+), 11 deletions(-)
```

(Measured against the lane anchor `8b06cc9b`; this session added only the report and the mutation-
control artifact on top — no further script edits were needed, everything above was already on the
lane from the two rescue commits.)

## Off-limits / out-of-scope respected

- Did not edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (held by another session).
- Did not edit `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`.
- Did not touch liveness detection anywhere — the funnel calls `LANE_LIVENESS_BIN` /
  `LEADV2_REAP_LIVENESS_BIN` exclusively, never `ps`/`kill -0`/mtime itself (grep-verified: no new
  liveness primitive in the diff).
- Did not touch `tests/known-red-suites.txt`, did not weaken any assertion.
- Did not touch `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*` — this
  worktree has unrelated pre-existing local modifications to those shared control-plane files from
  concurrent sessions; this commit's pathspec excludes all of them.
- `EXTRA_SUITE_MAP` was appended to, not reordered or edited elsewhere in the file (verified: `git
  diff` on `tests/run-all.sh` touches only the two new trailing rows).

## Known gap, reported rather than silently left

The brief's actor table (§1) names the dispatch-front `sweep` call
(`leadv2-dispatch-code.sh:6734`, out of edit scope) as the **PRIMARY** real-world trigger, and the
`leadv2-stale-sweeper.sh` SessionStart path as **SECONDARY**, with an explicit blocking ordering
constraint ("the `reap` call must run before any worktree GC on SessionStart"). Verified live:
`leadv2-stale-sweeper.sh` is **not** wired into `plugins/leadv2/hooks/hooks.json` at all today (grep,
0 hits) — it runs only at `/leadv2` slash-command startup, a different lifecycle than the
SessionStart hook chain `leadv2-merged-worktree-sweep.sh` (the worktree GC) belongs to. Neither
`leadv2-stale-sweeper.sh` nor any other SessionStart hook currently calls `reap`.

This is not a fixture regression: all four acceptance fixtures pass because the suite drives `reap`
directly, and the two *already-existing* mechanisms independently prevent the original incident even
without `reap` ever running automatically —
`dispatch_ledger_sweep_write_dead()` (pre-dates this task, `git log -S` confirms it predates the lane
anchor) already stamps `dead_with_unlanded_work` instead of a false `landed`/`no_work` when
`lv2_lane_dirty` is true, which is a TRUE terminal and already frees the cap slot; and
`leadv2-merged-worktree-sweep.sh` independently keeps any worktree with real `git status --porcelain`
dirt forever, regardless of `ahead` commit count (verified fixture-2's "zero commits + dirty" shape:
the `ahead != 0` check and the `real_dirt` check are two separate, both-must-pass gates, not one
conflated check — a zero-commit dirty lane is `real_dirt`-caught and kept independent of `ahead`).

What is **not yet wired**: the actual git *rescue commit* (the audit trail this task's design centers
on — unmistakable author/trailer/marker) only happens when something invokes `leadv2-dispatch-ledger.sh
reap`, and today nothing does so automatically. Wiring `leadv2-stale-sweeper.sh` (or a new SessionStart
hook entry) to call `reap --all` ahead of `leadv2-merged-worktree-sweep.sh` in `hooks.json` is real,
scoped follow-up work — deliberately not attempted in this session because `hooks.json` currently has
multiple other active lanes touching it concurrently (see the session list in this turn's context:
several `review:fail`/`review:blocked` hook-parity tasks), and the brief's own out-of-scope list places
"do not edit `leadv2-dispatch-code.sh`" as the only explicit file lock — `hooks.json` wiring is a
judgment call this report surfaces rather than making silently. Recommend a follow-up task rather than
scope-creeping it into this diff.
