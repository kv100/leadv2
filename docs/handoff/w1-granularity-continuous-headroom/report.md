# Report — W1-GRANULARITY-CONTINUOUS-HEADROOM-01 (§1.6)

Lane `84d8f25ae5eb` · commit `80b2b73f` · branch `worktree-84d8f25ae5eb` · 2026-09-10

**Who wrote this report:** the lead. Disclosed up front because it matters for how the evidence
below should be read. The worker committed the code and then died before writing anything —
`ps` showed the `claude -p` process gone at ~00:13Z with the tree clean, one work commit, and
`docs/handoff/w1-granularity-continuous-headroom/` holding only `brief.md`. No worker report, no
worker-produced mutation artifact. **Every run below was executed by the lead on the real file in
the lane's own checkout, not copied from a worker claim.** The pulse had already disagreed with
`ps` twice about this lane's liveness, so liveness here was decided by process, not by the pulse.

## What changed

| file | change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` | `headroom_weight()` now calls `_headroom_ramp(un)` — one continuous monotone ramp — in place of the four-row step table; `_hw_row` gone |
| `plugins/leadv2/config/leadv2-routing.yaml` | `headroom_weights` key **deleted** (no dead key left behind) |
| `plugins/leadv2/scripts/tests/test-headroom-continuous.sh` | new suite, 9 assertions |
| `plugins/leadv2/scripts/tests/test-route-arbiter.sh` | 8 lines adjusted for the removed table |

281 insertions, 45 deletions across 4 files.

The change **removes** machinery rather than adding it, which was the point of the brief:
`usable_now = remaining_pct / hours_to_reset` was already continuous and `ecost = cost / weight`
already multiplied — the bucket table sat between them discarding information that had already
been computed.

## Green run — lead, real file, 2026-09-10

```
PASS: separation: u=0.5 -> 0.25, u=1.5 -> 0.35 (one basket before, two prices now)
PASS: separation (brief's pair): u=0.5 -> 0.25, u=7.0 -> 0.9
PASS: monotonicity: 15-point ordered sample matches the ramp, never decreases, strictly increasing below saturation
PASS: edge u>=8: weight exactly 1.0 (no token) and codex wins unscaled
PASS: edge u>=20: weight exactly 1.0 (no token) and codex wins unscaled
PASS: edge no-data (unmetered): sonnet priced at the 0.2 floor (codex ~10.7 beat it), hand named, not in headroom_priced
PASS: discrete refusal: codex over work ceiling excluded by the same cliff (arm_excluded=codex:capped)
PASS: discrete refusal: all measured providers capped -> arm=refuse reason=all_arms_capped
PASS: config: headroom_weights key deleted (grep -c = 0), no dead key left in the live config
SUMMARY: 9 passed, 0 failed
```

## Negative control — lead, mutation inserted INSIDE the function body

Mutation: `_w=_headroom_ramp(un)` replaced, **inside `headroom_weight()`**, by the old step table
expressed literally —
`_w=(1.0 if un>=8 else (0.7 if un>=2 else (0.4 if un>=0 else 0.2)))`.
Line 1490 of the real file, not a copy. Verdict: **`SUMMARY: 6 passed, 3 failed`**.

The three deaths are exactly the three claims the brief demanded, and they are specific, not
incidental:

```
FAIL: separation: t05=0.4 t15=0.4 (expected 0.25 / 0.35)
FAIL: separation 0.5-vs-7.0: t05=0.4 t70=0.7 (expected 0.9)
FAIL: monotonicity: formula-mismatch at 0->0.4(!=0.2),0.5->0.4(!=0.25),1->0.4(!=0.3),
      1.5->0.4(!=0.35),2->0.7(!=0.4),...,7.5->0.7(!=0.95); flat stretch below saturation
```

The mutated sweep prints the defect in one line — `0 0.4; 0.5 0.4; 1 0.4; 1.5 0.4; 2 0.7; … 7.5 0.7`
— four distinct headroom states collapsed onto `0.4` and six more onto `0.7`. That is the original
complaint reproduced on demand.

Note what did **not** move under the mutation: the two discrete-refusal assertions and both edge
assertions stayed green. That is the correct shape — the mutation is a *ranking* mutation, and the
refusal path is meant to be independent of it.

The file was restored from `/tmp/arb.orig` after each run and `git status --porcelain` returned
**0 lines** both times; the run above was executed twice (once for the summary, once to capture
the FAIL lines) with a clean restore in between.

## The boundary the brief made half the assignment

Continuous only where the output is a **ranking**. Verified, not asserted: the ceilings still
refuse discretely and loudly — `arm_excluded=codex:capped` for one provider over its work ceiling,
and `arm=refuse reason=all_arms_capped` when every measured provider is over. Neither became a
probability. A human can still predict a refusal without running the arbiter.

## What this lane deliberately did NOT do

The thinking path was left alone, per the brief. The equivalence sample stands at glm/fable
agreeing on **6 of 11 (55%)**, so the arms are not interchangeable yet; the order is journal
(`think_model_resolved`, landed `5041256c`) → measure agreement per role → only then differentiate.
Adding granularity there now would be guessing dressed as intelligence.

## Live evidence that motivated the row, kept for the record

Arbiter line, 2026-09-10, before the change: `util_glm=19 util_codex=38 util_claude=62` →
`headroom_priced=claude:0.4,codex:0.4,glm:0.4`. Three providers with visibly different headroom,
one price. After the change the same spread separates.
