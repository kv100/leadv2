verdict: APPROVE
next_action: review_round_2

# CODEX-HAS-TOKENS-BUT-NO-DRAIN-SERIES-01 — developer full report

Full evidence, run output, and reasoning: `docs/handoff/dispatch-c8711201/report.md`
(same directory). This file gives the condensed narrative + pointers required
by the subagent deliverable contract.

## What was built

1. **`plugins/leadv2/scripts/leadv2-codex-drain-fit.py`** — new tool. Collects
   `util_codex` readings from every task's `journal.md` (backfill from
   existing decision lines, no new sampler — see report §1 for why forward-only
   was rejected), discovers codex spawns from `arm-registered` ground truth
   (never a `route_resolved` decision line — that proxy has a measured 0%
   reliability, see report §1 "Errors avoided"), attributes tokens via the
   SAME `leadv2_lane_token_total` the observed-cost loop uses (shelled to, not
   reimplemented), and attributes per-model identity via each job's own
   `request.model` record — explicitly excluding `gpt-6-astra` (the dispatch
   launcher's own default alias, confirmed live at
   `leadv2-routing.yaml:497,592`, not a fourth model per the mission's
   explicit instruction). Reset-spanning intervals (Δpct<0) are dropped via
   logic imported directly (`importlib.util`) from `leadv2-drain-weights.py`
   — never reinvented, per the mission's binding instruction.

2. **`plugins/leadv2/scripts/tests/test-codex-drain-fit.sh`** — new suite, 13
   assertions covering the static checks, the reset/idle drop counts, the
   resolved/unresolved-token counts, the astra-alias exclusion (the single
   most important behavioral guard — a regression here would silently invent
   a 4th "model" and be exactly the defect this lane exists to prevent), the
   NOT-ENOUGH-DATA gate, and the evidence-quadruple format on the aggregate
   fit line. Self-registered via
   `# run-all-triggers: leadv2-codex-drain-fit leadv2-codex-drain-fit.py leadv2-drain-weights leadv2-drain-weights.py leadv2-cost-actuals`.

3. **`plugins/leadv2/config/leadv2-routing.yaml`** — comment-only edit on the
   `cost.codex: null` line, replacing the dead `dispatch-f8880421` pointer
   with this lane's evidence and its R² (-0.3974, negative → stays null per
   the binding rule). No numeric value changed.

## Results (see report.md for full run output)

- **Codex drain series**: 332 readings, 331 raw intervals, 2 dropped as
  reset-spanning, 215 dropped as idle, 114 kept.
- **Aggregate fit**: R²=-0.3974, max_abs_corr=0.000, degenerate_pairs=0,
  kept=114 → **codex stays unpriced (`null`)**, correctly, not a guess.
- **Per-model fit** (terra, luna; sol has zero data in this window — named
  explicitly, not silently dropped): R²=0.1456, max_abs_corr=0.402,
  degenerate_pairs=0, kept=61. Not collinear the way Anthropic's four tiers
  are (0.402 vs 0.913-0.934) — a materially different, better-conditioned
  situation, though still a weak fit (15% variance explained).
- **Terra question**: terra's own weight is +0.0703 Δpct per 1M tokens
  (near-zero, directionally "almost free"). A validated comparison against
  sonnet/glm is **not possible** — the sibling per-model fit that would
  produce those numbers is R²-negative in both the 5h (-0.2975) and 7d
  (-0.5817) windows, with max_abs_corr 0.913-0.934, the identical collinearity
  defect already on record for Anthropic pricing. Sonnet's own number is not
  even stable between windows (19.4 vs 0.0 per 1M). Answered per the mission's
  fallback form: a number for terra, plus an evidenced "cannot be separated
  [from sonnet/glm], because their own fit has no valid R² either."
- **Published relative weight for codex tiers**: searched first, per the
  sibling lane's amendment, before trusting the fit. None found reliably —
  `model-capability.yaml` has no codex-volume/luna entry or numeric ratio;
  OpenAI's own help page 403'd on fetch; the one third-party page found gave
  two internally-inconsistent number sets between the search snippet and a
  direct fetch of the same URL. Tagged UNVERIFIED and not used; the empirical
  fit stands as the only evidence.

## Falsification set (bash -n / py_compile / changed-scope runner)

Red state (the exact broken point this session resumed from — `main()` still
called the removed `_codex_models_for_task` and unpacked
`_scan_codex_spawns()`'s new list-shaped return as a scalar):
```
$ python3 plugins/leadv2/scripts/leadv2-codex-drain-fit.py
NameError: name '_codex_models_for_task' is not defined
```
Green state after the fix (`main()` now consumes
`{(root, sig8): [(epoch, handle), ...]}` and calls `_job_model(handle)` per
handle) and the follow-on `gpt-6-astra` exclusion fix:
```
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-codex-drain-fit.py
COMPILE_OK
$ python3 plugins/leadv2/scripts/leadv2-codex-drain-fit.py
provider=codex kept=114 threshold=12 dropped_reset=2 dropped_idle=215 codex_tasks_resolved=118 codex_tasks_unresolved_token=123 codex_tasks_mixed_model=1 codex_tasks_no_job_model=36 readings=332 r2=-0.3974 max_abs_corr=0.000 degenerate_pairs=0 weights=codex_total=0.00000004
provider=codex per_model kept=61 r2=0.1456 max_abs_corr=0.402 degenerate_pairs=0 weights=gpt-5.6-luna=0.00000000,gpt-5.6-terra=0.00000007
```
New suite green (13/13, see report.md for the full transcript). All six
mission-mandated suites (`test-codex-lane-token-total.sh`,
`test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
`test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
`test-leadv2-task-judge.sh`) run and green — full output in report.md.

`tests/run-all.sh --scope changed` surfaced 10 NOT-KNOWN-RED failures in
suites unrelated to this diff's scope (capability-floor, think-through-arbiter,
route-arbiter, arm-pool-reachability, capability-fit, codex-tiers-selectable,
plugin-papercuts, exclusion-stages, effort-routing, failure-memory). Verified
pre-existing by reverting this diff's only routing.yaml edit and re-running
two of them directly against bare HEAD — identical failures. Not fixed (out
of this lane's scope; none relate to codex drain/token fitting).

## Off-limits respected

`~/.claude/burn/history.db` untouched; no codex price written beyond what the
fit supports (`cost.codex` still `null`); `reset_urgency`, the decision
record schema, the launcher-refusal event, and the judge parser untouched;
`docs/tasks.yaml` and `docs/leadv2/open-threads.md` untouched.

## Commit

All work (the new tool, the new test suite, the routing.yaml comment, this
report and its summary) committed on the lane branch
(`worktree-c953a84e0725`) before ending this session.

DELIVERABLE_COMPLETE
