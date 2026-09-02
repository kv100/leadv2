# CACHE-TRUTH-01 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-cache-truth.sh,plugins/leadv2/scripts/tests/test-cache-truth.sh,tests/run-all.sh,docs/handoff/CACHE-TRUTH-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Never commit anything under
`docs/leadv2/`, `docs/LEAD_V2_STATE.md` or `docs/handoff/dispatch-nw*` (lead-owned runtime files the
suites dirty) — `git checkout -- docs/leadv2 docs/LEAD_V2_STATE.md docs/handoff/dispatch-nw*` before every
commit and commit by explicit LANE_WRITES pathspecs. An uncommitted exit is a failed round.

## Review verdict on round 2 (reviewer opus, `review-opus.md`) — FAIL, high=3
1. `leadv2-cache-truth.sh:178` — zero denominator prints a fabricated `hit_ratio 0.0000` instead of
   `unreported`, violating the tool's own missing-is-not-zero rule. Reviewer's probe: one reported turn
   with all-zero usage → `unknown tmp 1 0 0 0 0.0000 none 1/1` rc=0.
2. `test-cache-truth.sh:236` — mutation controls 2 and 3 print "control proven red-capable" when their
   python assert fires and the mutant was never created. Reviewer's probe: perturbed anchor → `turns=''`
   → suite still PASS=16 FAIL=0. The controls are theatre.
3. The diff carried lead-owned runtime files (LEAD_V2_STATE.md, phases.d yamls, task journals, 8 live
   active-session rows). The lead restored them from main; the rule above prevents a repeat.

## Do
1. Denominator rule: `hit_ratio` is printed ONLY when `reported_requests > 0` AND
   `cache_read + cache_creation + input > 0` over the reported set; otherwise the cell is `unreported`.
   A request whose usage is all zeros is NOT "reported" — it is `unreported` (the api/anthropic GLM path
   returns `input_tokens:0/output_tokens:0` on every event; see
   `docs/handoff/GLM-EFFICIENCY-AUDIT-01/report.md` §2). Add the reviewer's exact probe as a suite
   case (expected: `unreported`, `reported=0/1`).
2. Mutation controls must FAIL LOUD when the mutant cannot be applied: the anchor substitution must
   verify the anchor exists (`grep -c` == 1) before running, and `turns=''` / an empty mutant must exit
   non-zero with `control_not_applied`. Re-run controls 1–3 and paste each one's RED output (the actual
   failing assertion line), then the green after revert.
3. Re-run the tool over today's runs (`~/.claude/cache/glm-runs/260902-*`, freepool/kimi/claude runs of
   the same day) and replace the table in report.md; per-arm conclusion again from the new numbers. For
   GLM state explicitly: "cache unmeasurable on api/anthropic (usage zeros) — dashboard only".
4. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-cache-truth.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
5. "## Round 3 evidence" in report.md; commit (pathspecs only).
