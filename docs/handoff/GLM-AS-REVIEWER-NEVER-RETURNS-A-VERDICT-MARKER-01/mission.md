# GLM-AS-REVIEWER-NEVER-RETURNS-A-VERDICT-MARKER-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The measurement

Counted 2026-09-17 across every lane journal in the leadv2 control plane
(`~/.claude/leadv2-state/leadv2/tasks/dispatch-*/journal.md`). GLM was resolved as **reviewer**
three times and produced **zero** verdicts:

| arm | resolutions | verdicts |
|---|---|---|
| **glm** | **3** | **0** — one `review_gate status=arm_refused arm=glm`, two `status=arm_no_verdict arm=glm reason=no_verdict_marker` (lanes `ba9200bd`, `c5db1e4e`) |
| fable | 21 | 23 |
| codex | 7 | 6 |
| sonnet | 5 | 5 |

Every other arm converts close to one-for-one over the same window. **n=3 is small and that is
stated, not hidden** — your first job is to decide whether the effect is real, and the honest
outcome "the sample is too small, here is what a decisive measurement would be" is an acceptable
verdict if you reach it with evidence.

GLM works fine as a **worker** in the same window. So this is specific to the reviewer role — the
likely seam is the verdict-marker contract (`verdict_source=marker`), not capability and not
quota. Do not assume that; establish it.

## Why this is urgent rather than cosmetic

It is tightly coupled to `ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01` (`da0acd521f24`),
which is live right now and whose entire point is to route simple reviews to the **cheapest
capable arm**. If the cheapest arm silently returns nothing, that change does not save anything —
it converts each cheap review into a failed resolution plus an arm advance to a dearer arm, which
is strictly worse than having gone to the dearer arm directly. Measured on lane `9aed148a` this
same day: `arm_advance … from=glm-flash to=sonnet reason=arm_produced_nothing`.

So the arbiter work and this row must agree. Read that lane's report if it has landed.

## What to establish, in order

1. **Reproduce it.** Resolve GLM as a reviewer against a small real diff and capture its raw
   output — not the gate's summary, the arm's own bytes. `arm_no_verdict reason=no_verdict_marker`
   says the gate could not find the marker; it does not say GLM produced nothing. Those are
   different failures and the bytes discriminate them.
2. **Name the mechanism.** If the marker is absent, is it never emitted, emitted in a different
   shape, or emitted and then lost in parsing? If GLM refuses outright (`arm_refused`), what does
   it refuse on?
3. **Fix the narrowest thing that is actually wrong.** If GLM emits a valid verdict in a shape the
   parser does not accept, the parser or the prompt contract is the defect. If GLM genuinely
   cannot hold the reviewer contract, then the correct outcome is **not** a code fix — it is a
   measured statement that the arm is not review-capable, with the evidence, so the arbiter's
   capability matrix can be corrected rather than the parser patched around it.

Both outcomes are legitimate. Choosing the second without the bytes from step 1 is not.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not hardcode GLM out of the reviewer pool. Founder rule, standing: an arm is excluded by the
  capability matrix and quota, never by a hand-kept exclusion list.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `leadv2-active-registry.sh`,
  `leadv2-route-arbiter.sh` or `leadv2-dispatch-product-close.sh` — other lanes hold all four.
  In particular the arbiter file is held by the lane this row is coupled to; if your conclusion
  is "the capability matrix is wrong", write that as a finding, do not edit it here.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. **GLM now returns a parseable verdict** (if that is your fix) → revert the change and confirm
   `no_verdict_marker` returns. If your conclusion is instead that GLM is not review-capable, this
   control is replaced by: the same diff reviewed by a second arm DOES yield a marker, run and
   pasted, so the failure is attributable to the arm and not to the diff or the harness.
2. **The gate still refuses a genuinely empty verdict.** Mutate the marker check inside the
   function body and confirm the suite goes red. A parser that accepts anything is a worse defect
   than the one you are fixing.

Apply each mutation **inside the function body in the lane worktree**, never a scratch copy.
Assert the mutation target string is present before running.

## Deliverable

`docs/handoff/GLM-AS-REVIEWER-NEVER-RETURNS-A-VERDICT-MARKER-01/report.md` — the raw captured arm
output from step 1, the named mechanism, the chosen fix with the rejected alternative, both
controls with pasted output, and the suite that now guards this seam by name with how CI selects
it. If your verdict is "sample too small", state the decisive measurement and how many
resolutions it needs — do not leave the row on a shrug.
