# ARBITER-ESTIMATES-BLIND-AND-NEVER-LEARNS-01 — round 1: give the arbiter an outcome record

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.** Workers died today with work uncommitted; the lead had to salvage.
- The suite path is `tests/run-all.sh` at the repo **ROOT**. `plugins/leadv2/scripts/tests/run-all.sh`
  does not exist; a round claiming to have run it has run nothing.

**Class:** Standard. **Repo:** leadv2 plugin. Design context (read first, do not re-derive):
`docs/handoff/SELECTOR-DESIGN-01/design.md`.

## The defect, measured 2026-09-02

The arbiter picks an arm with `reason=cheapest_capable`. **"Capable" is an assertion, never a
measurement.** `leadv2-route-bandit.sh` reads `route-outcomes.jsonl`; **nothing anywhere writes that
file and it does not exist on disk.** The bandit has therefore never received a single observation
since it was built. The arbiter cannot learn that an arm failed, because no one records that it did.

Same day, same machine, three consecutive dispatches of one lane: a round requiring an audit of a
five-week-old hook copy and a decision about GitHub runner economics (macOS = 10× minutes) was
scored `complexity=simple duration_class=short` and handed to the cheapest arm, three times. It
produced zero commits in 30 minutes on the first attempt. **Nothing recorded that outcome**, so the
fourth dispatch would score it identically.

## Scope of THIS round — the writer only

Do not turn on `LEADV2_ROUTER_V2`, do not change the estimator's inputs, do not touch the bandit's
selection maths. Those are separate rounds and they are worthless until data exists. This round
makes the data exist.

## Deliver

1. **An outcome writer.** Every dispatch that reaches a terminal state appends one row to
   `route-outcomes.jsonl` (path as the bandit already expects it — read the bandit, do not invent a
   path). Find the single place where a dispatch's terminal state is already known — the dispatcher
   already journals `terminal=win`, `worker_died_stale`, `product_close`, and
   `model_select_telemetry`. Write from there. **One writer, one call site.** If you find yourself
   adding a second, stop and say why in the report.
2. **The row must carry what a later decision needs**, at minimum: arm and model; declared class and
   the arbiter's own `complexity`/`duration_class`; work kind; round number for that task; terminal
   cause; whether the round produced commits; wall time from spawn to terminal. Justify anything you
   add or omit — a field nobody will read is a field that rots.
3. **Read it back.** A small command that reports, per arm: rounds attempted, rounds that produced
   commits, median wall time. This is the artifact that turns "capable" from a claim into a number.
   Show its output on the rows your own proof run generates.
4. **Failure must be recorded, not just success.** A worker that dies stale, a refusal, an
   `all_arms_capped` — each writes a row. An outcome log that only holds wins teaches the arbiter
   that every arm always works, which is worse than no log at all. State in the report which
   terminal states you covered and how you enumerated them (do not guess the list — grep the
   dispatcher for what it actually emits).
5. **Bounded growth.** Say how the file is kept from growing without limit, and pick the mechanism
   from a measured row size, not a round number.

## Prove it
- Run a real dispatch to a terminal state → paste the row it wrote.
- Force a failing terminal state (kill the worker mid-round) → paste the row. Both must exist.
- Run the read-back command on those rows → paste its output.
- **Negative control:** remove the writer call in a mktemp FULL copy of the tree whose baseline is
  proven green → the "a terminal dispatch writes a row" check must go red. Paste baseline and mutant
  runs. Insert the mutation INSIDE the function body; a top-level insert makes every suite red for
  the wrong reason and reads as a pass.
- `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND, `timeout 1800`. Paste the real
  tail. A placeholder token where run output belongs fails this round outright.
- `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Explicitly NOT wanted
A `--arm` flag or any manual arm override. The arbiter is supposed to decide; a lead-side override
becomes the default path within a week. We already have that evidence in our own data: 29% of
dispatches attested their way past the phase gate with `--reason` rather than passing it.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main`
merged.

## Done when
A terminal dispatch provably writes a row, a failed one provably writes a row too, the read-back
command prints per-arm numbers from those rows, the negative control is red against a green
baseline, and the report names every terminal state covered with the grep that enumerated them.
