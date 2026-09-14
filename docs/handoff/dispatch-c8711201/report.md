# CODEX-HAS-TOKENS-BUT-NO-DRAIN-SERIES-01 — report

Lane dispatch-c8711201. Builds the codex half of the drain series, fits it, and
answers the founder's "terra looked almost free" hypothesis with numbers.

## 1. The codex drain series — construction

New tool: `plugins/leadv2/scripts/leadv2-codex-drain-fit.py`.

- **Drain readings**: every `util_codex=<pct>` snapshot the arbiter journals on
  every routing decision (any arm, not just when codex was picked — one shared
  codex account means every consult samples the same window), collected from
  `~/.claude/leadv2-state/*/tasks/*/journal.md` across ALL tasks/repos into one
  sorted, global time series. This is a **backfill**: the readings already
  exist (361 mentioned in the mission, 332 matched by this tool's stricter
  `route_resolved` regex — the gap is decision lines that log `util_codex`
  outside a `route_resolved` line, e.g. probe-only lines, deliberately excluded
  since only a `route_resolved` line is a real arbiter decision, not a bare
  probe). No forward-only sampler was written: the existing journal write path
  already produces one on every decision, so a fresh sampler would just be a
  second writer of the same fact.
- **Token side (ground truth, never a routing decision line)**: codex spawns
  are discovered by scanning `docs/handoff/dispatch-*/arm-registered` for
  `arm=codex handle=<jobId> epoch=<epoch>` lines — the only reliable proof
  codex actually ran (see "Errors avoided" below). Each task's token total is
  `leadv2_lane_token_total` (lib/leadv2-cost-actuals.sh — the same function
  the observed-cost loop itself uses, shelled to rather than reimplemented, so
  a second reader can never drift from that join) and is attributed to the
  interval containing the task's LAST codex-spawn epoch.
