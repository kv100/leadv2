# COMBO: SCOPE-DISCIPLINE-01 + TEST-FALSIFICATION-GATE-01 + stop-gate test leg (~/Projects/leadv2)

Base: main 6ae373a. Three items, one lane (they share leadv2-dispatch-product-close.sh /
builder-selfcheck / test files). Suites: FOREGROUND, strictly SOLO (parallel runs cause false
reds here); on a fail rerun solo once before treating it as yours. COMMIT on the lane branch —
the STOP-GATE now auto-checkpoints uncommitted exits, but do not rely on it.

## 1. SCOPE-DISCIPLINE-01 (row 0f02513ea538-ish, external SCOPE-DISCIPLINE-01)
Enforce write-set/off_limits at BUILD time so diffs stop sprawling (root of
unscopable_diff x102): in the builder-selfcheck gate (lib/leadv2-builder-selfcheck.sh +
its product-close call), an oversized/off-write-set diff = builder bounce BEFORE any review
arm, with a loud journal line naming the offending paths. Declared write-set comes from
LEADV2_DISPATCH_LANE_WRITES / _PC_SCOPE_WRITES_CSV (already parsed in product-close). Bounce,
never trim silently. Kill-switch env (same idiom as LEADV2_BUILDER_SELFCHECK). Red-first suite.

## 2. TEST-FALSIFICATION-GATE-01 (external TEST-FALSIFICATION-GATE-01)
Machine rule «a test must have failed once»: extend the builder-selfcheck gate to refuse any
diff that adds/changes a test file without falsification proof — selfcheck.md must carry
per-test raw RED output against a pinned pre-fix baseline or mutant (pattern already coded in
test-review-gate-scope-evidence.sh red-first harness; GREEN_PRE_FIX>0 = non-zero exit). Root
cause: 3 lying-green tests caught in 3 lanes within 24h. Kill-switch. Red-first suite.

## 3. Stop-gate follow-up test leg (codex r3 ask, currently live-probe-proven only)
tests/test-stop-gate.sh: add a red-first leg — worker timeout with an UNTRACKED declared file
→ review.diff contains it AND the checkpoint commit includes it (pc_stop_gate_capture_diff
path). Red leg: assert against a mutant that reverts capture to plain `git diff HEAD`.

## Acceptance
All three suites green with red legs shown · full run-core-offline FOREGROUND SOLO green ·
bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-code.sh (another live lane owns it); routing; supervise*.

## Terminal artifact
Commit sha + per-item red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-201b3f97" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.