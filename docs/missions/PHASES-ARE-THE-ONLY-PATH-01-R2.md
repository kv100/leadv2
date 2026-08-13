# PHASES-ARE-THE-ONLY-PATH-01 — fix round 2 (plugin repo ~/Projects/leadv2)

Round 1 is commit `ed7adeb` in worktree `.claude/worktrees/d4d014e1`. It was reviewed and
**BLOCKED**. Continue from those edits — do not start over, do not revert. Full review:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-review.md`.

The whole point of this task is that a phase cannot be faked. Round 1 ships a gate that can be
satisfied by `touch`. That is worse than no gate, because it reads GREEN.

## F1 — BLOCKING. The review phase is permanently "proven" for the whole repo.
`leadv2-phase-record.sh:331-338`: `_verify_artifact` for the review phase ignores the artifact and
sha it just recorded and instead checks a repo-wide ledger file for non-emptiness. Once ANY review
has ever run in this repo, every future lane's review phase passes regardless of that lane's diff.

Fix: the review proof must be a ledger row keyed by **this lane's diff-hash**, per design §2. If the
diff-hash of the lane's current diff has no matching PASS row, the review phase is not proven.

## F2 — BLOCKING. `artifact_sha256` is written and never read.
`grep` confirms nothing reads it back. build/test/deploy/live_verify/e2e all degrade to a bare
`-f` existence check, not the per-phase content assertions the design table specifies. So

    touch fake && leadv2-phase-record.sh ... --artifact fake --status done

satisfies any of them with zero evidence, and the artifact can be overwritten with garbage
afterwards with no detection.

Fix: verification must re-hash the artifact at ASSERT time and compare against the recorded
`artifact_sha256`; a mismatch or a missing artifact fails the phase. Then implement the real
per-phase assertions from design §2: plan → `context.yaml` (or prepass design + .sig) with a
non-empty `decisions[]`; gate1 → the gate flag / acceptance block; review → the diff-hash-keyed
ledger row (F1); deploy → the commit is an ancestor of `origin/main`; close → `phase8-passed.flag`.
An existence check is not a proof and must not be left anywhere in this path.

## F3 — BLOCKING. The guard itself is untested.
`test-phase-precondition.sh` is 192 lines titled "guard matrix for `_phase_precondition_guard`" and
never calls the guard, never sets `LEADV2_REQUIRE_PHASES`. Every case pokes
`leadv2-phase-record.sh assert` directly. The warn / enforce / disabled behaviour wired into
`cmd_resolve` has zero coverage.

Fix: test `cmd_resolve` itself, end to end.
- `LEADV2_REQUIRE_PHASES` unset → journals `phase_precondition_warn` naming the missing phases,
  AND proceeds to spawn.
- `=1` → the same call is REFUSED with a distinct exit code, no worker spawned.
- `=0` → byte-identical to pre-C4 behaviour; assert no warn line is journalled.
- `--phase-waiver review=x` refused in every class, from plugin code not config default.
- A forged phase (`touch fake` + record + garbage-overwrite) is REJECTED — one test per F1 and F2.
Every new test must FAIL against `ed7adeb` and pass after the fix. Show both runs in your report.
A test that is green in both directions proves nothing; we caught exactly that twice today.

## Non-blocking, fix while you are here
- The design's `cmd_advance_arm` does not exist — the retry loop is inline in `cmd_resolve` and is
  already covered. Correct the stale reference; there is no live bypass.
- `lane_phase()` shells out to the liveness probe per running lane with a 3s timeout, uncached
  across renders. With several lanes in flight the menubar stalls for seconds. Cache per render pass.
- `phases.md`'s "model=skip ignored for review" is prose only, with no enforcement in
  `leadv2-router.sh`. Either enforce it in the router or say plainly in your report that it stays
  advisory, so nobody reads the prose as a guarantee.

## Confirmed clean by review — do not touch
One-writer discipline, and the single entry point (`backlog-pump.sh` and `fanout-lane-launcher.sh`
both route through `DISPATCH_BIN` into `cmd_resolve`).

## Base
Stay in worktree `d4d014e1`. Round 1 skipped the rebase that the mission asked for — do it now:
`git fetch origin && git rebase origin/main`, then record the SHA.

## Write set
Same as round 1. Do not widen it.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of both test runs (against `ed7adeb` and
after the fix).
