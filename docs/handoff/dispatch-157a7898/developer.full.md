# dispatch-157a7898 — CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01 (Part A/B)

## Scope actually touched (LANE_WRITES, exactly 3 files)
- `plugins/leadv2/scripts/codex-task.sh`
- `plugins/leadv2/scripts/lib/leadv2-launch-registry.py`
- `plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh` (new)

## Part A — codex-task.sh

**Before:** `top`/`standard`/`volume` all resolved to `gpt-6-astra` (only `--effort` differed);
the header comment still documented an unimplemented sol/terra/luna mapping; a second, dead
`_tier_model_effort()` existed only inside the timeout-retry path of `_run_with_fallback()`.

**After:** one `_codex_model_present(model)` (jq presence check against
`~/.codex/models_cache.json`, the same check the old `top` branch already did — generalized,
not invented) and one `_tier_model_effort(tier)` — used by BOTH the inline `_TIER` extraction
block and `_run_with_fallback()`'s timeout-retry path (old duplicate deleted, replaced with a
pointer comment). Mapping (derived from `config/leadv2-routing.yaml:213-215` cost ordering
`volume(3) < standard(4) < top(7)` plus the file's own historical header comment — not invented
taste):

| tier | primary model | fallback chain if absent |
|---|---|---|
| top | gpt-5.6-sol | astra (named, journaled) |
| standard | gpt-5.6-terra | astra (named, journaled) |
| volume | gpt-5.6-luna | astra (named, journaled) |

Effort stays a wholly separate concern (`WIRE_EFFORT`/`TIER_EFFORT`), computed from tier
independently of which model tier resolved to — this is what lets Part B vary effort per
task_class without touching model choice.

Every substitution is named and journaled, never silent:
`CODEX_FALLBACK_EVENT tier=<t> wanted=<model> fallback=astra reason=absent_from_models_cache`.

Header comment (lines ~14-23) rewritten to document the real implemented mapping instead of the
stale "not yet implemented" note.

### Two bugs found + fixed while building this (falsification evidence)

1. **`set -e` killed the whole script after tier resolution.** Original close of
   `_tier_model_effort()` used the bare idiom
   `[[ "$WIRE_EFFORT_OUT" == "ultra" ]] && WIRE_EFFORT_OUT="xhigh"`
   as the function's last command. Inside a function, the function's own exit status IS its last
   command's status, and a bare failing function CALL (not part of an `&&`/`||` list at the point
   of call) trips `set -e` — unlike the same idiom written inline at top level, where only the
   right-hand side's failure could trip it. Observed via `bash -x`: script exited status 1, zero
   stdout, immediately after `TIER_MODEL_OUT=gpt-5.6-sol; WIRE_EFFORT_OUT=high` — i.e. it died
   returning from its own helper. Fixed by converting to an explicit `if/fi` ending in `return 0`,
   with a comment flagging the regression class so it isn't reintroduced.
2. **Dropped `TIER_EFFORT`.** My first rewrite of the inline `_TIER` block set `TIER_MODEL` and
   `WIRE_EFFORT` but not `TIER_EFFORT`, which the pre-existing `CODEX-TIER-ENFORCER-01` JSONL
   logger reads via `"${TIER_EFFORT:-}"`. Fixed by adding `TIER_EFFORT="$WIRE_EFFORT_OUT"`.

### Live verification (real spawns, not config read-back)
```
$ plugins/leadv2/scripts/codex-task.sh task --tier top --reason "dispatch-157a7898 live check" --wait
tier=top -> model=gpt-5.6-sol [effort=high] (sub=task)
... job reached: completed

$ plugins/leadv2/scripts/codex-task.sh task --tier standard --wait
tier=standard -> model=gpt-5.6-terra [effort=medium] (sub=task)
... job reached: completed

$ plugins/leadv2/scripts/codex-task.sh task --tier volume --wait
tier=volume -> model=gpt-5.6-luna [effort=low] (sub=task)
... job reached: completed
```
All three tiers resolved to their own distinct model (not astra) and each completed a real job.

## Part B — leadv2-launch-registry.py

Added `CODEX_MODEL_TIER_TUPLES = (("gpt-5.6-sol","top"), ("gpt-5.6-terra","standard"),
("gpt-5.6-luna","volume"))` and `_codex_model_for_tier(tier, fallback_model)`, plus
`_codex_canonical_models(matrix_rows)` (unions the matrix's astra entries with the per-tier
models above) so `check(arm="codex", model=...)` accepts sol/terra/luna without widening
anything else — every existing kind/trust restriction on the codex row (`protected: true`,
`review: true`, kind allow-list) is preserved untouched; only the accepted-model set for the
`codex` arm was widened, nothing was loosened for any other arm.

`_argv_claude`/`_argv_codex` gained a `kind=None` parameter. `_argv_codex` now emits
`--effort <effort>` (in addition to the pre-existing `--tier <tier>` [+ `--reason` for `top`])
**only when `kind == "code"`**, returning `effort_supported=True` in that case (previously always
`False`). This is the founder's verbatim requirement — "и выбирать эффорт везде в зависимости от
задач" — effort is keyed per (model, tier, task_class), not a constant, without touching model
resolution (which Part A owns).

`lookup()` now computes `reported_model` via `_codex_model_for_tier` when `provider == "codex"`,
so the descriptor reports the actually-launchable model (sol/terra/luna) instead of the stale
matrix placeholder (astra), and passes `kind` through to the argv builder.

