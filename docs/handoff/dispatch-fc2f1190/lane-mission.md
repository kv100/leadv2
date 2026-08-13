# Mission — finish the one review path: the census must reach exactly one owner

## WORKTREE PIN

All edits go in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9ce00c9d`,
branch `worktree-9ce00c9d`, currently at `599275c` (the lane's 1580-line review-engine build, merged
with plugin `main` including the review-pool consumer fix `717b16f`). **Do not** edit
`~/Projects/leadv2` main directly, and **do not** create a real copy of any plugin file inside a
consuming repo. Never `git reset --hard`, `git clean`, or `git stash` anywhere in these trees.

## Where this stands

The review engine is built and green: `test-review-engine-fanout-multiprovider`,
`-pool-degrades`, `-verifier-distinct-arm`, `-verify-coverage`, and
`test-workflow-bypass-guard-lane` all pass, and the three review-pool suites
(`test-review-pool-empty-rootcause`, `-never-empty`, `test-quota-lockout-postspawn`) still pass
after the merge. One suite is red, and it is the one that names the whole point of the task:

```
owners found:
  plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
  plugins/leadv2/scripts/leadv2-review-run.sh
  plugins/leadv2/workflows/leadv2-review.js
FAIL: expected exactly one owner (leadv2-review-run.sh), found 3
```

The previous lane deferred deleting `workflows/leadv2-review.js` because three suites assert its
presence or content: `test-codex-doc-pointer.sh`, `test-leadv2-review-routing.sh`,
`test-leadv2-phase8-learn-counter.sh`. That deferral was correct at the time — stranding callers is
worse than a red census. It is now the only thing left.

## The task

Make `test-review-single-owner-census.sh` pass **honestly**. Exactly one of these is the truth, and
your first job is to determine which — with evidence, not preference:

**(A) The two extra owners are genuinely retired.** `leadv2-review.js` is dead once
`leadv2-review-run.sh` exists, and the review logic still living inside
`leadv2-dispatch-product-close.sh` is superseded. Then: delete `leadv2-review.js` (**both copies** —
confirm they are still byte-identical first), migrate the three asserting suites to assert against
`leadv2-review-run.sh` instead of deleting their coverage, and move `product-close`'s review section
to a call into `leadv2-review-run.sh`.

**(B) `product-close` must keep owning review until `LEADV2_REVIEW_ENGINE` flips**, in which case a
static census over files can never read 1 today, and the *test* is asserting the wrong thing. Then
rewrite it to assert the invariant that is actually true and actually valuable — one reachable owner
**on the path that runs**, parameterised by the flag — so that it is green now, and would go red the
day a second owner reappears.

Do not split the difference by weakening the assertion into something that cannot fail.

## The design is already decided — read it, do not re-derive it

An architect pass already ran on this mission and produced a design at
`/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/dispatch-75d151fe-architect/architect.full.md`.
**Read that file first.** Its conclusion, which you are implementing:

- **(B) for `leadv2-dispatch-product-close.sh`** — a flag-0 lane keeps its inline owner, so a static
  file census cannot legitimately read 1 today. The census becomes a **two-bucket reachability
  census keyed on `LEADV2_REVIEW_ENGINE`**, with a **fail-on-unclassified clause** so a new owner
  that fits neither bucket turns the suite red instead of being silently ignored.
- **(A) for `plugins/leadv2/workflows/leadv2-review.js`** — delete it (three byte-identical copies),
  and **migrate** the three asserting suites' coverage rather than dropping it.
- A **negative control** is prescribed: prove the census goes RED when a second owner is
  reintroduced. A census that cannot fail is worse than none.
- `LEADV2_REVIEW_ENGINE` stays `0`.

## Hard constraints

- **`LEADV2_REVIEW_ENGINE` stays `0` everywhere.** This task does not flip it; that flip is gated on
  `SD-ONEPATH-CODEX-LIVE-PROOF-01` and a 3-repo soak. If your chosen path (A) would silently make
  the new engine the live path while the flag reads 0, that is the wrong path — say so and take (B).
- **The review-pool consumer fix must survive.** `717b16f` made an empty review pool loud
  (populated `tried=` list, `resolver_rc`, `resolver_stderr`, `merge_blocked`, a `review_pool_resolve`
  ledger line, post-spawn quota lockouts). If you move review logic out of `product-close`, that
  behaviour moves with it intact. Its three suites are your proof and must stay green.
- **Author exclusion is non-negotiable** — a reviewer arm may never equal the author arm. It is
  covered by `test-review-pool-never-empty.sh` T7; keep it covered.
- No bare `claude -p` anywhere in the review path.

## Acceptance

- `test-review-single-owner-census.sh` PASSES, and you can state in one sentence what it now
  asserts and how you verified it still goes RED when a second owner is reintroduced. Demonstrate
  that red — a census test that cannot fail is worse than none.
- All nine suites listed above pass in the worktree.
- Full sweep `bash tests/run-all.sh --scope all` shows **no regression against the merge base
  `599275c`** — take the baseline first, in this same worktree, and diff the two result sets.
  A suite that was already failing at the baseline is not your regression; a suite that changes from
  pass to fail is.
- If you take path (A): grep proves zero live references to `leadv2-review.js` remain, and each of
  the three migrated suites still asserts real behaviour rather than having been deleted.
- Report the before/after owner census verbatim.

---

# ROUND 2 — 2026-08-07. Read this section last; it overrides nothing above, it adds.

Round 1 built the change and **failed the e2e gate**: `run-all.sh --scope changed` reported
2 blocking failures, `run-core-offline.sh` and `test-leadv2-route-bandit.sh`.

The lead baselined both on plugin `main` (`717b16f`) before sending this back. The result matters:

- **`test-leadv2-route-bandit.sh` — pre-existing red, NOT yours.** It fails identically on untouched
  `main`: `FAIL: Test 9: rd_exists=1 no_plugin_leak=0; expected file at
  <tmp>/docs/handoff/TEST-SELECT-03/route-decisions.yaml`. Do **not** fix it in this lane and do not
  let it distract you. Re-run it once at your merge base, paste the identical failure into your
  report as proof it is inherited, and move on.
- **`run-core-offline.sh` — this one is yours.** It passes on `main` and fails in your worktree, at
  `[CORE-OFFLINE] FAILED: product-close waits for worker exit`. Your change edits
  `leadv2-dispatch-product-close.sh`, and that is exactly the behaviour the test names. The other 42
  checks in that suite pass, so the break is narrow — find it, do not paper over it.

Fix the regression, keep every one of the nine suites from round 1 green, and re-run the gate.
The census work itself was accepted in shape — the design decision, the two-bucket reachability
census keyed on `LEADV2_REVIEW_ENGINE` with a fail-on-unclassified clause, and the negative control
proving it goes RED — all still stand exactly as written above.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-fc2f1190" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.