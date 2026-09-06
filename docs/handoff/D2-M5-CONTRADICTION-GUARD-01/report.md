# D2-M5 — E0 contradiction guard (D2-SINGLE-LIVENESS-VERDICT)

## Change

Added the evidence ladder's E0 rung to `leadv2-lane-liveness.sh`'s
`resolve(tid)`, evaluated FIRST — before the existing pid/birth/kind
resolution logic ever runs. Per the brief (§3, E0 row): a structural fact
about the registry that no evidence can rescue, decisive →
`unknown:contradictory_rows`, never `alive`, never `dead`.

Three independent triggers, checked in this order:

1. `len(sessions_all.get(tid) or []) > 1` — more than one `active.yaml` row
   for the same `task_id`.
2. The row's `worktree` (realpath-resolved) equals `PROJECT_ROOT`
   (realpath-resolved) — the second corruption named in #14.
3. A genuine WORKER pid (i.e. `worker_pid` present AND
   `worker_pid_role != "watcher"` — `lead_durable`/`watcher` pids are
   excluded, same exclusion the rest of the file already applies, since a
   lead session's own pid legitimately spans every lane it dispatches) is
   recorded as the owner of more than one lane.

New module-level `worker_pid_to_tids: Dict[int, Set[str]]`, built once
alongside the existing `sessions`/`sessions_all` maps, so `resolve(tid)`
can see a CROSS-LANE pid-ownership collision, not just facts local to the
one lane being resolved.

## Ordering dependency (satisfied)

The brief requires M5 land only after D1 M1
(D1-SINGLE-WRITER-FOR-LANE-STATE), which makes duplicate `active.yaml` rows
for one `task_id` impossible to CREATE going forward — landing E0 first
would flip live lanes with pre-existing duplicates to `unknown` with no
writer able to repair them. D1 merged to main as `1b02faf9` earlier this
session, before this work started.

## New test

`test-lane-liveness-e0-contradiction.sh`:
- **C1**: two rows for the same `task_id` → `unknown:contradictory_rows`.
- **C2**: a row whose `worktree` equals `PROJECT_ROOT` →
  `unknown:contradictory_rows`.
- **C3a/C3b**: one worker pid (`$$`, a real live pid with a real captured
  `ps -o lstart=` birth) recorded as `worker_pid` for TWO different
  `task_id`s → BOTH resolve `unknown:contradictory_rows`.
- **C3c**: neither of the two pid-sharing lanes reads `alive` — satisfies
  the brief's "at most one lane alive" assertion (here: zero, a valid
  subset of "at most one").
- **C4 (regression sanity)**: a normal single-row, single-owner, genuinely
  live worker lane (same fixture shape as
  `test-lane-registry-self-deadlock.sh` case (d)) is UNAFFECTED and still
  resolves `alive` — proves the guard does not over-fire on the common
  case.

6/6 pass on the first real run (no test-construction bugs this time — the
fixture pattern was copied directly from an existing, already-debugged
suite: `LEADV2_STATE_ROOT` sandboxing + `leadv2-state-path.sh` resolution +
a real `ps -o lstart=` birth capture, matching
`test-lane-registry-self-deadlock.sh`'s case (d)).

## Mandatory negative control (mutation-control-proven, brief §7 C7)

Mutated line 975 (`if _e0_reason is not None:` → `if False:  # D2 E0
mutation gate`, exactly the mutation the brief's own C7 row prescribes).
Suite goes RED on C1: with the guard neutralized, the duplicate-row
fixture falls through past E0 to the existing handoff-dir check and
resolves `dead:no_handoff_dir` instead of `unknown:contradictory_rows` —
the exact false-death this rung exists to prevent. GREEN on the committed
code.

## Commit

`4742d502`.

## CI selection

`test-lane-liveness-e0-contradiction.sh` carries its own
`# run-all-triggers: leadv2-lane-liveness.sh` self-registration line
(the pattern this repo has moved to — see
`SUITE-SELECTION-COVERS-140-OF-390-01` in
`test-codex-lead-intake.sh`/`test-worktree-enforce-liveness.sh` — rather
than a hand-maintained `EXTRA_SUITE_MAP` row), so
`tests/run-all.sh --scope changed` picks it up on any future edit to
`leadv2-lane-liveness.sh` without a separate registration step.

## Remaining D2 work (per Leadmain's sequencing)

M6 (dedupe `leadv2-lanes-snapshot.sh`'s duplicate `_commit_age_s()` rule) —
next, lower priority than M5 per Leadmain ("dedup without an external
defect is cleanup"). `leadv2-active-registry.sh` (×4 latent EPERM sites)
and `leadv2-lane-state.sh` remain Leadmain's own sequencing/lane.
