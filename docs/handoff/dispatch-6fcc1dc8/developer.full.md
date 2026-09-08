verdict: APPROVE
next_action: review_round_2

# ARBITER-SCORING-DESIGN-01 — Step 1 (of §8's 4-step rollout)

Worktree: `.claude/worktrees/F1-ARBITER-SCORING-20260907-step1`
Design doc: `docs/handoff/F1-ARBITER-SCORING-20260907/design.md` (persona-engine, commits `f88e15c3c`/`e678b4eb2`)

## Scope delivered

1. **`plugins/leadv2/config/leadv2-routing.yaml`**
   - Added `router_v2.capability_fit` block verbatim per §7.4's schema, `enabled: false`, `source_confidence.heuristic: 0.4` (Leadmain's §12 OQ1 decision).
   - Added `capability:` (1-4) to every one of the 10 `capability_matrix` cells, per §4.1's exact assignment (glm-flash=2, glm=4, freepool=2, codex/volume=3, codex/standard=4, codex/top=4, haiku=2, sonnet=4, fable=4, opus=4).
   - Rewrote the stale comment citing a dead `leadv2-route-arbiter.sh:79` reference (R5) — corrected to `:219`, plus a new paragraph on the `capability_fit` relationship, citing the design doc path and both commits.
   - Landed in the same commit as the arbiter change (see below).

2. **`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`**
   - Ported §6's decision function verbatim (own variable names: `FIT_MODE`, `CX_ORD`, `SRC_CONF`, `PRIOR`, `SLACK`, `CAP_DEFAULT`, `cx`, `conf`, `req_eff`, `cap()`, `fit_bucket()`).
   - `FIT_MODE` resolves from `LEADV2_ARBITER_CAPABILITY_FIT` else yaml's `capability_fit.enabled` (default off — nothing flipped `on` in this step).
   - `_cost_order`/`_fit_order`/`fit_differs` are **always** computed, in every mode; only which key sorts `ok` depends on `FIT_MODE`.
   - `_fit_tok` appends `complexity_source= conf= req_eff= fit_mode= fit_pick= fit_differs= fit_bucket=[ cap_default=][ complexity_unmapped=]` to every decision line.
   - **Finding fixed, not silently ported**: design.md §6's literal pseudocode (line 243) computes `fit_differs` by comparing only `c['arm']`. `capability_matrix` gives `codex` three cells (volume/standard/top) sharing one arm name — and §9.2's own table (rows "codex/vol (glm capped) → codex/std" and "haiku (glm capped) → codex/vol or codex/std") requires exactly that within-arm tier swap to register as `fit_differs=1`. An arm-only compare silently produces `fit_differs=0` for both rows (reproduced and confirmed red before the fix — see "Finding" below). Fixed by comparing the `(arm, tier)` identity instead, which matches how the rest of the decision line already treats a candidate (both `arm=` and `tier=` are printed as separate tokens). This is the one place I deviated from the doc's literal Python; the intent (not the letter) of "implement §6 verbatim" is preserved — nothing else in §6 was touched.
   - Untouched: `task_class`'s `sizes:` filter role (R1), freepool floor mode, `UNKNOWN_PROBE_PENALTY`, failure-memory demotion, `effort_matrix`, the legacy resolver, `complexity_penalty` itself (frozen off only when `FIT_MODE == 'on'`, exactly as designed).

