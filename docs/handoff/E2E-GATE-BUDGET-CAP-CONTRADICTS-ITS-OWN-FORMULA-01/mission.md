# E2E-GATE-BUDGET-CAP-CONTRADICTS-ITS-OWN-FORMULA-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The defect, measured

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:4000-4004`:

```bash
_pc_e2e_budget_default=$(( 1200 + 120 * (_pc_e2e_selected_for_budget - 1) ))
[[ "${_pc_e2e_budget_default}" -gt 3600 ]] && _pc_e2e_budget_default=3600
```

The formula states the gate's own belief about how long a run takes: 1200s of fixed cost plus
120s per selected suite. The cap then throws that belief away. The two disagree for every
selection above **21 suites** — `(3600 - 1200) / 120 + 1 = 21`. Above that line the gate is
allocating a budget it has itself just computed to be insufficient, so the run is scheduled to
be killed rather than to finish.

Observed on lane `66e478c3` (row `d6ea56a3cc02`, `NO-WORK-TERMINAL-…`), 2026-09-17T11:38:19Z:

```
e2e_gate task=66e478c3 status=ran verdict=timeout rc=124 timeout_s=3600
  selected_suites=65 completed_suites=37
  interrupted_suite=…/tests/test-review-arm-no-verdict.sh
→ dispatch_terminal task=66e478c3 terminal=parked cause=e2e_timeout
```

The formula's own number for 65 suites is `1200 + 120*64 = 8880s`. The observed rate was
37 suites in 3600s ≈ 97s/suite, i.e. ~6300s for 65 — so **the formula was roughly right and the
cap was wrong**. The lane did not fail review; it was parked by an arithmetic contradiction.

Note the shape of the loss: `rc=124` is a **timeout**, not a red suite. 37 suites' worth of
work was discarded and no verdict was produced about any of them.

## What is NOT in scope

Whether `--scope changed` should select 65 suites for a small write set is a **different
question** and is not this row. Do not widen into it. If you find evidence about it, write it
down as an observation and file it separately rather than fixing it here.

## The design question

Raising the cap is the obvious move and it is probably wrong on its own: the cap exists because
a hung suite would otherwise block dispatch-close forever, which the comment at `:4005-4011`
says explicitly (`PPC-G8`, both writers of `e2e-gate-passed.flag` must share one enforcement
mechanism). A single whole-run deadline cannot distinguish "many suites, all healthy" from "one
suite hung".

So the likely correct shape is a **per-suite deadline** plus a whole-run ceiling derived from
it, so that a hung suite is killed at its own deadline and the run continues and still produces
a verdict for every other suite. State which you chose and name what you rejected. If you keep a
whole-run cap, it must not contradict the budget the same function just computed.

Whatever you choose, the partial-result property must hold and must be what your first control
proves: **a run that exceeds its budget still reports a verdict for every suite that completed**,
rather than collapsing 37 results into one `rc=124`.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not remove the deadline. An unbounded e2e gate is how dispatch-close hung before `PPC-G8`.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — another lane holds it.
- The standalone gate `leadv2-phase8-e2e-gate.sh` writes the same flag. If you change enforcement
  here and not there, the fix is partial by the file's own comment — check both and say what you
  found.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. a selection above the old 21-suite line now gets a budget consistent with the formula → revert
   your change and confirm the old under-budget value returns;
2. a hung suite is still killed → mutate the deadline inside the function body and confirm the
   suite goes red.

Apply each mutation **inside the function body in the lane worktree**, never a scratch copy.
Assert the mutation target string is present before running, so a control cannot rot into a
permanent green.

## Deliverable

`docs/handoff/E2E-GATE-BUDGET-CAP-CONTRADICTS-ITS-OWN-FORMULA-01/report.md` — the chosen
enforcement shape with the rejected alternative named, the arithmetic for the new budget with its
inputs, both controls with pasted output, the suite that now guards this budget by name, and how
CI selects it on a change to `leadv2-dispatch-product-close.sh`. If no such suite exists, write
one.
