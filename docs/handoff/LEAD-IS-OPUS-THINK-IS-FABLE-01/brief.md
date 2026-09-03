# LEAD-IS-OPUS-THINK-IS-FABLE-01

**Founder decision, 2026-09-03** (answered in chat; supersedes FABLE-THINK-TIER-01 in the part that
touches the lead's own model):

> «fable не дефолт же, у нас лид на опусе, а вот архитекторы и т.д. на fable это ок и мб воркер для
> сложных задач»

Chosen option: **lead = Opus everywhere by default; Fable moves to the thinking roles.**

## What is on disk today

`FABLE-THINK-TIER-01 R4` collapsed two different axes into one. The lead's main model is currently
*derived from the think-model resolver*:

    plugins/leadv2/scripts/leadv2-repo-install.sh:56-57
        THINK_MODEL_RESOLVED="$(bash "${CANON}/lib/leadv2-think-model.sh" ...)"
        THINK_MODEL_RESOLVED="${THINK_MODEL_RESOLVED:-fable}"
    plugins/leadv2/scripts/leadv2-repo-install.sh:347
        "LEADV2_MAIN_MODEL": os.environ.get("LV2_THINK_MODEL", "fable")
    plugins/leadv2/scripts/leadv2-repo-install.sh:354
        "LEADV2_THINK_MODEL": os.environ.get("LV2_THINK_MODEL", "fable")

    plugins/leadv2/ref/leadv2-main-model.yaml
        main_model: fable

Consequence, measured 2026-09-03: the adoption sweep wrote `LEADV2_MAIN_MODEL=fable` into eight
freshly-adopted MythicalGames repos. `persona-engine` only escapes it through a per-repo override
to `opus`.

## The two axes, separated

| axis | value | who it governs |
|---|---|---|
| **main model** | **opus** | the lead itself — a thin router: talks to the founder, classifies, dispatches, adjudicates |
| **think model** | **fable** | architect, plan synthesis, judge — and possibly a worker arm for hard tasks |

The think resolver (`lib/leadv2-think-model.sh`) stays exactly as it is and keeps owning the second
row. It must stop owning the first.

## What this task must deliver

1. **`LEADV2_MAIN_MODEL` gets its own default of `opus`**, independent of `LV2_THINK_MODEL`.
   `LEADV2_THINK_MODEL` keeps coming from the think resolver (fable). Name every file:line changed.
2. **`ref/leadv2-main-model.yaml` → `main_model: opus`**, header comment rewritten to this decision
   and date rather than the FABLE-THINK-TIER-01 rationale it carries now. Note that
   `leadv2-main-model-check.sh` runs Opus guardrails when the value is `opus` and falls back to
   **sonnet** if one fails — confirm the guardrails pass in a normal repo, and argue in the report
   whether that sonnet fallback is the behaviour we want for a freshly adopted repo that has no
   skills/scripts yet.
3. **Backfill the repos already stamped with `fable`**: `environment-platform, m3, mondia-portal,
   mp-frontend, mythical-aii, pf3-backend, pf3-local-dev, pf3-smart-contracts`, plus
   `getmany-followup-bot` and `m3-market` if they carry the same value.
   **In `m3` the env block lives in `.claude/settings.local.json`, not `settings.json`** — that
   repo's `settings.json` is tracked by git and must stay untouched (see
   `INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01`). Never commit inside a MythicalGames repo.
4. **Answer whether Fable should also be a worker arm for hard tasks**, with a reason. The founder
   raised it as an open question ("мб воркер для сложных задач") — answer it in the report; implement
   it only if the answer is yes and the routing change is small and testable.
5. **Update the FABLE-THINK-TIER-01 assertions** at
   `plugins/leadv2/scripts/tests/test-fable-think-tier.sh` so they assert the split, not the
   collapse. Do not delete assertions to make it green.
6. **A negative control per claim**: force `LEADV2_MAIN_MODEL` back to the think value, show red;
   revert, show green. Then the reverse for the think axis, so a future change cannot re-collapse
   them in either direction.
7. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it on a change to
   `leadv2-repo-install.sh` and to `ref/leadv2-main-model.yaml`.
8. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, hardcoding an arm out of
routing, and retuning the think resolver — this task separates the axes, it does not change either
one's own logic.
