verdict: APPROVE
next_action: review_round_2

# dispatch-dacaf22f — ARM-SELECTION-COST-QUOTA-TELEMETRY-01

Lane: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` only, per
`docs/reference/arm-selection-proposal-2026-09-16.md` §4.2-§4.4 and §5. Full
detail, reasoning, and raw test output: `docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md`.

## What changed (4 bounded edits, one file)

1. **§4.2 cost provenance** — `router_v2.cost` entries may be a bare number
   (legacy) or `{value, source, observed_at, sample_count, confidence}`.
   Key resolution: `provider.model.effort` → `provider.model` → provider
   (dot-joined — the stdlib YAML-subset loader's key regex refuses colons,
   caught while writing this lane's own fixtures). Null stays visibly
   unknown (`cost_src` ends `:median`/`:unpriced_all`, never disguised as
   `:measured`). `_observed_rounds` untouched, no second multiplier. NNLS
   not re-run (forbidden).
2. **§4.3 quota** — `windows.pop('seven_day', None)` deleted from the
   scoped-Claude branch of `util()`. A Claude arm's scoped weekly window no
   longer replaces the account's general weekly aggregate; both now bind
   (worst-of-readable, never summed). This directly contradicted the 0485
   lane's own deliberate, mutation-tested design — escalated via
   `leadv2-ask.sh` (qid=`q-d19ae6cb`) rather than decided unilaterally;
   timed out and was architect-adjudicated to option (b), keep both,
   overriding my declared default. Implemented per that resolution.
3. **§4.4 rotation** — anti-stickiness's equal-ecost alternative pool is now
   constrained to the winner's own fit bucket when `FIT_MODE=on`; verified
   reproducible first (a real fixture where the old code rotates to a
   strictly worse fit), then fixed. `FIT_MODE=off`/`shadow` unchanged.
4. **§5 telemetry** — `arm_excluded`/`price_ratio` is untouched, byte-for-
   byte (two suites outside this lane's write set assert its exact string).
   A new, purely additive stdout token, `loser_detail=<arm>:<reason>,...`
   (`insufficient_fit` / `cost_unknown` / `higher_expected_cost` — spelled
   verbatim from the proposal's §5 vocabulary), rides alongside it. Not
   written to the JSON decision record. Migration-safe: absent from any
   older journal line, and its absence changes nothing about how
   `price_ratio` is read.

## Baseline reconciliation

Against `test-arm-selection-decision-fixtures-01.sh`'s frozen baseline:
exactly two decisions changed, both intended —

- **Case 5**: rotation now keeps the better-fit arm instead of demoting to
  the worse one (§4.4 fix).
- **Case 10**: two sub-flips, both from the §4.3 fix — (a) `fable` is now
  correctly refused when general weekly is exhausted even though its own
  scoped window is free (previously silently admitted — a documented
  `BASELINE FINDING` before this fix); (b) the stale-scoped sub-case now
  legitimately shows `reset_urgency` for `claude/fable`, proven (via the
  `[seven_day]` provenance tag) to come from the now-un-popped, genuinely
  valid general weekly window — not the deliberately-stale scoped one,
  which still contributes nothing to urgency. This is the fix working as
  intended; the sibling suite's stale-check assumed the old (popped)
  semantics and needs re-anchoring by whoever owns that suite next (outside
  this lane's write set) — flagged, not silenced.

Every other case (1,2,3,4,6,7,8,9,11,12,13) is decision-identical; the only
per-line diffs anywhere are `arb_rev` (a content hash of the edited file —
necessarily different) and the new additive `loser_detail=` token. The
suite's own negative control (byte-exact restore-after-mutation check)
fails for the same two structural reasons — an unavoidable consequence of
editing this file at all, not further drift.

## Guarding suites

Ran every suite whose name mentions arbiter/routing/quota/headroom/reset-
urgency/balancer — full raw output and per-suite pass/fail counts in
`docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md`. Highlights:

- `test-arbiter-seam-plugin-kind.sh`, `test-arbiter-uses-observed-cost.sh`,
  `test-quota-reset-arbiter.sh` — pre-existing red, named in the mission as
  such.
- `test-exclusion-stages.sh` — also pre-existing red; **independently
  verified** by swapping in the pristine pre-this-lane arbiter file
  (`git show HEAD:...`) and re-running: identical failure. Its `_STAGE_ORDER`
  anchor string predates this lane (missing `caller_constraint`/`forecast`).
- 8 more suites (`test-route-arbiter.sh`, `test-complexity-routing.sh`,
  `test-balancer-every-arm.sh`, `test-spawn-arbiter-gate.sh`,
  `test-think-through-arbiter.sh`, `test-route-arbiter-spend-forecast.sh`,
  `test-quota-daemon.sh`, `test-codex-quota-guardrails.sh`) — swap-tested
  the same way; pass/fail counts identical pre/post this lane's edit.
- `test-fable-is-priced-from-its-own-window.sh` — **1 new, expected** red
  (`C1`): that suite is the 0485 lane's own, asserting the exact
  replace-semantics this lane's §4.3 fix (per the architect-adjudicated
  answer) deliberately overturns. `C2`/`C3`/`C4` remain green. Flagged as a
  named follow-up for whoever owns that suite next.
- `test-arbiter-decision-record-inputs.sh`: 6/6 green (unaffected by the
  §5 redesign — confirmed the loser-labeling loop is byte-identical to
  before).
- This lane's own new suite,
  `test-arm-selection-cost-quota-telemetry-01.sh`: 14/14 green, covering
  all 4 changes plus controls.
- One race caught and discarded: an early sweep ran two copies of the same
  suite-runner concurrently against one shared log directory, producing one
  transient, self-contradicting read (`fail=1` in a tail, `fail=0` moments
  later reading the same file directly) — not a real result; every number
  in the report comes from an exclusive run.

## Static checks

`bash -n` on the arbiter and the new test file: OK. The embedded Python
heredoc (~2346 lines) compiles cleanly (`compile(..., "exec")`). All
touched/added files pass.

## Write set (unchanged, as specified)

- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`
- `plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh` (new)
- `docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md` (new)

