# Reviewer reads the spec — implementation report

## Decision

Shipped the smallest enforceable form of the proposal: the review engine resolves a lane mission (or accepts `--mission-file`), snapshots it before reviewer selection, passes that immutable content in every reviewer contract, and writes source, SHA-256, byte counts, and two independent verdict dimensions to `review-gate.md`.

The two dimensions are `correctness_verdict` and `mission_verdict`. `REVIEW_VERDICT` remains the aggregate terminal verdict, so existing callers retain their exit-code contract. A source-present review body lacking either new dimension is unreadable and cannot silently look mission-reviewed. A source-absent standalone invocation is explicitly recorded as `mission_verdict: UNAVAILABLE`; it is not claimed as a mission-alignment review.

The separate-plan / separate-implementer idea is valuable only if the plan is itself a versioned input to this same snapshot mechanism. It would add an authored planning phase, storage/provenance, and another review input; this lane deliberately does not implement it. Reviewer-vendor selection, capability numbering, and `router_v2.cost` are untouched.

## Measured input cost

Surface: `docs/handoff/dispatch-*/review.diff` paired with a same-handoff `lane-mission.md` or `MISSION.md`, in this leadv2 checkout.

```text
diff_bytes_min=0 median=22479 max=132191
mission_bytes_min=3781 median=19728 max=40573
total_bytes_min=4237 median=40573 max=172591
paired_review_inputs=34
```

The engine records the exact current-review `diff_bytes`, `mission_bytes`, and `review_input_bytes` in the terminal gate rather than assuming a fixed expansion. The new input is the immutable mission snapshot plus the already-present diff; the byte counts above are not token estimates.

## Discriminating negative control

The fixture runs three reviewer outcomes against the real engine. Its verdict text is:

```text
PASS: aligned has independent code=PASS mission=PASS verdicts
PASS: aligned receives and records the immutable mission snapshot with measured input bytes
PASS: wrong_task has independent code=PASS mission=FAIL verdicts
PASS: wrong_task receives and records the immutable mission snapshot with measured input bytes
PASS: broken has independent code=FAIL mission=PASS verdicts
PASS: broken receives and records the immutable mission snapshot with measured input bytes
review-mission-alignment: PASS=6 FAIL=0
```

Thus the correct-but-wrong-task failure and the broken-code failure both block, but their gate verdict dimensions are distinct. The fixture also changes the mutable mission source after the review starts and verifies that the review snapshot retains the original text.

The mutation-control artifact is [20260914T143242Z-72078.txt](mutation-control/20260914T143242Z-72078.txt). Its raw result is:

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-review-mission-alignment.sh file=plugins/leadv2/scripts/leadv2-review-run.sh
anchor=s/GATE_MISSION_VERDICT=FAIL/GATE_MISSION_VERDICT=PASS/
baseline_rc=0
mutated_rc=1
```

Its red line includes the mutant's contradictory gate text verbatim:

```text
FAIL: wrong_task rc=7 expected=7 ... correctness_verdict: PASS mission_verdict: PASS status: fail ...
```

That is the required red control: changing the gate assignment makes the new suite fail. The unmutated suite is green above.

## Evidence

### Shell syntax — raw output

```text
bash-n-engine-rc=0
bash-n-suite-rc=0
```

### Changed-scope selection — raw output

```text
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e1b5b1c34da1/plugins/leadv2/scripts/tests/test-review-mission-alignment.sh
run-all: 38 selected, scope=changed, select_only=1
```

### Changed-scope runner — terminal raw output

```text
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e1b5b1c34da1/plugins/leadv2/scripts/tests/test-review-mission-alignment.sh
run-all: 12 passed, 26 failed, 0 known-red (allow-listed, non-blocking), 3 known-red-skipped (budget mode, still run by --scope all), 0 gone-green (remove from allow-list), scope=changed
```

The changed-scope runner is red in this sandbox. Its raw failures repeatedly begin with `mktemp: mkdtemp failed on /var/folders/...: Operation not permitted`; the new suite itself passed in that run. This report does not treat the broad runner as green.
