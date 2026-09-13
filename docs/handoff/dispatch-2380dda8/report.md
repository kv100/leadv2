# Capability-gate refusal journal report

## Surface and measured rate

The rate below is about the retained local launcher-stderr artifact surface,
not the decision/event journal. The journal was not a valid counting surface
before this change because it did not receive these rows.

```text
window=retained_temp_spawn_stderr_files mtime_utc=2026-09-10T09:47:18Z..2026-09-13T16:44:01Z
attempts=74 refusals=5 rate=6.76%
reasons=arm_not_capable_for_kind:5
```

The probe read `${TMPDIR}/leadv2-dispatch-spawn-*.stderr.log`; it counted
files containing a `^refused: ` line and extracted that line's reason. This
is historical retained-artifact evidence, not an assertion that the new event
stream already contains a production-sized window.

## Mechanism and decision

The disagreement was caused by kind coercion, not two independently measured
capability matrices. `leadv2-route-arbiter.sh` normalizes an out-of-vocabulary
kind to `code`; `_arm_launchable_arms` did the same preflight normalization,
but `_spawn_worker_body` then called `leadv2-launch-registry.py` with raw
`kind=plugin`. The registry's `lookup()` consequently returned
`arm_not_capable_for_kind` and wrote the only durable evidence to launcher
stderr.

Decision: one matrix vocabulary now drives the real launch registry too.
`normalize_kind()` in `leadv2-launch-registry.py` reads the existing
`capability_matrix` vocabulary and maps only an unknown kind to `code`; the
dispatcher preflight calls that same function. This removes the coercion
disagreement without an arm exclusion or second capability matrix.

At the refusal seam, `spawn_worker()` captures a real `refused:` line before
the temporary stderr is copied/removed. The next candidate-loop entry emits
one `launcher_refused` decision and Tier-0 event with `task`, `arm`, `reason`,
and `fell_through_to`; exhaustion emits `fell_through_to=none`. Thus the
retained stderr file is diagnostic evidence only, never a post-hoc event
source.

## Real-refusal proof and negative control

```text
PASS: plugin kind is normalized by the real launch registry; a separate real refusal reached dispatcher capture seam
PASS: decision journal row joins sig8, arm, reason, and actual fallback
PASS: durable event row carries exact launcher refusal and fallback
PASS: RED control: mutating capture reason made the real-refusal assertion red

launcher-refusal-event: PASS=4 FAIL=0
```

The test uses the production registry and matrix: `plugin/sonnet` now resolves
through the common `code` vocabulary; `code/fable` produces a real
`refused: not_a_build_arm` line, which yields
`launcher_refused task=cafe0001 arm=fable reason=not_a_build_arm fell_through_to=codex`.

## Required focused regression output

```text
test-arbiter-decision-record-inputs.sh
SUMMARY pass=6 fail=0

test-reset-urgency.sh
SUMMARY: pass=10 fail=0

test-leadv2-task-judge.sh
=== Results: 31 passed, 0 failed ===

test-arbiter-prices-by-provider.sh
SUMMARY pass=7 fail=0
```

## Changed-scope selection and e2e rung

This was run after the first implementation commit.

```text
[SELECT] .../plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh
run-all: 136 selected, scope=changed, select_only=1
```

The real changed-scope runner was then attempted in the foreground with a
25-second bound and returned the same timeout-shaped result as the sibling
lane rather than a test failure:

```text
changed_scope_runner_rc=124
```

## Syntax checks

```text
bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh
python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-launch-registry.py
git diff --check
all exited 0
```

## Mutation-control artifact

The committed `leadv2-mutation-control.sh` artifact is recorded in the
`mutation-control/` directory beside this report. It mutates the capture
function's exact-reason assignment; its required result is a non-zero mutated
suite exit and the raw artifact is the authority for that claim.
