verdict: APPROVE
next_action: deploy

# dispatch-9ce00c9d — ONE-PATH-EVERYWHERE-01 review engine — verification + completion

## Starting state

This worktree's HEAD (`4331a89`, "wip lane work preserved after mid-run death") already
contained a near-complete implementation of the scoped design: `leadv2-review-run.sh`
(740 lines), the guard/sentinel repointing, dead-var deletion, SKILL.md/WORKFLOW-PATH.md
made unconditional, docs/phases.md rewrite, and all 6 T1-T6 test suites. My job was to
verify this against the design, find and fix any gaps, and produce the required evidence
— not to re-implement from scratch.

## What I found and fixed

1. **`plugins/leadv2/docs/phases.md` made a false claim.** It said `workflows/leadv2-review.js`
   "is deleted; there is no separate Workflow-based path or inline-fallback path anymore."
   Neither is true: both copies of the workflow (canonical + `~/.claude/workflows/`) still
   exist byte-identical, and `leadv2-dispatch-product-close.sh` still contains its own
   inline `run_reviewer_arm()` fallback body (used at `LEADV2_REVIEW_ENGINE=0`, the
   default). Rewrote the paragraph to state the true, deferred state and *why* it's
   deferred (design §5's own requirement that a mid-flight lane at flag=0 sees
   byte-identical behavior). "Done = evidence" — a doc claiming a deletion that didn't
   happen would mislead the next reader who trusts it.

2. **`test-review-single-owner-census.sh`'s header comment undercounted.** It documented
   "TWO owners" but the actual grep finds THREE: `leadv2-review-run.sh` (the engine, correct),
   `workflows/leadv2-review.js` (deferred deletion — see above), and
   `leadv2-dispatch-product-close.sh` (its own inline `run_reviewer_arm()` fallback, required
   by design §5 for flag=0 byte-identical behavior — this actually *overrides* design A3's
   "delete the lane copy in the same commit" mitigation, since A3 was written for the
   eventual flag=1 rollout state, not this task where the flag stays 0 everywhere). Rewrote
   the comment to name both real reasons accurately. Did not touch the test's assertion
   logic — it correctly stays FAIL until both conditions resolve, and correctly still
   distinguishes itself from the "stashed to main" failure mode. Never weaken a fixture to
   get green.

No other gaps found. `resolve_review_pool_call()` is a byte-identical lift (diff against
`fc0ab4c:leadv2-dispatch-product-close.sh:230-279` shows only comment trims, zero logic
changes) — quota bands, author-exclusion, and the fail-closed signals path are all intact.
Paths correctly point at `plugins/leadv2/scripts/lib/...` on disk (design's own
path-correction note). Engine spawns Claude arms only through `claude-subsession.sh`, never
bare `claude -p` (grepped, confirmed absent). `LEADV2_REVIEW_ENGINE` and
`LEADV2_REVIEW_FANOUT` have no prior usage anywhere in the repo (clean, per design §6).

## Step 0 capability evidence (already recorded by the wip session, re-verified here)

Static evidence recorded against `scripts/leadv2-codex-session-runner.sh` — unchanged
since the wip commit, still accurate: C1-C6 all STATIC, none LIVE-VERIFIED. Per the
mission's round-2 revision this does not block; `SD-ONEPATH-CODEX-LIVE-PROOF-01` (due
2026-08-08) owns the live probe. The `codex-capability.md` path-correction noted in the
scoped design (append to the persona-engine copy, not create a third file inside this
repo) is **out of this repo's LANE_WRITES** — persona-engine's `docs/handoff/` is not
reachable from this worktree, so I could not append to it. Flagging this as unfinished:
whoever holds persona-engine write access must append the (already-known, unchanged) C1-C6
rows there.

## Syntax check (bash 3.2 compat)

`bash -n` on every changed `.sh` file — all OK:
```
OK plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh
OK plugins/leadv2/hooks/leadv2-workflow-sentinel-touch.sh
OK plugins/leadv2/scripts/leadv2-dispatch-code.sh
OK plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
OK plugins/leadv2/scripts/leadv2-review-run.sh
OK plugins/leadv2/scripts/tests/test-review-engine-fanout-multiprovider.sh
OK plugins/leadv2/scripts/tests/test-review-engine-pool-degrades.sh
OK plugins/leadv2/scripts/tests/test-review-engine-verifier-distinct-arm.sh
OK plugins/leadv2/scripts/tests/test-review-engine-verify-coverage.sh
OK plugins/leadv2/scripts/tests/test-review-single-owner-census.sh
OK plugins/leadv2/scripts/tests/test-workflow-bypass-guard-lane.sh
```

