# Architect decision — GLM-EFFICIENCY-01 item 3 (routing), timed-out ask

DECISION_OPTION: b
RATIONALE: Flash-preferred policy is confirmed correct by the live probe; the only real defect is stale cost data (0.4 vs true 0.33), a one-line data-only fix in the file the routing item is about — extending LANE_WRITES to it is lower total risk than institutionalizing known drift (a) and vastly cheaper than the arbiter rewrite option (c) that the probe's evidence makes unnecessary.

## Analysis

### The probe inverts the brief's premise — brief item 3 is stale, not the policy

Live probe of Z.AI teamplan pricing (worker's artifact, cited in the question): glm-5.3 input 6.9 / output 24; glm-5.3-flash input 2.3 / output 8 credit-multiplier weight. Flash = 1/3 the weight of glm-5.3, i.e. "3x quota" means 3x MORE allowance. Under credit-weight semantics, flash IS the cheap arm.

This matches the in-tree policy: `plugins/leadv2/config/leadv2-routing.yaml:72` declares `arm: glm-flash ... cost: 0.4` preferred through `sizes: [standard]`, and the fallback leg at `:245` has `when: [trivial, light, standard]` — flash is already preferred on trivial/light/standard, exactly what GLM-53-FLASH-ARM-01 (founder order 2026-08-26, quoted in the file comment at :61-63) mandated. Verified this session by grep of the live worktree file.

Therefore option (c) — following the brief literally — would be acting on a refuted premise AND would require a SIZE_MAP arbiter change (trivial/light fold into the same "standard" cell as standard, so sizes-list edits alone cannot split them). Evidence says the current behavior is right; changing the arbiter to make it worse is ruled out.

### Why b over a

- The 0.4 figure is now confirmed stale on its own terms: the file comment (:62-63) justifies `cost: 0.4` from the LEGACY coding plan prompt-weight ratio. The account has since moved to teamplan weighting where the true ratio is 2.3/6.9 ≈ 0.33 input, 8/24 ≈ 0.33 output. The comment and the number are both wrong against the current plan.
- Option (a) documents the drift as "known" — but this lane IS GLM-EFFICIENCY-01, and the drift is exactly a GLM-efficiency datum. Leaving the wrong number in the arbiter's only economic unit while the lane's deliverable says "known drift" is self-defeating scope hygiene.
- The fix is data-only: `cost: 0.4` → `cost: 0.33` on line 72 plus rewriting the :61-63 comment to cite the teamplan multipliers. Zero behavior change — the arbiter uses cost as a relative preference weight among uncapped arms, and 0.33 vs 0.4 only nudges the score, never flips a cell (glm-flash remains the cheapest capable arm by a wide margin vs freepool=1, codex=3-7, sonnet=5).
- LANE_WRITES extension is a lead action (edit active.yaml / lane config), one line; ask-lead round-trip already paid by this escalation.

### Implementation notes for the (re)dispatched worker

1. LEAD_ACTION: extend LANE_WRITES for this lane to include `plugins/leadv2/config/leadv2-routing.yaml` (data-only authorization — do not authorize arbiter/SIZE_MAP edits under it).
2. Edit `plugins/leadv2/config/leadv2-routing.yaml:72`: `cost: 0.4` → `cost: 0.33`.
3. Rewrite the comment block at :61-63: replace legacy-plan ratio justification with teamplan weights (glm-5.3: 6.9 in / 24 out; glm-5.3-flash: 2.3 in / 8 out ⇒ ≈0.33 both directions) and keep the GLM-53-FLASH-ARM-01 founder-order citation.
4. Re-run whatever routing-config validation the lane's test suite already covers (test-glm-effort-wiring.sh is already in the lane's tree; no new test needed for a constant change — MINIMALISM).
5. Model-capability.yaml + docs refresh proceeds as planned under the original item 3, unaffected.

### Risks

- **Race surface:** leadv2-routing.yaml is a hot file (dispatch config). Concurrency risk is the standard one: re-diff immediately before `git add` (global rule; parallel sessions in this worktree family). Data-only single-token edit minimizes the window.
- **Semantics drift:** if Z.AI reprices again, 0.33 goes stale the same way 0.4 did. Mitigation: the rewritten comment cites the probe date and source page so the next auditor can re-verify in one probe. (Probe artifact for the multipliers is the worker's live teamplan-page capture, referenced in the question; not re-probed by me — cited, not independently confirmed.)
- **Auction sensitivity:** cost is used only as a relative preference weight (per :64-66 comment); no threshold in the file sits between 0.33 and 0.4, so no cell flips. Verified by inspection of the cited lines only.

### Out of scope (implementing agent must NOT do)

- Any change to arbiter SIZE_MAP or raw-size awareness (option c machinery).
- Re-routing heavy/bulk away from glm-5.3 or any tier reassignment.
- Changes to `when: [trivial, light, standard]` on the glm-flash fallback leg (:245).
- Model-capability.yaml schema changes beyond the cost/effort data refresh already in this lane's plan.

Self-check: option label verbatim from the offered list; routing-yaml path and line contents existence-verified this session (grep output above); no env vars introduced (checklist #1/#5 n/a); deliverable paths exist (binding-specified handoff dir, verified by ls).


DELIVERABLE_COMPLETE
# auto-marker added by SOFT_FINISH fallback
