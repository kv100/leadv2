# A registry failure becomes an empty allowlist, and every capable arm is dropped

**Priority 0.** This is why lanes died three times today with capable arms available. Fixing it
is worth more than any single lane it would have saved, because it turns a transient fault into
a total dispatch failure.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed
to main is not delivered. **Dispatch and work from `~/Projects/leadv2`, not persona-engine.**

---

## The mechanism, already traced — confirm it, do not re-derive it

`leadv2-dispatch-code.sh:2753` `_filter_arms_to_dispatchable()` builds its allowed set:

    _dispatchable="$(_arm_launchable_arms "${_sig8}" "${kind:-code}" | tr ',' ' ')"

`_arm_launchable_arms` (`:2591`) runs an inline python query against
`lib/leadv2-launch-registry.py`. When that subprocess exits non-zero it emits
`arm_refused ... reason=launch_registry_unavailable` and **`return 1`** — so `_dispatchable`
is the **empty string**. The loop below then fails the membership test for every candidate and
emits, for each:

    arm_dropped_not_dispatchable arm=codex ... reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate

That reason is false. The set it names contains codex and sonnet:
`lib/leadv2-glm-policy-resolve.py` gives `['codex','freepool','glm','glm-flash','sonnet']`, and
the legacy ladder at `:2459` is `_LADDER_IDS=(glm codex sonnet)`. Nothing is stale — the
allowlist is simply *empty* because the lookup failed, and "unknown" is being rendered as
"nothing qualifies".

Observed end-to-end on task `ea105ac7` (P6b, third attempt), in order:

    arm_refused reason=launch_registry_unavailable kind=code
    quota_lockout_recorded provider=glm reason=quota_gate minutes=30 strikes=81
    arm_refused by=router model=glm reason=glm_refused_quota_gate
    arm_refused reason=launch_registry_unavailable kind=code
    arm_dropped_not_dispatchable arm=codex   reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate
    arm_dropped_not_dispatchable arm=sonnet  reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate
    dispatch_rolled_back reason=all_arms_not_dispatchable_v2

One arm was genuinely unavailable (glm, quota). Two were fine and were thrown away.

---

## Why this is the doctrine violation, not just a bug

This codebase already decided how to treat an unknown. `run-core-offline.sh`'s scope selection
(`cf03dd6a`) states the rule: an undeterminable set **fails OPEN** and runs everything, because
a path that silently narrows to zero and exits 0 is invisible. The dispatcher does the opposite
at this seam — it narrows to zero on a lookup failure and reports it as a property of the arms.

Both halves are wrong and both are worth fixing:

1. **The fallback.** On registry failure, fall back to the legacy dispatchable set rather than
   to empty. A lane launching on a slightly-stale arm list is strictly better than a lane not
   launching at all, and the legacy set is right there at `:2459`.
2. **The message.** `reason=not_in_DISPATCHABLE_BUILD_ARMS` must not be emitted when the
   allowlist could not be computed. Those are different facts and today they print identically,
   which is what made this take three failed dispatches and a code read to see.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable)

Two, both run, both shown red then green:

1. **Force the registry query to fail** (inside `_arm_launchable_arms`, in the function body —
   not a top-level insert) and assert a lane still resolves an arm and launches. Before your
   fix this must FAIL; after it, pass.
2. **Assert the message is honest**: with the query forced to fail, no
   `reason=not_in_DISPATCHABLE_BUILD_ARMS` line may be emitted for an arm that IS in the legacy
   set. Break the distinction deliberately and show the suite goes red on the VALUE, never on a
   log string alone.

Register the suite so CI selects it on a change to `leadv2-dispatch-code.sh`, and prove the
selection with `--scope changed`. A suite CI never runs is worth nothing — that lesson is
already paid for in this repo.

**`tests/run-all.sh` is NOT in your write set**, because a concurrent lane (founder row
`b0fe5f28527e`, the gate-budget work) owns it right now. If registration needs an edit there,
write the exact one-line change you need into your report and stop — the lead will apply it in
the merge. Do not edit across the boundary; two lanes writing that file is how a fix gets
silently reverted.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- `leadv2-dispatch-code.sh` is also P6b's target file. P6b is HELD, not running, precisely so
  you can have this file. Do not widen into P6b's work (wiring the complexity estimator).
- The cause of the registry query failing at all is a SEPARATE open row and is still
  unexplained. Do not chase it here. This mission is about surviving it.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-d60b1e07" "<question>" \
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