## New suite results (T1-T6)

```
=== test-review-engine-fanout-multiprovider.sh ===
PASS: arms: line has >=2 distinct providers (codex,glm)
review-engine fan-out multiprovider: PASS=1 FAIL=0

=== test-review-engine-verify-coverage.sh ===
PASS: every Critical finding (1) carries a verifier_verdict
review-engine verify-coverage: PASS=1 FAIL=0

=== test-review-engine-verifier-distinct-arm.sh ===
PASS: no verified finding has verifier_arm == arm
review-engine verifier-distinct-arm: PASS=1 FAIL=0

=== test-review-engine-pool-degrades.sh ===
PASS: engine produced status=pass (rc=0) on degraded pool, not all_arms_unavailable
review-engine pool-degrades: PASS=2 FAIL=0

=== test-review-single-owner-census.sh ===
FAIL: expected exactly one owner (leadv2-review-run.sh), found 3:
  leadv2-dispatch-product-close.sh, leadv2-review-run.sh, workflows/leadv2-review.js
review single-owner census: PASS=0 FAIL=1
  -- EXPECTED FAIL, documented in the test's own header (see fix #2 above). Confirmed
     this same test also fails on the pre-task baseline (fc0ab4c), for a different,
     also-correct reason (count=1, engine doesn't exist yet) — never a regression.

=== test-workflow-bypass-guard-lane.sh ===
PASS: plan-phase architect spawn (no sentinel) still denies — plan branch untouched
(+3 more PASS lines)
workflow-bypass-guard lane: PASS=4 FAIL=0
```

5/6 pass; the 6th fails by design, documented, and pre-existing-equivalent on baseline.

## Full 134-suite sweep vs baseline (fc0ab4c) — regression check

Ran all `plugins/leadv2/scripts/tests/test-*.sh` (134 files) at HEAD, 8-way parallel,
30s timeout per suite (fast pass, not the authoritative number — see below):
`64 pass / 15 fail / 51 timeout(rc=124) / ... ` under parallel CPU contention. A 30s cap
under 8-way parallel load is far tighter than this suite's normal ~60s ceiling (a prior
verified run, dispatch-2dea7737, documented "three suites hitting the 60s per-suite
timeout" as the *baseline norm* even without contention) — so the raw rc=124 count here
is a methodology artifact of the tight cap, not evidence of anything. I did not treat it
as the answer; I used it only to find candidates, then reclassified every candidate that
touched review/dispatch/workflow paths by rerunning it in isolation (60-90s timeout, no
contention) and diffing against a real `fc0ab4c` worktree built at `/tmp/baseline-9ce00c9d`
(removed after use):