3. **`plugins/leadv2/tests/test-router-v2-capability-fit.sh`** (new)
   - 9 cases, one per §9.2 differ/match table row (rows 1–9 as printed in design.md, verbatim complexity/source/cost-pick combinations).
   - 3 negative controls: (a) mutate `glm-flash`'s `capability` 2→4 in a scratch yaml copy, prove `fit_bucket=glm-flash:1` (baseline) → `:0` (mutant); (b) mutate the arbiter's `cx >= PRIOR` branch to drop the confidence discount (`req_eff=cx` → `req_eff=PRIOR`), prove `req_eff=4.0`→`3.0` **and** the actual winner `tier=standard`→`volume` under `FIT_MODE=on`; (c) mutate `SRC_CONF.get(complexity_source, 0.0)`'s default to `0.9`, prove `conf=0.0`→`0.9`, `req_eff=3.0`→`2.1`, and the actual pick `glm`→`glm-flash` under `FIT_MODE=on` (this is design's own §9.3 row 3, reused as instructed). All three controls read a source-line count (`n != 1` aborts the mutation with a named reason) before mutating, so a future refactor that moves the anchor fails loud instead of silently mutating nothing.
   - Header: `# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml` — self-select convention, discoverable by `tests/run-all.sh`'s scan of `plugins/leadv2/tests/` (confirmed via `grep` of `tests/run-all.sh`'s discovery logic; no `EXTRA_SUITE_MAP` edit needed).

## Falsification set (foreground, pasted verbatim, not summarized)

**bash -n / py_compile — all changed files, after every edit:**
```
BASH_SYNTAX_OK   (leadv2-route-arbiter.sh)
PY_COMPILE_OK    (extracted python3 heredoc)
BASH_SYNTAX_OK   (test-router-v2-capability-fit.sh)
```

**New suite — RED before the fit_differs fix (rows 4/5), GREEN after:**
```
# before fix:
FAIL: 9.2 row4 out=... fit_pick=codex fit_differs=0 fit_bucket=codex:1,codex:0,sonnet:0
FAIL: 9.2 row5 out=... fit_pick=codex fit_differs=1 ... (initial run also caught by tier-token
      contradiction in my own first assertion — fixed by switching to fit_bucket= evidence)
SUMMARY: pass=10 fail=2

# after fix (plugins/leadv2/tests/test-router-v2-capability-fit.sh):
PASS: 9.2 row1: heuristic/simple demotes glm-flash, fit_pick=glm fit_differs=1 (pick unchanged, enabled:false)
PASS: 9.2 row2: standard complexity (req_eff=3.0) demotes glm-flash, fit_pick=glm fit_differs=1
PASS: 9.2 row3: unknown provenance is cautious (req_eff=3.0 regardless of low complexity), fit_pick=glm fit_differs=1
PASS: 9.2 row4: complex work with glm capped demotes codex/volume (cap3 short by1), fit_pick=codex(standard, per fit_bucket=codex:1,codex:0,...) fit_differs=1
PASS: 9.2 row5: plan work with glm capped demotes haiku (cap2), fit_pick=codex(volume, tie broken by cost) fit_differs=1
PASS: 9.2 row6: glm (cap4) is cheapest and never demoted, fit_pick=glm fit_differs=0
PASS: 9.2 row7: allowed_arms filter precedes the fit sort, fit_pick=sonnet fit_differs=0
PASS: 9.2 row8: --task-class Heavy (Scenario D) still resolves to glm via the capability table, fit_differs=0
PASS: 9.2 row9: judge-trivial fits glm-flash (cap2), fit_pick=glm-flash fit_differs=0
PASS: NC(a): mutating glm-flash capability 2->4 flips its printed fit_bucket token from :1 to :0
PASS: NC(b): stripping confidence-discount on a >=PRIOR estimate flips req_eff=4.0->3.0 and the actual winner tier=standard->volume (FIT_MODE=on)
PASS: NC(c): SRC_CONF default 0.0->0.9 flips conf=0.0->0.9, req_eff=3.0->2.1, and the actual pick glm->glm-flash (FIT_MODE=on)
SUMMARY: pass=12 fail=0
RC=0
```
`checked=12` (9 §9.2 rows + 3 negative controls).

**Existing suites — before and after, all edits applied:**
```
$ bash plugins/leadv2/tests/test-router-v2-headroom-order.sh
PASS test-router-v2-headroom-order
RC=0
```
(This is the suite the mission names "the only existing arbiter test"; it actually exercises `leadv2-router-v2.sh`, the legacy resolver — confirmed via grep that `router_v2.capability_matrix`/`complexity_penalty`/`capability_fit` are never read by that file, so it is structurally guaranteed unaffected. Ran unchanged before and after my diff, both PASS.)

