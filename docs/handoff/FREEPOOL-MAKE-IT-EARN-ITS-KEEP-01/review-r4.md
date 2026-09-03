# Round-4 review — FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 (commit 7cb0c9d)

## Findings

1. [PASS] C-2 fixed and independently reproduced. In a scratch repo with no
   `origin/main`, a committed `bash -n`-failing file now returns rc=2 with
   `worker_output_gate_error reason=committed_range_unresolved` (self-run,
   not trusted from the suite). Restoring the pre-fix code
   (`committed_base=""`) reproduces the exact silent `rc=0` pass — my own
   mutation, not the test's — confirming the guard is load-bearing, not
   decorative. `test-worker-output-gate.sh`: 14/0 (was 12/0), mutates/restores
   `leadv2-worker-output-gate.sh` and `freepool-coder.sh` in place (backup/cp,
   no scratch-copy control). `git diff --stat` on both files is empty after
   the run — restore is real.
2. [PASS] Ranking provenance is now honest. `freepool-arm.yaml` says
   "No discriminating bash-3.2 editing bakeoff was run or recorded that
   round; this ordering is not a correctness or model-quality claim" and
   points at `round3-selector/*.log` (present, uncommitted — gitignored per
   `.gitignore:40`). Only `bakeoff/round2/` exists on disk; no fabricated
   `round3` bakeoff dir was invented to match the old comment.
3. [PASS] `report.md` no longer has a "Pending execution" section — rewritten
   with real suite output for all four controls. Present but **uncommitted**
   (commit 7cb0c9d touches only the 5 production/test files, not
   `docs/handoff/**`) — `.gitignore:40` hides it, consistent with the round-3
   note, but the brief explicitly said `git add -f <file>` one at a time and
   that did not happen. Minor process miss, not a functional one.
4. [PASS] Scratch-copy control removed from `test-freepool-model-liveness.sh`.
   `SELECTOR` points at the real `leadv2-freepool-model-select.sh`; mutation
   is applied/restored in place. Self-run: 7/0, `git diff --stat` on the
   selector empty after.
5. [CONFIRMED, not a fail] `tests/run-all.sh --scope changed` self-run:
   `[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held
   by a concurrent run)` — matches report.md verbatim. Genuinely blocked by
   a concurrent orchestrator in this shared worktree (confirmed: unrelated
   `docs/leadv2/.bus.lock` etc. are dirty from other lanes right now). Item 8
   was traced statically only, not proven end-to-end — carry to round 5.
6. [PASS] Self-ran the selector for all 4 roles live: implement rc=0/0s,
   bulk rc=0/2s, review rc=0/2s, read rc=0/3s (probe failure/failover on
   `read`, correctly advances rank). `report.md`'s first line names a model
   per role with timings, consistent in shape (my numbers are faster —
   normal network variance, not a discrepancy worth blocking on).

## Residual risk for round 5
- [Medium] The C-2 fix fails closed *unconditionally* whenever `origin/main`
  doesn't resolve via `merge-base`, even on an otherwise-healthy worker tree.
  Verified this lane's own `origin/main` resolves fine (git-worktree refs are
  shared), so production is not currently exposed — but no test proves a
  *legitimately isolated* clone (no shared refs, no remote) doesn't now get
  permanently misclassified `reason=parse_error` on clean work. Round 5:
  either confirm every freepool worker cwd is a `git worktree add` of this
  repo (refs always present) or add that as an explicit precondition check
  with its own error reason instead of reusing `parse_error`.
- [Low] `git add -f` the round-4 handoff artifacts
  (`report.md`, `round3-selector/`) so provenance survives lane cleanup.
- Carry forward: prove `--scope changed` end-to-end once the shared lock
  clears (item 8, still open).

## Fraction of dispatchable work the freepool arm can now actually carry
Gate no longer has a silent-pass hole and the ranking claim is honest — the
arm is safe to trust for **implement/bulk/read roles now** (~most trivial-to-
moderate multi-file edits); `review` role provenance is still latency-only
with no correctness bakeoff, so treat review-role freepool output as
**not yet earning its keep independently** — still needs the normal
adversarial gate on every diff, same as before this round.

VERDICT: PASS
