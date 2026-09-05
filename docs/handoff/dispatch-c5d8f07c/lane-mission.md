GLM-53-FLASH-ARM-01 FIX-ROUND (review BLOCK: 3 CRITICAL + 1 HIGH, verbatim below). Base branch: lane-glm53arm (c944b6e). Fix C1, C3, H4; C2's persona-engine tenant yaml is ALREADY fixed by the lead (review_arm_exclusions now [glm, glm-flash]) — your job for C2 is ONLY the drift test in the plugin. All suites must stay green; new branches get red-proven negative controls.

C1: lib/leadv2-glm-policy-resolve.py:710 — the whole protected/safety/opus precedence table is gated on `if base_arm == "glm":`, so base_arm="glm-flash" bypasses every rule. Fix: gate on ("glm","glm-flash") AND add an unconditional final refusal for glm-flash on safety/protected, mirroring the existing freepool block at :949-960. Test: call resolve with base_arm=glm-flash + protected_path=1 -> must NOT return glm-flash; mutate the new check on a scratch copy -> red.

C2 (drift test only): add a test asserting every tenant yaml's explicit review_arm_exclusions is a superset of DEFAULT_REVIEW_EXCLUSIONS (pattern: test-freepool-pin-drift.sh). It must fail if a tenant lists [glm] while defaults include glm-flash.

C3: new glm-flash branches in leadv2-dispatch-code.sh (refusal_reason quota-gate REROUTE + lock_busy disjuncts, bench-park _qpc_arm check, _qg_next drop-both-glm-arms reorder ~:6713) have zero test coverage. Extend test-glm-flash-arm.sh: force stub launcher exit 75 with the quota-gate/lock-busy strings -> assert outcome/journal attribute glm-flash; exercise _qg_next reorder with both glm arms in candidate_arms.

H4: journal line now emits model=${arm} where it hardcoded model=glm. Grep all broad-status/dashboard/quota-status renderers for literal `model=glm` matches; fix any consumer that would miss model=glm-flash rows, or document that none exist (list the files you checked).

M5 (cheap if quick, else skip): LEADV2_COSTLOG_ARM=glm-coder is model-blind — if a one-line change can carry the model into the cost log arm or a field, do it; otherwise note it as a follow-up in the lane notes.

Constraints: bash -n + ast.parse on touched files; do not touch persona-engine; commit on the lane branch.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c5d8f07c" "<question>" \
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