- **Model attribution**: each handle's own job record
  (`CODEX_GUARD_STATE_ROOT/*/jobs/<handle>.json`'s `request.model`) — not
  journal.md's `arbiter_pick=codex model=...` decision line. Live-measured:
  0/118 arm-registered-confirmed codex tasks had a `route_resolved` line in
  their own journal at all (dispatched via a path that logs no decision), so
  the journal-based approach that mission text originally implied has a 0%
  hit rate; the job JSON does not.
- **`gpt-6-astra` exclusion**: `request.model` on many jobs literally reads
  `gpt-6-astra` — this is the DISPATCH LAUNCHER's own default alias
  (`leadv2-routing.yaml:497,592`, `router.dispatch_ladder` / `channels`
  entries for `id: codex`, both still say `model: gpt-6-astra` even though
  the capability_matrix moved to real tier names in
  CODEX-TIERS-COLLAPSED-ONTO-ASTRA part B). It is what got SENT in the
  request, not proof of which tier codex resolved to internally. Per the
  mission's explicit instruction, this is excluded from per-model attribution
  entirely (treated as unresolved, counted in `codex_tasks_no_job_model`,
  never fitted as a 4th column). Verified live: 36/118 tasks hit this case.
- **Reset-spanning interval handling — reused, not reinvented**: `build_intervals()`
  imports `nnls`, `_pearson`, `_ts_to_epoch` and `MIN_INTERVALS` directly from
  `leadv2-drain-weights.py` via `importlib.util` (the same reuse pattern that
  file itself uses for `leadv2-quota-read.py`), and mirrors its interval loop
  exactly: `Δpct < 0` → `dropped_reset` (a reset made the reading jump down
  mid-interval — an artifact, not drain); `Δpct == 0` with zero attributed
  tokens → `dropped_idle` (no information); `Δpct == 0` WITH tokens is kept
  (real information).

### Live run (2026-09-14)

```
provider=codex kept=114 threshold=12 dropped_reset=2 dropped_idle=215 codex_tasks_resolved=118 codex_tasks_unresolved_token=123 codex_tasks_mixed_model=1 codex_tasks_no_job_model=36 readings=332 r2=-0.3974 max_abs_corr=0.000 degenerate_pairs=0 weights=codex_total=0.00000004
  codex_total weight=0.00000004 Δpct per token (per 1M tokens: +0.0429)
provider=codex per_model kept=61 r2=0.1456 max_abs_corr=0.402 degenerate_pairs=0 weights=gpt-5.6-luna=0.00000000,gpt-5.6-terra=0.00000007
  gpt-5.6-luna     weight=0.00000000 Δpct per token (per 1M tokens: +0.0016)
  gpt-5.6-terra    weight=0.00000007 Δpct per token (per 1M tokens: +0.0703)
```

Reset-spanning intervals dropped: **2** (out of 331 raw intervals between 332
readings). Idle intervals dropped: 215 (readings are dense relative to codex
spawn frequency — most decision consults land between codex dispatches).
Kept: 114.

## 2. The fit

**Aggregate (provider-level, one `codex_total` column)**: `r2=-0.3974`,
`max_abs_corr=0.000`, `degenerate_pairs=0`, `kept=114`. Per the mission's
binding rule ("a provider whose R² stays negative gets NO price"), **codex's
`router_v2.cost.codex` stays `null`** — `plugins/leadv2/config/leadv2-routing.yaml`
was updated to point at this report instead of the dead
`dispatch-f8880421/developer.full.md` reference, the numeric value is
unchanged (still `null`). max_abs_corr/degenerate_pairs are trivially 0/0 for
a single-column fit (no pair exists to correlate) — printed anyway, per the
same binding rule ("report … on every fit you quote").

**Per-model (terra vs luna; sol absent — see below)**: `r2=0.1456`,
`max_abs_corr=0.402`, `degenerate_pairs=0`, `kept=61`. This is weak-but-positive,
not negative, and notably NOT collinear the way Anthropic's four tiers are
(their sibling fit's `max_abs_corr` is 0.913–0.934, see §3) — codex's three
tiers get dispatched with enough independence across the fitted window that
this per-model fit is not automatically defeated the same way. It is still
weak (R²=0.1456 explains 15% of variance), so its numbers are reported as
directional evidence, not as a price this repo's schema has anywhere to put
(`router_v2.cost` is keyed by PROVIDER, not model — there is no per-model slot
to write into even if the fit were strong).

**`gpt-5.6-sol` has zero data in this window.** It never appears as a column
in either fit: no arm-registered-confirmed codex task in this sample resolved
cleanly to `gpt-5.6-sol` via `request.model`. Named here per the mission's
"name the surface of every count" rule — this is a real gap, not an omission.

**Published relative weight — checked first, per the sibling lane's
amendment, before trusting the per-model fit as the only source:**
`plugins/leadv2/config/model-capability.yaml` (lines ~160-230) has
`codex-standard`/`codex-top` benchmark rows but no `codex-volume` entry and no
usable numeric quota-weight ratio. A web search surfaced third-party cost
tables for gpt-5.6-{sol,terra,luna} — but WebFetch of OpenAI's own help
center page returned HTTP 403 (could not verify the primary source), and
WebFetch of the specific third-party page the search cited
(`backgrind.com/blog/gpt-5-6-sol-terra-luna/`) returned NUMBERS THAT DISAGREED
with the search snippet quoting the same page (search: sol
250/25/1500, terra 125/12.5/125, luna 50/5/300 per-1M input/cached/output;
direct fetch of the same URL: sol 125/12.5/750, terra 50/5/300, luna
5/0.5/30). **UNVERIFIED and internally inconsistent — not used.** No reliable
published relative weight exists for these three tiers, so the mission's
fallback condition ("only collapse if none exists") is met, and the empirical
per-model NNLS fit above is reported as the best available evidence instead —
un-collapsed, since it was not defeated by collinearity the way Anthropic's
was.

## 3. The terra question

> He has said more than once that codex requests on terra looked "almost
> free" and flagged his own uncertainty. Answer it with a number: terra's
> fitted weight against sonnet's and glm's, or a plain statement that the data
> cannot separate them and why.

**Terra's own number**: weight `0.00000007` Δpct per token — **+0.0703
percentage points of the codex window per 1,000,000 tokens** — on a
weak-but-positive fit (R²=0.1456, kept=61, max_abs_corr=0.402,
degenerate_pairs=0). Luna's number is smaller still (+0.0016/1M, ≈0).

**But a side-by-side against sonnet's/glm's number cannot be honestly made**,
because those numbers do not exist as validated fit outputs — re-run live
today for this report:

```
$ python3 leadv2-drain-weights.py --window 5h
window=5h account=eb6c5b97 kept=114 threshold=12 dropped_reset=30 dropped_idle=41 fable_intervals_excluded=11 r2=-0.2975 max_abs_corr=0.934 degenerate_pairs=5 weights=<synthetic>=0.00000000,claude-haiku-4-5-20251001=0.00000000,claude-opus-5=0.00001565,claude-sonnet-5=0.00001940,glm-5.3=0.00000000,glm-5.3-flash=0.00000182 snapshots=197
  claude-sonnet-5              weight=0.00001940 Δpct per token  (per 1M tokens: +19.4020)

$ python3 leadv2-drain-weights.py --window 7d
window=7d account=eb6c5b97 kept=78 threshold=12 dropped_reset=2 dropped_idle=103 fable_intervals_excluded=13 r2=-0.5817 max_abs_corr=0.913 degenerate_pairs=5 weights=<synthetic>=0.00000000,claude-haiku-4-5-20251001=0.00000000,claude-opus-5=0.00000401,claude-sonnet-5=0.00000000,glm-5.3=0.00000000,glm-5.3-flash=0.00000000 snapshots=197
  claude-sonnet-5              weight=0.00000000 Δpct per token  (per 1M tokens: +0.0000)
```

Both windows have **negative R²** (-0.30, -0.58) with **very high collinearity**
(max_abs_corr 0.913–0.934, degenerate_pairs=5) — the exact same defeat
condition already on record for Anthropic's per-model fit
(`leadv2-routing.yaml:161-165`, PRICE-THE-ARM-PER-PROVIDER-01: "per-model NNLS
pricing is off the table"). Sonnet's own weight is not even stable between
the two windows (19.4 vs 0.0/1M tokens) — by this repo's own binding rule
("a provider whose R² stays negative gets NO price"), **sonnet has no valid
per-model number to compare terra against.** Glm's number is 0.0 in both
windows for the same collinearity reason.

**Answer: cannot be separated with a validated sonnet/glm comparison point,
because the only per-model fit that would produce one has negative R² in
both windows tried (max_abs_corr 0.91-0.93) — the identical defect already
documented for Anthropic pricing.** What IS available is terra's own number:
+0.0703 Δpct/1M tokens on a weak-but-positive R²=0.1456 fit — small in
absolute terms and directionally consistent with "almost free," but 15%
explained variance is suggestive, not proof. This is reported as evidence,
not asserted as a settled price.

## Falsification set

Red (before the astra-alias fix and the `main()` reconciliation, the exact
point this session picked back up from — captured live, not reconstructed):
```
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-codex-drain-fit.py
# (compiled clean even in the broken state -- the defect was a NameError/
# shape mismatch at RUNTIME, not a syntax error; py_compile alone would not
# have caught it)
$ python3 plugins/leadv2/scripts/leadv2-codex-drain-fit.py
Traceback (most recent call last):
  ...
NameError: name '_codex_models_for_task' is not defined
```
(`_codex_models_for_task` had been removed in favor of `_job_model`, but the
call site in `main()` still referenced it — this is the exact broken state
the prior context-compaction summary described.)

Green (after fixing `main()` to consume `_scan_codex_spawns()`'s
`{(root, sig8): [(epoch, handle), ...]}` shape and call `_job_model(handle)`,
then after the follow-on `gpt-6-astra` exclusion fix):
```
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-codex-drain-fit.py
COMPILE_OK
$ python3 plugins/leadv2/scripts/leadv2-codex-drain-fit.py
provider=codex kept=114 threshold=12 dropped_reset=2 dropped_idle=215 codex_tasks_resolved=118 codex_tasks_unresolved_token=123 codex_tasks_mixed_model=1 codex_tasks_no_job_model=36 readings=332 r2=-0.3974 max_abs_corr=0.000 degenerate_pairs=0 weights=codex_total=0.00000004
  codex_total weight=0.00000004 Δpct per token (per 1M tokens: +0.0429)
provider=codex per_model kept=61 r2=0.1456 max_abs_corr=0.402 degenerate_pairs=0 weights=gpt-5.6-luna=0.00000000,gpt-5.6-terra=0.00000007
  gpt-5.6-luna     weight=0.00000000 Δpct per token (per 1M tokens: +0.0016)
  gpt-5.6-terra    weight=0.00000007 Δpct per token (per 1M tokens: +0.0703)
```

New test suite (`plugins/leadv2/scripts/tests/test-codex-drain-fit.sh`, 13
assertions: py_compile/bash-n statics, dropped_reset counting, dropped_idle
counting, resolved/unresolved-token counting, the astra-alias exclusion, the
NOT-ENOUGH-DATA gate, and the evidence-quadruple format):
```
$ bash plugins/leadv2/scripts/tests/test-codex-drain-fit.sh
[TEST] PASS: 0a py_compile leadv2-codex-drain-fit.py
[TEST] PASS: 0b py_compile leadv2-drain-weights.py
[TEST] PASS: 0c bash -n lib/leadv2-cost-actuals.sh
[TEST] PASS: 5 below MIN_INTERVALS -> NOT-ENOUGH-DATA, no fit line printed
[TEST] PASS: 1a kept=2 (only the two real-delta intervals survive)
[TEST] PASS: 1b dropped_reset=1 (E2->E3 delta=-45, reset artifact)
[TEST] PASS: 2 dropped_idle=1 (E3->E4 delta=0, zero tokens)
[TEST] PASS: 3a codex_tasks_resolved=2 (task A + task B)
[TEST] PASS: 3b codex_tasks_unresolved_token=1 (task C, stub returns -)
[TEST] PASS: 4a codex_tasks_no_job_model=1 (task B's astra alias excluded)
[TEST] PASS: 4b gpt-6-astra never appears as a fitted column
[TEST] PASS: 4c per-model fit correctly sees only 1 real slug (terra) after excluding astra
[TEST] PASS: 6 aggregate fit line carries r2/max_abs_corr/degenerate_pairs together
SUMMARY pass=13 fail=0
```
Self-registered: `# run-all-triggers: leadv2-codex-drain-fit leadv2-codex-drain-fit.py leadv2-drain-weights leadv2-drain-weights.py leadv2-cost-actuals` (header line 1).

## The six suites that must stay green

```
$ bash plugins/leadv2/tests/test-arbiter-prices-by-provider.sh | tail -1
SUMMARY pass=7 fail=0
$ bash plugins/leadv2/scripts/tests/test-reset-urgency.sh | tail -1
SUMMARY: pass=10 fail=0
$ bash plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh | tail -1
SUMMARY pass=6 fail=0
$ bash plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh | tail -1
launcher-refusal-event: PASS=4 FAIL=0
$ bash plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh | tail -2
=== Results: 36 passed, 0 failed ===
$ bash plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh | tail -1
SUMMARY pass=9 fail=0
```
All six green.

## Changed-scope run (`tests/run-all.sh --scope changed`)

Surfaced 10 `[NOT-KNOWN-RED]` failures in unrelated suites (capability-floor
case E, think-through-arbiter, route-arbiter, arm-pool-reachability,
capability-fit, codex-tiers-selectable, plugin-papercuts, exclusion-stages,
effort-routing, route-arbiter-failure-memory). **Verified pre-existing, not
caused by this diff**: reverted the one routing.yaml comment edit
(`git checkout --` then re-applied via saved diff) and re-ran two of them —
`test-arbiter-reads-capability-floor.sh` and `test-think-through-arbiter.sh`
— against bare HEAD; both failed identically (same "case E" mismatch, same
3/15 think-through failures). None of the failing suites' `run-all-triggers`
headers relate to codex drain/token fitting; they were pulled in only because
editing `leadv2-routing.yaml` is a broad trigger keyword. This diff's own new
suite and all six mission-mandated suites are green (above).

## Off-limits respected

- Did not touch `~/.claude/burn/history.db` or its writer.
- Did not write a codex price the fit does not support — `cost.codex` stays
  `null`, comment only updated.
- Did not touch `reset_urgency`, the decision record schema, the launcher-
  refusal event, or the judge parser.
- Did not touch `docs/tasks.yaml` or `docs/leadv2/open-threads.md`.
