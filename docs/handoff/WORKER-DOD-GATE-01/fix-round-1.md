# WORKER-DOD-GATE-01 — fix-round 1 (review FAIL high=2)

## READ THIS FIRST — the rules that killed the last four rounds
- **Pulse mode does NOT apply to you.** You have exactly one turn-chain; no notification will ever reach
  you. Never end a turn waiting for anything.
- **Never background a command whose result you need.** No Monitor, no `run_in_background`. Long commands
  run in the FOREGROUND with `timeout 900`.
- **Never spawn nested agents**, and never with `isolation:"worktree"` — the diff lands in a stray worktree
  nobody reads.
- **Commit after every step.** Four rounds today ended with uncommitted work.

**Class:** Standard fix-round. **Lane:** worktree-WORKER-DOD-GATE-01 (resume; merge `main` FIRST).

## The two findings (glm reviewer, committed diff from build-r3, live-probed)
1. `lib/leadv2-dod-gate.sh:40` — check (d) extracts only `+++ b/` lines, so a pure DELETION of a runtime
   state file passes the gate. Live-probed by the reviewer: a diff deleting `docs/leadv2/active.yaml` and
   `docs/LEAD_V2_STATE.md` returns `dod_pass check=runtime_state rc=0`. A worker can therefore delete the
   registry and the state file and the gate waves it through.
2. `lib/leadv2-dod-gate.sh:241` — check (b)'s mutation sub-check accepts ANY worker-authored
   `mutation-control/*.txt` containing one line `diff_hash=<hash>`. There is no provenance check, so the
   mission's own rule ("must be backed by a `leadv2-mutation-control.sh` artifact, not asserted prose",
   D7) is not enforced. The suite's own green fixture at `tests/test-worker-dod-gate.sh:158` passes with a
   hand-written one-line file, and the worker owns the diff and can compute its sha256 in one command.
   This is the gate's central claim, so it is the most important of the two.

## Do — one commit each
1. `## Review round 1 findings` in report.md: REAL/REFUTED + the evidence command per row.
2. Fix 1: parse BOTH sides of the diff (`--- a/` and `+++ b/`), so additions, modifications AND deletions
   of runtime-state paths are caught. Suite case: a deletion-only diff of `docs/leadv2/active.yaml` must
   return `dod_fail check=runtime_state`; negative control: revert to the `+++`-only parse in a mktemp FULL
   copy (including `lib/`) whose baseline is green → the case must go red. Paste both.
3. Fix 2: give the artifact provenance the worker cannot forge alone. At minimum the artifact must carry
   something only `leadv2-mutation-control.sh` produces — a run id plus the mutation's own before/after
   suite exit codes, and the gate must re-verify the recorded `diff_hash` against the diff it is checking
   AND reject an artifact whose contents do not match the generator's format. State plainly in the report
   what a worker can still forge; do not overclaim.
   Suite: hand-written one-line file → `dod_fail`; real generator artifact → `dod_pass`; negative control
   as above.
4. `tests/run-all.sh --scope changed` in the FOREGROUND with `timeout 900`; paste the tail. If it stalls,
   check `/tmp/leadv2-core-offline-*` for a lock whose holder pid is dead (`kill -0`), clear it, say so, re-run.
5. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
  `plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main` merged.

## Done when
- both findings REAL→fixed with pasted runtime output; the deletion case and the forged-artifact case both
  fail the gate; FALSIFIABLE; run-all tail present.
