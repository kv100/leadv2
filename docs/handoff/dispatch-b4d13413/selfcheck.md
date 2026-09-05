# builder selfcheck — dispatch-b4d13413
generated_at: 2026-09-02T10:27:10Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01
diff_hash: 16c36eb5dab77a9515fe6207d327efb08fa0300df5d9df2d742c0467f86f278e
checks: 3   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-brain-class-live.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-brain-class-live.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-brain-class-live.sh (falsification proof) (rc=1)
PASS: (a) light+risk mission escalates to Standard|Heavy, journaled
PASS: (a) brain.yaml class_source=escalated
PASS: (b) trivial-but-declared-Heavy holds the floor, journaled
PASS: (b) final class stays Heavy
FAIL: (c) missing declared_fallback: [leadv2-dispatch-code] task_class=Standard route=phases source=classifier_error task=brainC01
[leadv2-dispatch-code] brain_decision task=brainC01 class=Standard class_source=declared_fallback phases=classify,plan,gate1,build,test,review,live_verify,close reason=judge_unavailable
CLASS=Standard SOURCE=classifier_error
PASS: (c) dispatch proceeds with declared class, no refusal
PASS: (c2) judge failure + declared=Heavy floors admission class at Heavy
PASS: (c2) brain.yaml records class: Heavy under judge-fail floor
PASS: (c3) judge failure + declared=Strategic floors admission class at Strategic
PASS: (c3) brain.yaml records class: Strategic under judge-fail floor
PASS: (c4) judge failure + declared=Light never lowers below Standard
PASS: (c5-up) judge success escalates over a lower declared class
PASS: (c5-down) declared floor holds Heavy over a lower judge-computed class
PASS: (d) brain_decision line names class=Heavy
PASS: (d) brain.yaml class: Heavy
PASS: (d) re-entry guard floor RETURNS class=Heavy (the routed value, on stdout alone) over a lower base class
PASS: (e) brain_decision reaches stderr with JOURNAL_TASK unset
PASS: MUTATION (e) killed: re-adding 2>/dev/null drops brain_decision from stderr
PASS: MUTATION (d-re-entry) killed: decision line still says Heavy (stderr='[leadv2-dispatch-code] phase_class_floor task=brainD301 source=brain_record class=Heavy') but the stdout-only assertion correctly rejects the stale return value ('Light')
PASS: (a) baseline: unmutated full copy escalates, matching the tracked file
PASS: (d) baseline: unmutated full copy writes brain.yaml, matching the tracked file
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
PASS: MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor

=== test-brain-class-live.sh: 23 PASS, 1 FAIL ===

verdict: RED
