# PHASES-ARE-THE-ONLY-PATH-01 — round 7 (plugin repo ~/Projects/leadv2)

Lane `d4d014e1`, HEAD `1cdf7de`. Do not rebase. `test-phase-precondition.sh` is `pass=52 fail=0`
and is verified non-tautological (43/9 against pre-fix code) — do not regress it.

Scope is ONE finding. An adversarial review is running in parallel; if it lands blocking findings
they become round 8, not your problem. Do not widen scope on your own.

## R1 — the review-recorder guard is broader than the property it enforces
`leadv2-dispatch-code.sh:2317-2328` refuses `record-review` whenever `$PWD` is inside a linked
worktree (git-dir vs git-common-dir, plus a `*/.claude/worktrees/*` path heuristic).

The property we want: **a build worker cannot record a review of its own work.**
The property implemented: *nobody can record any review from any worktree.*

Collateral, reproduced: `tests/test-routing-enforcement-p1.sh` passes on plugin main (rc=0) and
fails in this lane (rc=1) with
`FAIL: duplicate review refusal -- first_rc=1 second_rc=1 output=... review_record_refused
reason=lane_worktree`. That test asserts duplicate-diff-hash refusal and has nothing to do with
provenance; both its calls are now refused for the wrong reason, so the dedup assertion is never
exercised. Running the suite from inside a lane is our standard way of validating a lane, so this
turns every in-lane suite run red on an unrelated test.

Required: narrow the guard to the actual property. Refuse when the caller is recording a review of
**the current worktree's own diff** — i.e. compare the row's `diff_hash` against the hash of the
diff of `$PWD`'s worktree against its own base, computed the same way the rest of the code computes
it (find that code, do not invent a second hashing scheme). Recording a review of a DIFFERENT diff
from inside a worktree must be allowed.

If you conclude that narrowing cannot be done safely, say so explicitly and instead make
`test-routing-enforcement-p1.sh` set `REVIEW_RECORDER_GUARD=0` for its dedup cases — but state in
your report that the landmine remains for the next caller.

## Must still hold after your change
- A worker recording a PASS for its own current diff from inside its lane → still refused.
- `tests/test-phase-precondition.sh` → still `pass=52 fail=0`, forgery cases still rejecting.
- `tests/test-routing-enforcement-p1.sh` → passes BOTH from the main repo root and from inside a
  lane worktree. Show both runs.

## Do NOT
Do not touch `leadv2-phase-record.sh` unless the hashing helper you must reuse lives there.
Do not disable `REVIEW_RECORDER_GUARD` by default. Do not touch the Codex runner suite — it fails
on untouched main because Codex is quota-locked until 2026-08-08, which is not ours.

## Write set
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`,
`plugins/leadv2/scripts/tests/test-phase-precondition.sh` (only to add a case for the narrowed
guard).

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit sha + raw output of the three test runs named above.
Commit your work before you finish — four workers today died with uncommitted work.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4a948294" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.