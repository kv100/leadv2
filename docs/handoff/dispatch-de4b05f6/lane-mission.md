CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01, PART A — make sol / luna / terra
launchable as themselves. This is the open half of the founder's gate before WAVES; the astra half
was proven live at 19:59:49Z and is done.

REPO: ~/Projects/leadv2 (the plugin repo is the single source; edit there, never a copy in a project).
Gate table with the measured status of all six requirements:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/GATE-EVIDENCE.md` — read row 1b.

## What is measured, 2026-09-07T20:05Z — not assumed

**The models exist on this account.** `~/.codex/models_cache.json` (written 23:01 local today) lists:
`gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, plus `gpt-5.5`, `gpt-5.4-mini`,
`gpt-5.3-codex-spark`, `codex-auto-review`, `gpt-reserve`.

**But our launcher can reach exactly one of them.** `codex-task.sh:1409-1423` and the parallel block at
`:2012-2020` map ALL THREE tiers to the same model:

    top      -> gpt-6-astra / high   (with a models_cache presence check at :1409)
    standard -> gpt-6-astra / medium
    volume   -> gpt-6-astra / low
    *        -> gpt-6-astra / medium

Only the effort differs. sol, luna and terra are unreachable through any tier.

**And the file lies about it.** Its own header, `codex-task.sh:14-20`, still documents the mapping the
code stopped implementing:

    top      -> gpt-5.6-sol/high, falls back to gpt-5.6-terra/xhigh if sol is absent
    standard -> gpt-5.6-terra/medium   (EFFORT-RECAL 2026-07-10, was /high)
    volume   -> gpt-5.6-luna/low       (EFFORT-RECAL 2026-07-10, was /medium)

This is the third artifact of that class found today (the others: `transport_gone_app_server_absent`
attached unconditionally, and `pipeline_route=plan_first` at 100 % of its population). **A comment that
describes behaviour the code does not have is worse than no comment** — it is what sent the previous
investigation in the wrong direction. Whatever mapping you land, the header must match it exactly.

## What to build — two files, both uncontended

### A. `plugins/leadv2/scripts/codex-task.sh` — un-collapse the tier table
Restore a tier → (model, effort) table in which **each tier can resolve to a different model**, driven
by what `~/.codex/models_cache.json` actually offers, with the presence check the `top` branch already
demonstrates at `:1409` (`jq -e '.models[]? | select(.slug==...)'`) generalized to every tier.

Rules:
- **A model absent from the cache must fall back, never fail** — and the fallback must be journaled by
  name, not silently substituted. The existing `top` branch is the shape to follow.
- **Effort stays per tier and must remain distinguishable from the model choice.** Model = hardness,
  effort = marginal value of extra thinking; `leadv2-routing.yaml:236` already states that split. Do
  not fold them together.
- Do NOT invent a preference order from taste. Derive the tier→model assignment from the cost/
  capability ordering already recorded for codex rows in `config/leadv2-routing.yaml:213-215`
  (READ ONLY — that file is held by a live lane) plus the historical mapping in the header comment,
  and say in your report which source you used for each tier.
- Fix the header comment (`:14-20`) to state the mapping you actually implemented.

### B. `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` — add the codex tuples
This file landed on `main` an hour ago (commit `b761089d`, part A of the launch registry). Read it
first — it already defines the `(kind, role, arm, task_class) -> argv` shape, a `check(arm, model)`
refusal helper, and `_argv_codex`. Add one registry entry per **(codex model, tier)** pair that part A
above makes launchable, each with its own effort per task class — **effort is part of the key, not a
constant** (founder requirement, verbatim: models must be selectable «и выбирать эффорт везде в
зависимости от задач»). Preserve every kind/trust restriction the matrix already imposes; the registry
narrows what is launchable and never widens what is allowed.

## Scope boundary — the matrix rows are part B, not yours

`config/leadv2-routing.yaml` (the `router_v2.capability_matrix` rows the arbiter selects from),
`leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py` and
`tests/run-all.sh` are held by a live lane. **Do not touch them; read them freely.** Without new matrix
rows the arbiter still cannot pick sol/luna/terra by itself — that is expected and is part B. Your job
is to make them launchable and registry-addressable so part B is a config change, not a redesign.

In your report, write the exact matrix rows part B must add (arm/provider/model/tier/cost/kinds/sizes/
capability), modelled on `:213-215`, so it is a copy-paste.

## Acceptance
acceptance:
  surface: log_line
  observable: For each of `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`, a real `codex-task.sh` run at
    the tier that selects it reports THAT model in its own resolution line (`tier=… -> model=… effort=…`)
    and the job reaches `completed`. One live run per model, not a table read back from config.
    A model absent from `models_cache.json` is reported as a NAMED fallback, never a silent astra.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the tier-resolution function body, re-collapse every tier onto `gpt-6-astra`. The suite must
   go red **on the resolved model name**, for at least two different tiers — a control that only checks
   one tier cannot tell a collapsed table from a correct one.
2. Inside the fallback branch, make an absent model resolve silently to astra without journaling the
   substitution. The suite must go red on the MISSING journal line.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass.
Your new suite must self-register with `# run-all-triggers: codex-task` (verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`); do NOT edit `tests/run-all.sh`.

## Constraints
- Do NOT install anything, do not delete anything from `~/.codex`, do not log in or out of codex.
- Never `git add -A`; name every path, and `git commit -- <the same paths>`.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim in the report carries its artifact: a diff hunk, a resolution line, a suite output.
  "Unverified" is said out loud; "should work" is never said.

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/lib/leadv2-launch-registry.py, plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh


---

## Dispatch note 2026-09-08 — why this is being sent again

The previous attempt never ran. It was refused by the dispatcher with
`dispatch_refused reason=duplicate_task_signature`: the dedupe key is the MISSION CONTENT,
not the task id, so re-sending the same file under a new id is refused even though the
worktree is created and an anchor commit lands. From the outside that looks exactly like
"the worker produced nothing", and it cost three attempts across three rows before the
dispatcher's own log named it.

Nothing about the work below changed. This paragraph exists to change the signature, and to
leave the reason on the record where the next reader will find it.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-de4b05f6" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.