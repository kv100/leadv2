# SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01

Backlog row `bd9c35163b33` (P0). Primary writes in **`~/Projects/leadv2`**:
`plugins/leadv2/hooks/leadv2-model-inherit-guard.sh` and the spawn-arbiter-gate hook beside it.

## The defect
Two hooks contradict each other, so no spelling of a bare `Agent` spawn passes:

- `leadv2-spawn-arbiter-gate` demands the spawn carry the arbiter's decided model, **or** no model.
- `leadv2-model-inherit-guard` denies a built-in `subagent_type` with **no** `model=`.
- For `kind=recon` the arbiter answers `arm=freepool model=freepool-default` — a value the `Agent`
  tool cannot accept at all, since its model enum is `sonnet|opus|haiku|fable`.

Reproduced 2026-09-10, three attempts: `model=haiku` → arbiter gate DENIED (no decision on record
for that model); no model → model-guard DENY; the recorded decision names a model the tool refuses.

Two guards that are each individually correct compose into a gate nothing can pass. A guard
verified in isolation is not verified in composition — that is the shape here, and the fix must be
verified in composition too.

## First — reproduce, then measure the real intersection
1. Reproduce all three refusals and paste them. Do not fix what you have not reproduced; the row
   is five days old and one of the two hooks may have moved.
2. Then answer, by reading the code, not by guessing: **what is the set of spawn spellings that
   both hooks accept simultaneously?** If it is empty, say so and show why. If it is non-empty, the
   defect is a documentation/UX failure rather than a deadlock, and that is a different fix —
   report which one you found before changing anything.

Note for the reproduction: at least one spawn in this repo has since succeeded with
`subagent_type=recon, model=haiku`. Either that path bypasses a hook, or the hooks' behaviour
differs for a *defined* agent type versus a *built-in* one. Establish which before you fix — a
fix aimed at the wrong branch is a wasted round.

## The fix must not weaken either guard's purpose
- The model-inherit guard exists so a built-in `Explore`/`general-purpose` cannot silently inherit
  an Opus caller's model and run a whole fan-out on Opus. Keep that.
- The arbiter gate exists so the lead cannot bypass routing by hand-picking an arm. Keep that.
- **Never hardcode an arm out of routing.** If `freepool` cannot be expressed to the `Agent` tool,
  the answer is a translation at the boundary (arbiter arm → tool-acceptable model), not a
  hand-kept exclusion list. Quota, task and complexity decide — not a literal.

State the mechanism you chose in one sentence before the diff.

## Acceptance
- A bare spawn of a built-in type succeeds under both hooks live, with the arbiter's decision
  honoured and recorded. Paste the spawn and the journal line proving which arm was decided.
- A spawn that genuinely should be refused is still refused — name the case and show it.
  A deadlock fixed by opening the gate to everything is the same bug with the sign flipped.
- The composition is tested: a test that exercises **both hooks in sequence**, the way a real
  spawn hits them. Two separate single-hook tests do not cover this defect.

## Negative controls — one per independent property, both RUN
1. Revert the boundary translation and show the deadlock test go RED.
2. Remove the still-refused case's check and show the refusal test go RED.
Paste both red/green pairs. One mutation is not a control for two properties.

## Off limits
- The route arbiter's decision logic, the capability matrix and the cost ordering — untouched.
  This row is the hook boundary only.
- `.claude/hooks/leadv2-glm-first-agent-gate.sh` in persona-engine is a **real file, not a
  symlink** — a repo-local override. Do not edit it from this lane. If the fix requires touching
  it, say so in the report and stop; that is a founder decision about shared vs per-repo, not
  yours.
- Do not edit any shared tree outside `~/Projects/leadv2/plugins/leadv2/hooks/`.

## Report
`docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/report.md`: the three reproductions, the
intersection finding, the chosen mechanism, the composition test, both controls. End with
`DELIVERABLE_COMPLETE`.
