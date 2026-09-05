# QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01 — fix round 1

Your design is accepted and I want to say why, so the next round does not "simplify" it away.

The `kv` row stays **byte-identical** and history is a side-write into a separate
`rate_limit_history` table in the same transaction. That is the right call and it dodges a trap you
may not have known about: `leadv2-quota-status.sh:141` reads the `kv` row with **no `ORDER BY` and
no `LIMIT`**. Had history been appended into `kv`, that reader would have silently started returning
the *oldest* probe — a false answer with no error anywhere. Keep `kv` single-row. Do not "unify" the
two stores in a later round.

Also right, and to be preserved: `account_key` partitioning, `_prune_history` with a retention
window, the idempotent `_seed_from_kv` that only fires while the table is empty, and the comment
forbidding an un-nested `ORDER BY`/`LIMIT` on a compound `SELECT`.

Two items close this lane.

## 1. There is no negative control — this is the blocking item

`tests/test-leadv2-ratelimit-probe.sh` is green. Green proves the suite runs; it does not prove the
suite **bites**. Three of the five wave-3 lanes are in exactly this state, and none of them will be
closed without a biting control — including this one, however finished it looks.

Write the controls in the shape accepted today on `TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01`. Read
`plugins/leadv2/scripts/tests/nc-claude-account-collapse.sh` in that lane's worktree as the model.
Required properties, all of them:

- The mutation is applied **inside a function body**, never at file top level — a top-level insert
  reddens every suite for the wrong reason and reads as a pass.
- The mutated copy is written to a scratch file and the suite runs against **that copy** via an
  injection variable; never edit the original in place.
- An `NC-SETUP-FAIL` guard that exits non-zero loudly if the target line no longer matches, so the
  control cannot degrade into mutating nothing.
- The control passes **only** when the suite goes red.

Three controls, one per load-bearing claim:

- **NC1 — history is actually appended.** Inside `_append_history()`, make the `INSERT` a no-op. The
  suite must go red. Without this, "we now record history" is an untested assertion.
- **NC2 — the `kv` row is not disturbed.** Inside the probe's write path, make the side-write also
  overwrite or delete the `kv` row. The suite must go red, proving you actually assert `kv`
  byte-identity rather than merely intending it.
- **NC3 — the seed is idempotent.** Inside `_seed_from_kv()`, remove the "only while the table is
  empty" condition so it seeds on every probe. The suite must go red, proving the idempotence claim
  bites. If no assertion currently covers it, that is the finding — write the assertion, then the
  control.

For each: report the `baseline_rc` / `mutated_rc` pair and the literal red suite line, then revert and
show green with both exit codes pasted. A `diff_hash` is not proof that anything ran.

## 2. Make the per-account split explicit in what the history answers

The lane was re-aimed to serve the arbiter, and there is now a second consumer worth one sentence in
your header, because it changes nothing in the code but stops a future round from collapsing
`account_key`:

The September plan rests on two Claude accounts having **independent quota**. The sibling lane
`TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01` answers that at the level of **identity** — distinct
`accountUuid` — which is inference, not measurement. Your table answers it at the level of
**consumption**: with `account_key` partitioning, a spend on one account that leaves the other
account's percentages unmoved is readable directly from recorded probes, with no experiment staged.

Add that to the header as the second consumer, and make sure the dwell aggregation can be filtered
to a single `account_key` (if it already can, say so in the header rather than changing code). This
is documentation and, at most, one query flag — not a redesign.

## Constraints

- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session.
- Do not modify `leadv2-quota-status.sh`. Its unordered read is a separate defect; changing it here
  would entangle two lanes.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened to reach green.
- Your registration line in `tests/run-all.sh` shares that file with two other lanes. **Append
  only** — do not reformat or move existing lines, so the three-way merge stays trivial.
- Commit after each item. The machine is heavily loaded and workers have been dying of CPU
  starvation; uncommitted work on this lane has already been rescued by hand once.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-97669e50" "<question>" \
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