```
$ bash plugins/leadv2/scripts/tests/test-route-arbiter.sh
SUMMARY: pass=27 fail=0
RC=0
```
(This suite DOES exercise `leadv2-route-arbiter.sh` directly. First run showed `pass=26 fail=1` — the one failure was `dispatch_refused reason=writeset_pending blocked_by=F1-ARBITER-SCORING-20260907-step1... task=c4c38811`, traced to a writeset-overlap guard in `leadv2-dispatch-code.sh` (untouched by this diff) colliding with a genuinely concurrent leadv2 session — not a regression. Re-ran clean at 27/27 once that session finished; pasted the clean run above as final evidence.)
`checked=27` (test-route-arbiter.sh cases), `checked=1` (headroom-order case).

## Live/synthetic-but-labeled dry run (acceptance criterion: tokens present, pick unchanged, enabled:false)

Ran against the **real, committed** `plugins/leadv2/config/leadv2-routing.yaml` (`capability_fit.enabled = False`, confirmed via `yaml.safe_load`), with a stub quota-live script (all providers healthy) and two labeled synthetic descriptors:

```
=== descriptor A: heuristic/simple (design.md §9.2 row1) ===
arm=glm-flash ... reason=cheapest_capable ... complexity_source=heuristic conf=0.4 req_eff=2.6
fit_mode=off fit_pick=glm fit_differs=1 fit_bucket=glm-flash:1,glm:0,codex:0,codex:0,sonnet:0,freepool:1

=== descriptor B: judge/trivial (design.md §9.2 row9) ===
arm=glm-flash ... reason=cheapest_capable ... complexity_source=judge conf=0.9 req_eff=1.2
fit_mode=off fit_pick=glm-flash fit_differs=0 fit_bucket=glm-flash:0,glm:0,codex:0,codex:0,sonnet:0,freepool:0
```

Both lines pick `arm=glm-flash` — **identical to today's behavior, unchanged** — while `fit_pick=`/`fit_differs=`/`fit_bucket=` are fully computed and shown in shadow. Descriptor A demonstrates a would-differ case (`fit_differs=1`, glm would win under `on`); descriptor B demonstrates a match case (`fit_differs=0`). This is the acceptance criterion satisfied directly, not inferred from the test suite.

## Out of scope, confirmed untouched

No persona-engine file touched. No edit to `task_class` sizes-filter logic, freepool floor mode, `UNKNOWN_PROBE_PENALTY`, failure-memory demotion, `effort_matrix`, or the legacy resolver/kimi arm. Steps 2–4 of §8 (task-judge `complexity_basis`, dispatcher `complexity_source`/declared-class floor, the `shadow` env var, flipping `enabled: true`) not started — separate follow-up tasks.

## Runtime-state path check

```
$ git status --porcelain
 M docs/leadv2/.compact-freeze.md      <- SessionStart:compact hook side effect, NOT mine, excluded from commit
?? docs/leadv2/.graveyard-last-run     <- same, excluded from commit
 M plugins/leadv2/config/leadv2-routing.yaml
 M plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
?? plugins/leadv2/tests/test-router-v2-capability-fit.sh
```
Committed only the 3 intended files (`git add` by explicit path, not `-A`); `docs/leadv2/*` left as pre-existing working-tree state, untouched by this commit, per the DEFINITION-OF-DONE gate's runtime-state-path constraint.

## Commit

Committed on the lane branch `worktree-F1-ARBITER-SCORING-20260907-step1`; see `git log -1` for the SHA. Message documents the R5 fix, the capability tiers, the arbiter port, the (arm,tier) fit_differs fix and why, and the new test suite.

DELIVERABLE_COMPLETE