### Verification
- `python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-launch-registry.py` — clean.
- Ad-hoc functional checks: `check("codex","gpt-5.6-sol")` / `terra` / `luna` all accept;
  `lookup(..., provider="codex", tier="top", kind="code")` reports model=gpt-5.6-sol with
  `--effort` present; non-code kinds omit `--effort` as before.
- Pre-existing `plugins/leadv2/tests/test-launch-registry-argv.sh`: **13/13 pass, unchanged.**

## Part C — new test: test-codex-tier-model-table.sh

Self-registers via header `# run-all-triggers: codex-task` (confirmed via
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` →
`codex-task:plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh`); no edit to
`tests/run-all.sh` was made or needed.

Extracts `_codex_model_present`/`_tier_model_effort` verbatim from `codex-task.sh` via `sed`,
builds 4 fixture `models_cache.json` variants, and asserts:
- each tier resolves to its own primary model when present (positive path),
- fallback-to-astra when a primary is absent from the fixture cache,
- the `CODEX_FALLBACK_EVENT` journal line is emitted on fallback and NOT emitted on the
  positive path.

**Negative controls (E2E-KILLRATE-01), both applied inside the function body, never top-level:**
1. Mutant A re-collapses the tier table onto astra for all 3 tiers → asserted to turn the
   resolved-model assertion RED for ≥2 tiers (proves the positive assertion has teeth).
2. Mutant B silences the fallback journal line (comments out the `CODEX_FALLBACK_EVENT` echo) →
   asserted to turn the journal-line assertion RED (proves the journal assertion has teeth).

Bug found building this: BSD/macOS `sed`'s POSIX ERE doesn't support `\s`; the silent-fallback
mutation regex used `\s*` and silently matched nothing (mutant came out byte-identical to the
original, so both negative-control assertions failed with "mutation did not change the extracted
body"). Root-caused with a standalone one-line `sed` repro, fixed by switching to `[[:space:]]*`.

**Result: `bash -n` clean → PASS=17 FAIL=0**, both negative controls confirmed catching their
mutants (red before the fix, green after).

## Falsification set (full raw evidence)
```
$ bash -n plugins/leadv2/scripts/codex-task.sh                                   # clean, exit 0
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-launch-registry.py     # clean, exit 0
$ bash -n plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh            # clean, exit 0
$ bash plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh
PASS=17 FAIL=0
$ bash plugins/leadv2/tests/test-launch-registry-argv.sh
PASS=13 FAIL=0
$ bash plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh   -> PASS=29 FAIL=0
$ bash plugins/leadv2/scripts/tests/test-codex-quota-gate.sh        -> PASS=10 FAIL=0
$ bash plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh  -> PASS=5  FAIL=0
```

### Pre-existing failures investigated, ruled NOT regressions
For each, reverted `codex-task.sh` to `HEAD` (`git show HEAD:plugins/leadv2/scripts/codex-task.sh
> plugins/leadv2/scripts/codex-task.sh`), re-ran the suite, got IDENTICAL failures, then restored
my version (`diff` byte-identical, `git status --short` back to exactly the 3 expected
changed/new files):
- `test-codex-timeout-tier-resolution.sh` — 4/5 sub-tests fail on both HEAD and my branch.
- `test-worker-mcp-all-arms.sh` — 1/49 fails on both ("preamble gate: sonnet default...").
- `test-plugin-papercuts.sh` — times out at "P5 --resume-lane..." on both.

None of these three touch tier→model resolution; failures are environment-sensitive /
pre-existing, not introduced by this change.

## Part B (routing.yaml) — copy-paste-ready rows for the OTHER lane

`config/leadv2-routing.yaml` is held by another lane and was only read (lines 205-224), never
edited, here. These are the rows that lane should use to replace lines 213-215 so the matrix's
declared model matches what `codex-task.sh` actually launches per tier (same kinds/sizes/tags/
review/protected/capability as today — only `model` changes, cost ordering unchanged):

```yaml
    - { arm: codex, provider: codex, model: gpt-5.6-luna, tier: volume, cost: 3, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard], tags: [review, adversarial], review: true, protected: true, capability: 3 } # CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01: volume now launches gpt-5.6-luna (codex-task.sh _tier_model_effort), astra only as named/journaled fallback when luna is absent from ~/.codex/models_cache.json.
    - { arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, cost: 4, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard, heavy], tags: [review, adversarial], review: true, protected: true, capability: 4 } # same CODEX-TIERS-... — standard now launches gpt-5.6-terra, astra fallback only.
    - { arm: codex, provider: codex, model: gpt-5.6-sol, tier: top, cost: 7, kinds: [code, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [heavy], tags: [adversarial, exhaustive], review: true, protected: true, capability: 4 } # same CODEX-TIERS-... — top now launches gpt-5.6-sol, astra fallback only.
```

Nothing else on those lines changes: kind/size/tag/review/protected/capability are copied
verbatim from the existing rows, so this only fixes the declared model to match reality —
it does not widen or narrow anything the arbiter or launch-registry gate does today.

## Commit
Committed exactly the 3 lane files (no `git add -A`):
`git commit -- plugins/leadv2/scripts/codex-task.sh plugins/leadv2/scripts/lib/leadv2-launch-registry.py plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh`

DELIVERABLE_COMPLETE
