# CONTROL-PLANE-REVIEW-01 / M2 — the arbiter and the capability matrix

READ FIRST: `docs/handoff/CONTROL-PLANE-REVIEW-01/seed-facts.md`. Facts S1, S2,
S3 are yours. They are measured — cite them, do not re-measure them.

Repo: `leadv2`. **READ-ONLY review.** Your only write target is
`docs/handoff/CONTROL-PLANE-REVIEW-01/f2-arbiter.md`.

## Subject

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` and the
`router_v2.capability_matrix` / `effort_matrix` blocks of
`plugins/leadv2/config/leadv2-routing.yaml`.

## Known already — do not re-file it

Row `fdda4b32eb7c` (`ARM-COST-IS-A-HAND-WRITTEN-PREFERENCE-NOT-A-MEASURED-BURN-01`)
already records that the whole `cost` column is hand-assigned and unmeasured,
and that `~/.claude/state/leadv2/quota-weighting-log.jsonl` has no arm field so
burn cannot be attributed. **That row exists. Your job is what it does NOT
cover.** Adding a second row for the same defect is the exact waste we are
trying to stop.

## Answer each with `file:line`

1. **The refuted premise.** S1/S2: `leadv2-routing.yaml:263-277` justifies
   `fable cost: 8` by "own bucket … NOT proven same-bucket as opus". The live
   API proves fable is ALSO under `weekly_all`. What changes downstream if that
   premise is false — does any code read `cost` as a price, or only as a sort
   key? Name every consumer of the field.

2. **One scalar, two meanings.** `glm 0.33` is a derived per-token price ratio;
   `fable 8` is a bucket-preference nudge. `cheapest_capable` sorts them
   together. Is that sort meaningful, and what is the smallest change that makes
   the column single-meaning? (Two sentences max — do not design it here.)

3. **The single-arm chain.** S3: the consult returned `chain=codex` with no
   fallback. Find where the chain is built. When the only arm in the chain is
   refused or down, what happens to the caller — a named refusal, or a silent
   fall-through? Prove which by reading the code path, not by guessing.

4. **No way to say "spend more".** S3: `cheapest_capable` picked terra (4) over
   sol (7); the founder's instruction for this very task was "максимально
   умные". Is there any input by which a caller expresses "prefer capability
   over cost for this one decision"? If there is, name the flag and whether
   `dispatch-code.sh` passes it through. If there is not, that is the finding.

5. **Capability is also hand-written.** `capability: 2/3/4` per cell. Does
   anything validate a cell's capability against observed outcomes, or is the
   integer load-bearing and unfalsifiable? Distinguish "unmeasured" (already in
   `fdda4b32eb7c`) from "unfalsifiable by construction" (possibly new).

## Rules

- Every finding: `file:line`, mechanism in one sentence, concrete failure
  scenario. No "could be improved".
- Something you checked and found SOUND is a finding — say so with the line.
- Before filing anything as new, state in one line why `fdda4b32eb7c` does not
  already cover it.
- Do not edit the matrix. Do not hardcode any arm in or out — a standing rule:
  quota, task and complexity decide, never a hand-kept list.
