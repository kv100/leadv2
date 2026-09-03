# REVIEW-GATE-IS-MUTE-01 — the gate says "no work" about finished, committed work

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run.

**Class:** Standard. **Repo:** leadv2 plugin. Owner file: `plugins/leadv2/scripts/leadv2-review-run.sh`.

## Why this is now the highest-leverage task in the repo

On 2026-09-02 five lanes were merged. **Every single one was merged because the lead ran its suites
by hand and merged personally.** In each case the gate had already reported:

```
status: blocked
reason: no_work
worker_reason: {type:system,subtype:hook_response,hook_id:...,hook_name:SessionStart:startup,...}
```

— about lanes carrying real commits, a written report, and `DELIVERABLE_COMPLETE`. Three separate
witnesses on `CI-RUNS-THE-SUITES-01` alone, hours apart.

So the throughput gain of that evening was **not** a system improvement: the lead was personally
doing the gate's job. That does not scale, and it is dangerous — had the lead believed `no_work`,
five finished pieces of work would have been thrown away and redone.

Two visible symptoms, and you must decide whether they are one bug or two:
1. `reason: no_work` while the lane's diff is non-empty.
2. `worker_reason` carries a **SessionStart hook response** — a hook's JSON, captured where the
   worker's own terminal reason belongs. That strongly suggests the gate is reading the first
   thing on a stream rather than the worker's result, and a hook firing at session start wins the
   race.

## Deliver

1. **Reproduce it first, and paste the reproduction, before changing anything.** Point the gate at
   a lane worktree with committed work — the merged lanes are on `main` now, so construct the case
   in a scratch worktree. If you cannot reproduce it, stop and say so; do not fix a bug you have
   not seen.
2. **`no_work` must mean no work.** Whatever the gate uses to decide "is there a diff", make it
   answer from the lane's committed range, not from a stream that a hook can poison. Name the
   decision site and what it reads now versus after.
3. **A hook response is never a worker verdict.** If the stream can carry hook JSON where a result
   belongs, the reader must reject it by shape, not by hoping it does not appear. Say how you
   distinguish them.
4. **A blocked verdict must name evidence.** When the gate refuses, its `reason` should be
   falsifiable by a command the reader can run — "0 files changed in `<base>..<head>`" beats
   `no_work`. A verdict nobody can check is how five finished lanes nearly got redone.

## Prove it
- The reproduction, pasted, before the fix.
- A lane with committed work → the gate reviews it instead of returning `no_work`. Paste it.
- A lane with genuinely no diff → still `no_work`, and the reason names the empty range. Paste it.
- A hook response injected into the stream → the gate ignores it and still reads the worker's real
  terminal state. Paste it.
- **Negative control:** restore the old read in a mktemp FULL copy whose baseline is proven green →
  the committed-work case returns `no_work` again. Paste baseline and mutant runs. Insert the
  mutation INSIDE the function body.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.

## Out of scope
The review round cap, reviewer arm selection, the e2e gate. This round is about the gate reporting
`no_work` for work that exists.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.

## Done when
The `no_work`-on-real-work case is reproduced and then fixed with both runs pasted; an empty lane
still refuses and names the empty range; an injected hook response cannot become a verdict; the
negative control reproduces the old behaviour against a green baseline.
