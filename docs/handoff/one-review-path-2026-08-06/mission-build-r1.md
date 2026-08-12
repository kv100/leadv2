# ONE-PATH-EVERYWHERE-01 — build the review engine (step 1 of the consolidation)

**Read `docs/handoff/one-review-path-2026-08-06/design.md` in full before writing anything.** It is
the approved design; this mission is its execution order, not a re-litigation. In particular §3
(target design), §4 (blast radius / migration order), §5 (test strategy) and the FOUNDER
CONSTRAINTS section at the end are binding.

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` — this is the single source. The founder
ordered this work explicitly, so editing the plugin repo is authorized for this task. **Never
create a real copy of a plugin-owned file inside a consuming project** (persona-engine, m3-market,
respiro-ios); those are per-file symlinks and a copy silently drifts.

## Step 0 — capability evidence. **Do NOT block on this** (revised 2026-08-06, round 2).

A first attempt at this mission correctly returned BLOCKED here: Codex's quota is exhausted until
2026-08-08 08:48, so the live probe could not run. That stop condition is now lifted, because the
live proof has its own ledger row — `SD-ONEPATH-CODEX-LIVE-PROOF-01`, due 2026-08-08 — and nothing
gets enabled until that row closes (`LEADV2_REVIEW_ENGINE` stays 0 everywhere).

So: gather what you can **statically**, record it, and move on to Step 1.

Read `leadv2-codex-session-runner.sh`, its tool grants, its sandbox/permission config, and any
existing codex session transcripts on disk, and answer with file:line evidence:

- Can a Codex-led session invoke a plain `bash` script from the plugin's `scripts/` directory?
- Does it have the Agent tool? The Workflow tool? In-session MCP?
- What is its working directory and its write scope under `docs/handoff/<task>/`?

Append to the existing `docs/handoff/one-review-path-2026-08-06/codex-capability.md`, and mark each
row **STATIC** or **LIVE-VERIFIED** so a later reader cannot mistake one for the other.

**If the static evidence positively shows a plain bash script is NOT invocable under a Codex lead,
then stop and return BLOCKED** — that would falsify the design and the founder needs to know before
code is written. Quota being unavailable is NOT such a finding; it is an absence of evidence, and
the ledger row covers it.

## Step 1 — build the engine

`plugins/leadv2/scripts/leadv2-review-run.sh`, per design §3.1: arm-pool resolution lifted verbatim
from `resolve_review_pool_call()`, N-arm multi-provider fan-out (`LEADV2_REVIEW_FANOUT`, default 3),
the always-on cheap hack-detect pass, per-finding refutation on a DIFFERENT arm than the one that
raised it, and synthesis writing both `review-gate.md` (existing contract + additive `arms:` /
`verified:` lines) and the new `review-findings.json`.

Keep: `lib/leadv2-glm-policy-resolve.py`, `lib/leadv2-review-signals.sh`, author-exclusion, and the
quota bands exactly as they are (GLM 90, Codex 90/95, Claude 95). Do not hardcode an arm in or out
of the pool — quota, task and complexity decide, never a hand-kept list.

## Step 2 — converge both entry points

- Lane: replace the `leadv2-dispatch-product-close.sh:1447-1667` body with one call to the engine.
  The lane keeps its process model, EXIT trap, `_stamp_review_terminal`, and `review_crashed`
  fallback.
- Lead/interactive: the review phase calls the engine over Bash; rewrite
  `skills/leadv2-review/SKILL.md` and `WORKFLOW-PATH.md` to point at it.
- Repoint `hooks/leadv2-workflow-bypass-guard.sh`: predicate changes from "was the Workflow tool
  called" to "does `docs/handoff/<task>/review-gate.md` exist with a parsed `REVIEW_VERDICT:`", and
  the match widens from `subagent_type` to also cover Bash invocations of the dispatch scripts.

## Step 3 — delete the duplicates (design §3.3), in the order given there

Both copies of `workflows/leadv2-review.js` (plugin **and** `~/.claude/workflows/`) — deleting one
leaves the other live. Plus the sentinel branch, the `.workflow-called-review` sentinel, and the
already-dead `LEADV2_DISPATCH_REVIEWER_ARMS`.

## Scope fence

**Review only.** Do NOT touch Plan (§3.4) or Diagnose — they are sequenced after review proves out
in all three repos. Do not start them even if they look easy.

## Rollout

Behind `LEADV2_REVIEW_ENGINE`, default **0** (off). Do not enable it anywhere in this task. The
rollout order is persona-engine → respiro-ios → m3-market, and m3-market has Codex disabled, so the
arm pool must **degrade** there, never fail closed — cover that with a test.

## Tests (design §5)

Every fix carries a test that FAILS against the pre-fix code. At minimum: the bypass guard sees a
lane review (fails today — the lane is invisible to it); the fan-out is genuinely multi-provider,
not three Claudes; a verifier never runs on the arm that raised the finding; the pool degrades when
Codex is unavailable. Run the full suite and report the actual output, not a claim.

## Constraints

- Shared tree: never `git reset --hard`, `git clean`, or `git stash`.
- Commit incrementally with a clear message per step.
- If Step 0 blocks, stop there — do not build against an unverified premise.

## Return

`PASS|FAIL|BLOCKED` + commit shas + the Step-0 capability findings with their evidence + the full
test run + which parts of §3.3 were deleted + confirmation that `LEADV2_REVIEW_ENGINE` is still 0
everywhere.
