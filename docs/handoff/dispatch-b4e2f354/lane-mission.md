# REVIEW-ENGINE-V3-CORE-01-R2

Narrow core replacement for the parked broad review lane. Change only the shared
review engine and one new bounded test.

Required behavior:

1. Default fanout is one independent reviewer.
2. Always-on Haiku hack detection is removed. A security/hack pass runs only for
   protected/high-risk paths or an explicit environment flag.
3. Per-finding verifier LLM calls are off by default. They run only for disputed
   High/Critical findings under an explicit/risk policy.
4. Review state is keyed by task plus diff hash. A changed diff starts a fresh
   state rather than inheriting attempts from an earlier implementation.
5. First pass is exhaustive. After a failed pass and a changed diff, the one
   allowed recheck is targeted to the prior High/Critical blockers; it must not
   request another full census. Hard-cap the sequence at those two passes.
6. Preserve independent reviewer selection, fail-closed gate output and existing
   explicit overrides.
7. Add executable no-provider fixtures proving default call count, risk-triggered
   escalation, fresh-diff state and targeted recheck prompt/mode.

Do not touch product-close, dispatcher, root skills or hooks. No real provider
calls. Commit both files and leave the worktree clean.

acceptance:
  surface: review_gate
  observable: Ordinary changes invoke one reviewer, risk alone enables extra security review, and a changed failed diff gets only one targeted blocker recheck as proven by executable fixtures.
  authored_at: 2026-08-24T21:33:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-engine-v3-core.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b4e2f354" "<question>" \
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