## Round 2 (2026-09-16) — Fable ruling + baseline re-freeze

Lead's round-2 brief resolved the lane's own `q-d19ae6cb` decision conflict:
founder ruled **keep both Fable windows** (round 1's §4.3 fix stands,
`seven_day` stays un-popped) and ordered the 0485-era
`test-fable-is-priced-from-its-own-window.sh` rewritten to assert the new
rule instead of reverted against it.

- Arbiter code (`leadv2-route-arbiter.sh`) is **untouched this round** — the
  founder ruling confirmed round 1's fix as correct, so there was nothing to
  fix in code.
- Rewrote `test-fable-is-priced-from-its-own-window.sh` in place (same path,
  CI suite-selection keys on it) with a header naming decision 0485, the
  founder ruling, and its date. Added the mirror case (scoped exhausted /
  account weekly healthy also caps) so a replace-shaped regression can't
  sneak back in from either direction. 12/12 green (was 10/10 pre-round-2,
  1 red mid-round after the code fix and before the suite rewrite).
- Re-froze `ARM-SELECTION-DECISION-FIXTURES-01/baseline/` from the
  post-round-1 tree. Reconciled every changed field in
  `docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md` §2: only
  `arb_rev` and `loser_detail` plus the case05/case10 decisions already
  explained in round 1. Negative control (mutate → decision moves → revert →
  byte-identical restore) re-verified: `test-arm-selection-decision-fixtures-01.sh`
  44/44 green.
- Paired all three suites against main (report.md §3):
  `test-arm-selection-decision-fixtures-01.sh` rc=0/rc=0,
  `test-fable-is-priced-from-its-own-window.sh` rc=0/rc=0,
  `test-arbiter-reads-capability-floor.sh` rc=1/rc=1 (still red in both
  columns, confirmed untouched by this lane).
- Post-commit mutation-control evidence (`leadv2-mutation-control.sh`
  artifacts under `mutation-control/`, committed) appended to report.md §8
  after the round-2 commit (`8b271082`) so `lane_diff_hash` binds the actual
  committed HEAD — this final commit (`b6654d69`) is that append, done by
  this session on resume.

Verification re-run this session (raw, foreground):
```
$ bash plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
SUMMARY pass=44 fail=0 (rc=0)
$ bash plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh
SUMMARY: pass=12 fail=0 (rc=0)
$ bash plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh
SUMMARY pass=14 fail=0 (rc=0)
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh && echo OK
OK
```

Write set this round: `test-fable-is-priced-from-its-own-window.sh`,
`ARM-SELECTION-DECISION-FIXTURES-01/baseline/*`, `report.md`. No arbiter
code change. `docs/leadv2/.compact-freeze.md` and the untracked
anti-silence-pulse heartbeat/stderr files present in the worktree on resume
are background-process artifacts, outside this task's write set — left
untouched, not committed.

Committed on the lane branch before ending this session
(`8b271082`, `b6654d69`).

DELIVERABLE_COMPLETE
