# EPHEMERAL-BASENAME-COLLISION-01 report

## Outcome

Scratch repositories now resolve ephemeral state as
`<state-base>/.ephemeral/<basename>-<8-hex-path-digest>`. The implementation
is in `1d8dbee8`. A pre-hash bare-basename root is adopted only when its
`.ephemeral` or `.repo-root` provenance names the exact resolving repository;
foreign same-basename residue is left untouched for state purge. This avoids
silently moving a live lane owned by another checkout.

The follow-up commit `94448c31` repairs the suite's rotted negative control:
both fixtures now use the same description and therefore the same stable
dispatch signature. The old control used distinct descriptions, so it could
not exercise the historical signature collision.

## Reproduced collision and negative control

The control counts the exact resolver assignment anchor before replacing it in
a throwaway copy. Fixture A writes a stale row; fixture B resolves the same
`active.yaml` only in the bare-basename mutant. The canonical helper also ran
the real suite against that single-source mutation and recorded a nonzero
mutated result in `mutation-control/20260912T222942Z-68093.txt`.

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-ephemeral-state-basename-collision.sh file=plugins/leadv2/scripts/leadv2-state-path.sh red_line=[TEST] FAIL: same-basename fixtures share a root -- a='.../.ephemeral/repo-collide/active.yaml' b='.../.ephemeral/repo-collide/active.yaml' diff_hash=2b3d60205c2dfbcfdfeba6e94355341b387c5762e6b2cbd8feb4873ddb2808dd lane_diff_hash=fe7a9839f484fae3697e18fb075a6dc11821305e0c5618db176747a24f33c804
```

## Green regression proof

```text
[TEST] PASS: fixture B (same basename, dirty machine) dispatches with no writeset refusal
[TEST] PASS: fixture A and B exercise the same stable dispatch signature (825c294b)
[TEST] PASS: fixture B registered under its OWN hashed root (dispatch-825c294b)
[TEST] PASS: fixture A's row is invisible to fixture B
[TEST] PASS: foreign-source legacy root kept, never adopted (residue stays dead)
[TEST] PASS: matching-source legacy root is adopted into the hashed root
[TEST] PASS: (red) bare-basename keying reproduces the stale-row collision (.../.ephemeral/repo-collide/active.yaml)
[TEST] PASS: no fixture-named root appeared in the live .../.claude/leadv2-state/.ephemeral
ephemeral-basename-collision: 15 pass, 0 fail
ALL PASS
```

`bash -n plugins/leadv2/scripts/tests/test-ephemeral-state-basename-collision.sh` also passed before that run.

## Diff stat

```text
 plugins/leadv2/scripts/leadv2-state-path.sh        | 107 ++++++--
 .../test-ephemeral-state-basename-collision.sh     | 295 +++++++++++++++++++++
 2 files changed, 374 insertions(+), 28 deletions(-)
```

## Guarding-suite results

The dedicated collision suite is green at 15/0. The two additionally requested
guarding suites did not meet their stated baselines in this checkout, so this
lane is not claiming a full green closure:

```text
test-route-arbiter.sh: SUMMARY: pass=28 fail=4
test-dispatch-refuses-a-dead-premise.sh: 38 passed, 8 failed
```

The observed failures are in dispatcher fixture routing/premise execution
(`foreign project root` / `candidate_chain`), not in the collision suite.
This lane did not modify `leadv2-dispatch-code.sh` or the arbiter library;
the failures are recorded rather than masked or allow-listed.

## Changed-scope runner

The canonical runner was executed in the foreground with an explicit 600s
bound. Its raw terminal result was:

```text
suite-discovery: [UNTRACKED-SKIP] 232 suite file(s) refused: not tracked by git (stage or commit to admit; run directly while authoring) — GATE-DISCOVERS-246-UNTRACKED-SUITES-01
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit=124 (timeout after 600s; no further output)
```

It is an environmental non-green result, not evidence of a passing changed
scope. No background process remained after the timeout.