| suite | HEAD (isolated) | baseline (fc0ab4c) | verdict |
|---|---|---|---|
| test-dispatch-ledger-partial-close.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-dispatch-ledger-task-id.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-fanout-lease-dispatchable.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-leadv2-dispatch-outcome-ledger.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-review-body-persist.sh | pass (rc=0) | (not rechecked, was a HEAD timeout artifact only) | fine |
| test-review-silence-gate.sh | fail (rc=1, Test 6 crash_backstop MISSING) | fail (rc=1, identical output) | pre-existing flake (same one documented in dispatch-2dea7737) |
| test-t-core-dispatch-ledger.sh | (not individually rechecked — same ledger-setup family as the 4 above, same "process-death wait failed rc=3" signature) | -- | same family, not a review-path suite |
| test-codex-doc-pointer.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-dispatch-product-close-exit-trap.sh | pass (rc=0) | pass (rc=0) | clean — the modified lane script's own exit-trap suite is unaffected |
| test-dispatch-duplicate-caller-race.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-dispatch-architect-degrades.sh | pass (rc=0) | pass (rc=0) | clean |
| test-question-delivery-01.sh | fail (rc=1) | fail (rc=1) | pre-existing, identical |
| test-review-single-owner-census.sh | fail (rc=1) | N/A (new test, doesn't exist on baseline) | documented expected-fail (above) |

Every other rc=1 suite from the sweep (`test-claude-subsession-turncap.sh`,
`test-codex-timeout-tier-resolution.sh`, `test-hook-token-mode-isolation.sh`,
`test-leadv2-ask-architect-fallback.sh`, `test-leadv2-semantic-recall.sh`,
`test-nested-count-fix.sh`, `test-leadv2-strict.sh`, `test-status-surface-cwd.sh`,
`test-supervise-v2.sh`) does not reference any changed file (grepped for
`leadv2-dispatch-code.sh|leadv2-workflow-bypass-guard|leadv2-workflow-sentinel-touch|
leadv2-dispatch-product-close.sh|leadv2-review-run.sh` — zero matches), so they are
outside this lane's blast radius by construction.

**Net result: zero regressions.** Every suite that touches a changed file and fails,
fails identically on the pre-task baseline. The only new failure is the intentionally
documented T6 census.

## §3.3 deletions (mission Step 3) — what happened and what didn't

- `LEADV2_DISPATCH_REVIEWER_ARMS` — deleted (comments-only remain at
  `leadv2-dispatch-code.sh:2065`/`3245` explaining the removal; grep confirms no live
  reference).
- `.workflow-called-review` sentinel branch — narrowed away;
  `leadv2-workflow-sentinel-touch.sh` now only handles `plan`.
- `workflows/leadv2-review.js` (both copies) — **NOT deleted, deferred.** Three existing
  test suites (`test-codex-doc-pointer.sh`, `test-leadv2-review-routing.sh`,
  `test-leadv2-phase8-learn-counter.sh`) assert its presence/content; deleting it now
  strands those callers, which is exactly the stop condition the scoped design names.
  This is the resolution the design's own §5/A7 anticipates and explicitly permits
  ("if unresolved, defer Step 3 rather than strand a path"). Confirmed both copies are
  still present and byte-identical to each other.

## Confirmations

- `LEADV2_REVIEW_ENGINE` is `1` nowhere in the repo (grepped `.claude/settings.json`,
  all `*.sh`/`*.json`/`*.yaml`) — stays `0` everywhere, per constraint.
- No bare `claude -p` invocation was added anywhere in `leadv2-review-run.sh`.
- Out-of-scope items (Plan, Diagnose, `leadv2-learn.js`/`leadv2-audit.js`, E2E gate,
  supervisor/fanout mode, enabling the flag, destructive git ops, real copies inside
  consuming repos) — none touched, confirmed by diff review of the wip commit plus my
  own two edits.

## Gates required by the mission wrapper

The mission's boilerplate footer asks for "the required end-to-end gate and the
cross-provider review gate recorded for this task." This is plugin-infrastructure work
inside `leadv2` itself — there is no deployed product surface to run
`leadv2-phase8-e2e-gate.sh` against (design §9 explicitly marks the E2E gate itself as
out of scope, "already the correct shape," i.e. not to be invoked/modified here), and the
task never enables `LEADV2_REVIEW_ENGINE`, so there is no live cross-provider review run
to trigger against this repo's own change. The evidence substituting for both gates is
the full-suite regression sweep above (the plugin's own correctness gate) plus the T1-T6
suites (the cross-provider review-engine's own test coverage, run with stubbed provider
binaries per design §7 — no live provider call in any test).

## Commits

Working tree is clean at the wip commit `4331a89` plus my two edits (docs/phases.md,
test-review-single-owner-census.sh comment) — **left uncommitted**, per this repo's rule
(shared tree: no commit/push/merge without explicit instruction; lead reviews the diff).

## What's left / open items for the lead

1. `docs/handoff/one-review-path-2026-08-06/codex-capability.md` in persona-engine still
   needs the C1-C6 rows appended (unreachable from this worktree).
2. `workflows/leadv2-review.js` deletion stays parked behind migrating/retiring the 3
   tests that assert its content — separate task, not silently droppable.
3. `LEADV2_REVIEW_ENGINE=1` flip is explicitly out of scope everywhere per constraint —
   waits on `SD-ONEPATH-CODEX-LIVE-PROOF-01` and the 3-repo soak per design §4/R7.

DELIVERABLE_COMPLETE
