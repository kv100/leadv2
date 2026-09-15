# LANE-WRITES-SCOPING-SUITE-RED-ON-MAIN-01

Carve-out of `MAIN-RED-SUITES-BLOCK-EVERY-LANE-01`, taken because this one suite is the measured
blocker of a queued row. All writes in **`~/Projects/leadv2`**. The only production-ish file you
may write is `plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh`.

## The defect
`plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh` is **red on unmodified `main`**.

Because it is red on main, the review gate's falsifiability check returns `could_not_determine`
for every lane whose diff maps to it, and the gate answers
`blocked: suite_falsifiability_undetermined`. The lane's own work is then never judged. That is
what is currently holding `PLUGIN-PREPASS-PHANTOM-DESIGN-01`.

### Paired measurement already taken by the lead, 2026-09-15
The suite was run in **main** and in a **lane worktree** at a 900s bound. Both runs produced the
**same 16 failures, with identical names**:

```
C1-codex  C1-glm  C1-sonnet  C2-b  C3  H5  M7  L11   (×2 each)
```

Identical in both trees ⇒ the failure is **pre-existing on main**, not caused by any lane's diff.
An earlier 3-vs-6 comparison was an artifact of a 240s timeout cutting both runs short; do not
reuse that number, it is void.

Re-run the suite on unmodified main yourself first and paste that red output. A suite that was
already green cannot be the evidence that this round fixed anything — and a measurement you did
not take is not yours.

## Step 1 — classify before you touch anything
For **each** of the named failures, state its cause class and say which one it is with `file:line`:

- `never_reaches_subject` — the check refuses at a gate added after the suite was written and
  reports that refusal as a failure. Two sibling suites in this repo had exactly this
  (`test-dispatch-architect-prepass-late-artifact.sh`,
  `test-dispatch-architect-prepass-orphan-timeout.sh`, fixed in `62e7a253` by passing the audited
  `--no-probe-yet` escape hatch). Use them as the worked example.
- `real_regression` — the subject genuinely broke. Name it. **Do not fix it here** if the fix is
  not small and obviously correct; report it as a new row instead.
- `environment_dependent` — passes alone, fails under the runner, or is Linux-only. Name the
  specific difference; "flaky" is not a cause.
- `rc_127` — three causes wear this one code (missing file, missing interpreter, cwd-relative
  path). Say which. Never report it as a test failure.
- `timeout` — its own verdict, neither pass nor fail. State the bound you used.

Several failures may share one cause. If so, say so explicitly and name the group — that is
honest, and it changes how many controls you owe (see below).

State the classification **before** any fix appears in the diff.

## Step 2 — fix only what the classification justifies
The deliverable is a **correct verdict per check**, not greenness.

- A check that never reached its subject must reach it, and you must show its assertions actually
  firing — not merely that `rc` became 0.
- A check that is genuinely environment-dependent must **declare that in the suite itself**, with
  the difference named, so the falsifiability check stops treating it as undetermined.
- A check whose subject is genuinely broken stays red and is named in the report as still-red,
  with its cause and a proposed row title.

## Hard prohibition
**Do not weaken or delete a check to make it green.** Deleting an assertion, loosening a grep,
widening a pattern, or wrapping anything in `|| true` converts a false red into a false green,
which is strictly worse than what we have now. `2>/dev/null` hides an error so that it reads
exactly like success — distrust it wherever it already appears here.

If you cannot fix a check honestly, leave it red and say so. That is a passing outcome for this
row.

## Acceptance
- The pre-fix RED output from unmodified main, with the failure count and its boundary: how many
  checks the suite contains, how many ran, how many failed, on which platform.
- The classification table: every named failure, its cause class, its `file:line`.
- Per changed check: the paired before/after (`rc` **and** reason before, `rc` after) plus proof
  the assertions now fire.
- The after count stated with the **same boundary** as the before count.

## Negative controls — RUN them
One control per **independent cause**, not one per check. If you fixed six checks through one
shared cause, one control for that cause is honest — name the group. If you fixed two distinct
causes, you owe two controls.

For each: restore the broken condition, show the suite go RED, restore, show it green. Paste every
red/green pair. A mutation anchor that does not match must fail loudly — an unmatched anchor is a
test failure, never a silent skip, and an anchor bound to exact source bytes rots into a permanent
green the moment the line is reformatted.

## Off limits
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — another lane owns it right now. If a check is
  red because of a real defect in that file, **report it, do not fix it**.
- `leadv2-review-run.sh`, `leadv2-active-registry.sh` — other lanes own them.
- Do not change the falsifiability check itself. This row makes one suite honest; it does not
  relax the gate.
- Do not touch any other suite file.

## Report
`docs/handoff/LANE-WRITES-SCOPING-SUITE-RED-ON-MAIN-01/report.md`: pre-fix RED first, then the
classification table, then per-check fix + controls, then the before/after count with its
boundary. End with `DELIVERABLE_COMPLETE`.
