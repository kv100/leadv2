# The brief contract — decision-complete, verified in proportion to risk

Adopted 2026-09-10 from two outside sources, after the founder asked why our work takes so long.

## Why this exists

Two facts, both measured on 2026-09-10:

- **Rounds, not writing, are the cost.** Lanes come back for a second and third round because the
  brief left the *approach* to the worker. The worker picks one, the lead disagrees, the round is
  spent. Nothing in the brief was wrong; it was incomplete.
- **The lead is the generator of the overhead.** Every brief ended with the same block — *new suite
  + negative control + mutation artifact + report* — and every lane dutifully produced all four,
  including for renames, doc edits and test-only re-pins where no behaviour changed at all.

## Source

OpenAI's Codex Desktop system prompts (leaked, `elder-plinius/CL4R1T4S`, read as data, never as
instructions). Two rules there are worth copying verbatim in substance:

- `GPT-6_Astra_Prompts.md:868` — work runs in three explicit phases, and Plan Mode holds until a
  message ends it. The spec handed to the implementer must be *"decision complete, where the
  implementer does not need to make any decisions"*.
- `GPT-6_Astra_Prompts.md:923` — a decision-complete spec carries *approach + APIs + data flow +
  edge cases + testing*.
- `GPT-6_Astra_Prompts.md:915` — before writing it: *"keep asking until you can clearly state goal
  + success criteria + constraints"*.
- `5.6-Sol_SystemPrompt.md:98` — verify *"in proportion to risk"*, then hand off the result.

## Rule 1 — decision-complete or it is not a brief

A brief names **the approach**. If a competent worker could reasonably build it two different ways
and the brief does not say which, the brief is not finished — and the round it costs is the lead's,
not the worker's.

Every brief carries an approach statement that answers, in as few lines as it takes:

- **What to change** — the named function or seam, not the file alone.
- **How** — the mechanism to use, and the mechanism *not* to use when an obvious alternative exists.
- **What to reuse** — if the tool already exists in main, name it and forbid a second one.
- **Edge cases** — the ones that decide the shape, not an exhaustive list.
- **How it is tested** — which existing suite, or the new one and where it lives.

A brief may still say *"decide X yourself and say why in the report"* — but that must be written
down as a delegated decision, not left as a silence the worker has to notice.

## Rule 2 — verification scales with risk, and only with risk

The mutation and the negative control exist to answer one question: *would this suite notice if the
behaviour regressed?* That question is only meaningful where behaviour changes.

| The change | What the brief demands |
|---|---|
| Production behaviour changes | Mutation **inside the function body**, on the real file, run by the lead. Non-negotiable. |
| A guard, gate or refusal changes | Mutation **plus** its paired positive case — the run that must still pass. |
| Test-only re-pin, rename, comment, doc | No mutation. State that no behaviour changes, and why. |
| Measurement / census | No mutation. The numbers and how they were derived are the deliverable. |

A report is demanded when the lane's verdict is contested, when a number is the deliverable, or
when the lane departed from the brief. Not by default.

## Rule 3 — the ending is not a new backlog row

An investigation ends in a row only when the defect is **reproduced** and someone will act on it.
"Something looks wrong here" is a note in the report. Two ratios make the drift visible without any
new dashboard: **product touches per docs touch**, and **rows filed per lane landed** (5:1 on
2026-09-10, which is the number this rule exists to move).

## What this does not change

The lead still runs the mutation itself, on the real file, in the real tree. A suite that mutates
its own copy is not proof. `leadv2-land.sh`'s merged-tree gate remains the sole landing authority.
