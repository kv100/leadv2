# Two standing reds in the plugin suite — both are the test's fault, not the code's

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`** (the plugin repo). All edits
land there.

Both suites below are RED on plugin `main` (`717b16f`) with a clean tree and no lane involved.
They have been false-redding every lane that runs the full suite. Neither indicates a defect in
the code under test. Fix the tests, do not weaken them.

## R1 — `plugins/leadv2/scripts/tests/test-leadv2-route-bandit.sh:434-436` — leak guard fires on committed docs

```bash
local no_plugin_leak=1
if [[ -d "${SCRIPT_DIR}/../../docs/handoff" ]]; then
  no_plugin_leak=0
fi
```

`SCRIPT_DIR` is `plugins/leadv2/scripts/tests`, so the guard resolves to
`plugins/leadv2/docs/handoff`. That directory **exists and is tracked in git** — six mission docs
under `hermes-adopt/`, committed long before this test. The guard therefore reports a leak
unconditionally, on every machine, forever. Test 9 already reports `rd_exists=1`: the behaviour
under test (route-decisions written to the consuming-repo path) is correct; only the guard is wrong.

Fix: the guard must assert that **this test's own artifact** did not land in the plugin tree —
i.e. that `${SCRIPT_DIR}/../../docs/handoff/TEST-SELECT-03/route-decisions.yaml` does not exist —
not that the directory is absent. Keep it able to go red: prove it by creating that exact file
before the assertion, showing Test 9 RED, then removing it and showing it green.

## R2 — `plugins/leadv2/scripts/tests/test-leadv2-phase8-learn-counter.sh:282,299,316` — trailing-slash TMPDIR

```
expected unrelated='/var/folders/.../T//mw-fix-unrel.Y1SC6Z'
got      unrelated='/var/folders/.../T/mw-fix-unrel.Y1SC6Z'
```

The *expected* string carries the double slash; the *got* value is the normalised path. The
expectation is built by string-concatenating a `TMPDIR` that already ends in `/` (the macOS
default), while the value under test has been through `cd && pwd`. `main` and `wt` compare equal
in the same assertion because both sides of those went through the same normalisation; only
`unrelated` mixes a raw concatenation with a resolved path.

Fix: normalise both sides of the comparison the same way (resolve the expectation through
`cd … && pwd`, or strip the duplicate separator at the point the expectation is built). Do not
fix it by loosening the comparison to a substring or a glob.

## Constraints

- Test files only. Do not touch `leadv2-route-bandit.sh`, the phase-8 counter itself, or any
  non-test script — if you believe a production file must change, stop and say so instead.
- Every fix carries a red-before demonstration, pasted verbatim: the assertion failing for the
  intended reason, then passing after the fix.
- Run each full suite after the fix and paste its `Results: PASS=n FAIL=0` line.
- Do not add either suite to any known-failures registry.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4012b6c5" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.