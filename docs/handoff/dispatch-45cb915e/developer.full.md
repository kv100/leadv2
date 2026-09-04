verdict: APPROVE
next_action: review_round_2

# WORKER-DOD-GATE-01 — fix round 1 (developer)

## Scope

`docs/handoff/WORKER-DOD-GATE-01/fix-round-1.md`: two HIGH-severity glm-reviewer
findings against `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`.

## Finding 1 — check (d) missed deletion-only diffs

`_dod_diff_paths()` only parsed `+++ b/` lines, so a pure deletion of a
runtime-state file (`+++ /dev/null`) never surfaced a path and the check
passed undetected. REAL — reproduced pre-fix in an isolated mktemp full copy
(negative control), where the same deletion-only diff of
`docs/leadv2/active.yaml` returned `dod_pass` instead of `dod_fail`.

Fix: `_dod_diff_paths()` now unions both `--- a/` and `+++ b/` sides
(deduped via `sort -u`), so additions, modifications, and deletions are all
caught.

Verified: deletion-only diff of `docs/leadv2/active.yaml` -> `rc=1`,
`dod_fail check=runtime_state_in_diff`. Negative control (revert to
`+++`-only parsing in the mktemp full copy, same fixture) -> goes green
incorrectly, confirming the control is discriminating. Both pasted in
`report.md`.

## Finding 2 — check (b) mutation-control artifact was forgeable

Any file under `mutation-control/*.txt` containing a single hand-written
`diff_hash=<hash>` line was accepted as proof of a real mutation-testing
run, with no check that it came from `leadv2-mutation-control.sh`. A worker
could compute sha256 of their own diff and write one line. REAL — confirmed
by hand-crafting such a file and observing `dod_pass`.

Fix: new `_dod_valid_mutation_artifact()` requires the full generator shape
— non-empty `suite=`/`file=`, `baseline_rc=0` (baseline must have been
green before mutating), `mutated_rc` numeric and non-zero (mutation must
have actually turned the suite red), and `diff_hash` matching the diff
under test. Check (b)'s artifact-search loop now calls this instead of a
bare `grep -q diff_hash=`.

Verified: hand-written one-line artifact -> `rc=1`,
`dod_fail check=mutation_control_not_via_runner`. Real
`leadv2-mutation-control.sh`-generated artifact -> `rc=0`,
`dod_pass check=paste_evidence`. Negative control in the mktemp full copy
(revert to bare `grep -q`) -> the hand-written forgery goes green again,
confirming the control discriminates. All three pasted in `report.md`.

**What a worker can still forge**: the fields' *values* — nothing prevents
someone from writing `suite=foo`, `baseline_rc=0`, `mutated_rc=1`, and a
correctly-computed `diff_hash` by hand without ever running the mutation
tool for real, since the gate only checks shape and hash-match, not that
the suite/anchor actually exist or that the sha256 was produced by an
actual run. Full provenance (e.g. a signed run-id from the runner) was out
of scope for this round; stated plainly in `report.md`, not overclaimed.

## Suite

`test-worker-dod-gate.sh`: replaced the old single hand-written-artifact
case (previously incorrectly expected `dod_pass`) with two cases (forged ->
fail, generator-shaped -> pass), plus a new deletion-only check-(d) case.
Result: 29/29 passed, 0 failed.

## `tests/run-all.sh --scope changed` (foreground)

Required multiple retries due to infrastructure issues unrelated to the
fix, all diagnosed with evidence (not guessed):
- Two stale `flock` locks at `/tmp/leadv2-core-offline-*.lock` held by dead
  pids (one pre-existing pid 30758, one my own timed-out run's pid 8127
  that didn't clean up on SIGTERM — bash 3.2 trap semantics) — cleared
  after confirming via `kill -0`.
- `--scope changed`'s state file (`.git/leadv2-run-all-last-checked-sha`)
  is written before suites run, so timed-out attempts silently consumed
  the diff range for the next attempt — reset to `HEAD~1` before retries.
- The suite genuinely needed more wall-clock time (1800s, not the
  suggested 900s) under concurrent load from sibling lanes' own test runs.

Final result: `run-all: 4 passed, 1 failed, scope=changed` — the one
failure is the pre-existing `run-core-offline.sh` baseline red, unrelated
to this diff (matches known pre-existing-reds memory). `test-worker-dod-gate.sh`
explicitly selected and passed 29/29. Full tail pasted in `report.md`.

## `leadv2-suite-falsifiable.sh` (from lane root)

Verdict: falsifiable — a failure injection turned the suite red (rc=1).
Pasted in `report.md`.

## Closing proof — gate against its own diff+report.md

Initial self-check failed with `dod_fail check=mutation_control_not_via_runner`
because the existing mutation-control artifacts in the task dir were bound
to a stale (build-round-3) `diff_hash`, correctly rejected by the new Fix 2
provenance check — this is proof the fix works, not a bug. Fixed by
generating a fresh `leadv2-mutation-control.sh` artifact bound to this
round's own diff hash. Re-ran in a clean isolated subshell (to rule out
interactive-shell tracing noise seen in an earlier attempt): `rc=0`, all
four checks `dod_pass`. Pasted in `report.md`.

## Commits (this round)

- `5a5bbff6` — both fixes + suite updates + report.md findings/fix sections
- `2fc8fc65` — run-all + falsifiability sections in report.md
- `32290bdb` — closing self-check proof in report.md

## Constraints honored

- Only committed `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`,
  `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh`,
  `docs/handoff/WORKER-DOD-GATE-01/report.md` — all LANE_WRITES.
  `docs/leadv2/**`, `docs/LEAD_V2_STATE.md`, `phases.d/`, other lanes'
  journals left dirty/untracked, never staged (confirmed shared live
  runtime state from concurrent sessions).
- All mutants/fixtures built in mktemp full copies, never in the lane's
  own working tree.
- `main` merged, working tree clean of anything beyond pre-existing shared
  runtime-state files.
- No Monitors, no nested agents, no `isolation:"worktree"`. Long-running
  `run-all` invocations exceeded the harness's own 600s tool cap and were
  auto-backgrounded by the harness itself (not a chosen Monitor/background
  pattern); each time I waited in-turn for the result before proceeding,
  never ending a turn on an outstanding wait.

DELIVERABLE_COMPLETE
