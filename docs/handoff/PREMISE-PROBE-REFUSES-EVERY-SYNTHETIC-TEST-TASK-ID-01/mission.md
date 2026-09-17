# PREMISE-PROBE-REFUSES-EVERY-SYNTHETIC-TEST-TASK-ID-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## Five red suites, one observed cause

`_premise_probe_gate` in `plugins/leadv2/scripts/leadv2-dispatch-code.sh:8453-8454` (called at
`:9141`) refuses a dispatch whose task id has no matching row in `docs/tasks.yaml`:

```
[leadv2-dispatch-code] premise_probe task=<id> verdict=refused reason=backlog_row_not_found
[leadv2-dispatch-code] ERROR: premise refused: reason=backlog_row_not_found ... -- exit 8
```

Every suite below dispatches with a **synthetic** task id and seeds no backlog row, so dispatch
exits 8 **before the mechanism under test ever runs**. Cause class: `never_reaches_subject`.

| suite | observed | evidence |
|---|---|---|
| `test-routing-enforcement-p1.sh` | rc=1, PASS=3 FAIL=15 | refusal quoted in the failure output |
| `test-phase-precondition.sh` | rc=1, pass=72 fail=10 | `G2 should exit 3 (got 8)`, `G3 should exit 0 (got 8)`, G11a quotes the refusal |
| `test-glm-deferred-ladder.sh` | rc=1, 6 PASS / 10 FAIL lines | `(f) retry-all ... rc=8 ... reason=backlog_row_not_found task=27aa4766` |
| `test-dispatch-arm-vocabulary.sh` | rc=1, PASS=8 FAIL=2 | call order: `:9141` precedes `resolve_arm` (`:9847`,`:10698`) and `DC_TASK_CLASS=` (`:9820`) |
| `test-claim-evidence-gate.sh` | rc=1, 24 passed / 1 failed | **INFERRED, NOT CONFIRMED** — see below |

**`test-claim-evidence-gate.sh` is not confirmed.** It redirects the dispatcher's stdout and
stderr to `/dev/null`, so the refusal could not be observed; only the shape matches. Start this
lane by removing that redirect locally and *looking*. If the cause turns out to be different, say
so and treat it as its own failure — do not fold it into the group to make the count tidier.

## The knot this sits inside — read before choosing a fix

There is already a filed row, `NO-PROBE-YET-MEANS-TWO-DIFFERENT-THINGS-01`, about the same seam:
`task-add.sh --no-probe-yet` stamps `needs_acceptance_probe=true`, while the dispatch gate honours
its own identically-named flag **only when no backlog row was found** (`:8366-8373`). A row that
exists without a probe takes the `no_premise_probe` branch at `:8438`, whose remedy text lists
three fixes and not the flag.

So there are two candidate fixes and they are not equivalent:

- **Fix the fixtures** — each suite seeds a backlog row, or passes the flag that genuinely
  bypasses the gate for a synthetic id. Narrow, no production risk, but five fixtures to touch.
- **Fix the gate** — give the dispatcher an explicit, documented way to run against a synthetic
  id (a test-mode contract), so no fixture has to imitate a backlog row. Wider blast radius: this
  file is the dispatcher every lane on the board runs through.

Choose one, state which and why in the report, and say what you rejected. If you touch the gate,
the change must be additive: **no existing refusal may become permissive for a real dispatch.**

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A suite that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do not weaken `_premise_probe_gate` for real dispatches. It is the gate that stops work being
  started on a premise nobody checked.
- `test-report-only-gate.sh` and `test-t13-slice2.sh` are NOT in this lane. Other lanes own them.

## Controls

Two independent claims at minimum — the gate/fixture change, and the "no real dispatch became
permissive" claim — so **two** negative controls, each run, both outputs pasted. If you fix the
fixtures rather than the gate, the second control is: re-remove one fixture's seeding and confirm
that suite goes red again. Apply each mutation inside the function body **in the lane worktree**,
never a scratch copy — this suite family was measured to behave differently in a detached
worktree at the same commit. Assert the mutation target exists before running.

## Deliverable

`docs/handoff/PREMISE-PROBE-REFUSES-EVERY-SYNTHETIC-TEST-TASK-ID-01/report.md` — per-suite
before/after counts with their boundary (counts, ceiling, platform, commit), the chosen fix with
the rejected alternative named, the verdict on `test-claim-evidence-gate.sh` once observed, both
controls with pasted output, and any suite left red with its cause.
