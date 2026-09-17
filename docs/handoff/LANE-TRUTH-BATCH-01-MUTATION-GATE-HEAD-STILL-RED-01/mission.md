# LANE-TRUTH-BATCH-01-MUTATION-GATE-HEAD-STILL-RED-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## Scope: exactly one assertion

`plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh:172-176`. Everything else in this suite
passes. Measured on main, 400s ceiling, macOS: `rc=1 pass=15 fail=1` — three times on main and once
inside the lane worktree at its own HEAD `79d0986f`, identical every time. Persistent, not flaky,
and not sensitive to tree location.

Do not re-open the rest of the file. The E0 fixture fix (landed `cc386114`) already did its work:
this suite went 13/3 → 15/1 and its sibling `test-lane-verdict-three-states` went 3/14 → 18/0.

## The observed failure

```
[TEST] FAIL: Row 1 mutation gate HEAD must resolve stamped stream alive
  got: {"lane":"MUT-HEAD","verdict":"dead:no_log_artifact","age_s":null,"source":"handoff",
        "log_path":null,"raw_log_path":null,"pid":null,"pid_alive":null,
        "reason":"no_log_artifact", ...}
```

Two facts constrain the diagnosis, and they point in opposite directions — reconcile them before
you change anything:

1. The *immediately preceding* call at `:165`, `run_dispatch_liveness_gate "$head_dispatch" ''`,
   **passes**. Same dispatch handle, empty lane argument.
2. The *immediately following* case, "Row 1 mutation gate mutant: registry read does not treat
   pulse.md as live stream", **also passes**.

So the gate works for the unnamed lane and correctly rejects the mutant stream. Only the named
`MUT-HEAD` lane resolves to `dead:no_log_artifact` with `log_path: null` and `source: handoff`.

## What to determine first, before writing a fix

`no_log_artifact` with `source: handoff` is the gate saying: *I looked in the handoff location for
this lane's stream and there is nothing there.* That admits two very different causes, and they
need opposite fixes:

- **the fixture never stamps a stream artifact for the named lane** — a test-fixture defect; the
  production gate is right to call it dead, and the assertion is asserting something false;
- **the gate looks in the wrong place for a lane-named stream** — a production defect, and one that
  matters, because a live lane reported dead is exactly the failure class this repo keeps paying
  for (`hub_lane_liveness_verdicts`: liveness is three-valued, and a claim of death needs two
  independent signals).

Decide which, by *looking* — stamp the fixture, then list what is actually on disk at the path the
gate computes, and paste both. Do not infer it from the code alone. State the verdict in the report
in one sentence before proposing anything.

If it is the fixture, say so plainly and fix the fixture; a suite asserting a falsehood is not made
honest by bending the gate to satisfy it. If it is the gate, fix the gate and leave the assertion
untouched.

## Off limits

- Never make the suite green by deleting the assertion, loosening the grep, or adding `|| true`.
  If this case cannot be fixed honestly, leave it red and name the cause — that is an acceptable
  outcome for this row and a better one than a false green.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-active-registry.sh` — other lanes hold both.
- Do not widen into the other 15 passing cases.

## Controls

One independent claim here, so one negative control, RUN, output pasted: after the fix, mutate the
thing you changed (inside the function body, in the lane worktree, never a scratch copy) and confirm
this exact case goes red again. Assert the mutation target string is present before running, so the
control cannot rot into a permanent green against text that no longer exists.

If your verdict is "fixture defect", the control is the same shape: re-remove the stamping and
confirm the case returns to `dead:no_log_artifact`.

## Deliverable

`docs/handoff/LANE-TRUTH-BATCH-01-MUTATION-GATE-HEAD-STILL-RED-01/report.md` — the one-sentence
verdict (fixture vs gate) with the disk listing that proves it, before/after counts with their
boundary (pass/fail, ceiling, platform, commit), the control with pasted output, and — if it stays
red — the cause named precisely enough that the next person does not repeat this investigation.
