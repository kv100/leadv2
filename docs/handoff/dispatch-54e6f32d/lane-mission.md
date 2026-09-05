# TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 — fix round 1 (lead review findings)

Your previous work is accepted in substance. Both suites are green (`PASS=15 FAIL=0` and
`PASS=73 FAIL=0`) and **both negative controls bite** (NC1 `exit=1 PASS=65 FAIL=8`, NC2 `exit=1
PASS=13 FAIL=2`). Do not redo any of it. The full review is committed at
`docs/handoff/TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01/brief-lead-review.md` — read it first.

Three items close this lane. Nothing else is in scope.

## 1. `verdict()` ignores `organizationUuid` — the hole is one level up from the one you closed

`verdict()` in `plugins/leadv2/scripts/leadv2-claude-account-check.sh` compares only the pairwise
`accountUuid` in `ACCOUNTS[]`. `organizationUuid` is collected and printed per slot but never reaches
the decision.

Two **distinct** `accountUuid`s inside the **same organization** therefore report `TWO_BUCKETS`.
Rate limiting for an organization applies at the org level — your own line 84 reads
`organizationRateLimitTier` for exactly that reason. So the check can answer "two independent
buckets" about a configuration that has one bucket. That is the failure class this lane exists to
prevent, just one level up: not two slots into one account, but two accounts into one org.

It is not firing today (personal = `max`, gmail, no org; work = `team`, mythical.games). It matters
because the check must keep answering correctly **after 15 September**, when a slot may be moved in
response to the Max 5x downgrade — the exact moment someone puts two seats in one org and reads
`TWO_BUCKETS` as reassurance.

Required:
- A pairwise `organizationUuid` comparison alongside the existing `accountUuid` loop, skipping the
  `-` placeholder the same way.
- **A distinct verdict word** — do not overload `ONE_BUCKET`. The operator must be able to tell
  "same account" from "different accounts, same org" without reading code, because the remedies
  differ. Pick the word and document the exit code in the header's exit-code table.
- The org check must not fire when `organizationUuid` is unresolved for either slot. An unresolved
  org is unknown, never a collapse — the same fail-open discipline `T20d` already holds for the
  email half.

## 2. Fixtures and a negative control for the new branch

- Fixture pair: two slots with **different** `accountUuid` and the **same** `organizationUuid` →
  must report the new collapse verdict, not `TWO_BUCKETS`.
- Mirror fixture: different accounts, different orgs → still `TWO_BUCKETS`, so the new branch cannot
  degrade into "always collapsed".
- Unresolved-org fixture: one slot with `org=-` → `TWO_BUCKETS`, no spurious collapse.
- **NC3**, same shape as your NC1/NC2: mutation **inside `verdict()`'s body** that neutralises the
  org comparison only, run through `LEADV2_TEST_SELECT_BIN` against the mutated copy, with the same
  `NC-SETUP-FAIL` guard you already wrote. Suite must go red. Report the `baseline_rc` /
  `mutated_rc` pair and the literal red line, then revert and show green with both exit codes.

## 3. Two acceptance items from the original brief that are not yet satisfied

- **Linux container.** Both suites have only ever run on macOS. The header claims `.claude.json` is
  present on a keychain-less Linux container and that a missing keychain never flips the verdict;
  `T4` asserts that on macOS with a stubbed absence, which is not the same as running there. Run
  both suites plus all three NCs in a linux container and paste the exit codes.
- **Runner registration.** You registered the suite at
  `plugins/leadv2/scripts/tests/run-core-offline.sh:424`. Confirm that is the runner CI actually
  selects for this repo, and demonstrate that a change to `leadv2-claude-profile-select.sh` selects
  it. If there is a `--scope changed` mechanism here, show its output. An unregistered suite rots
  silently and a green suite CI never runs is worth nothing.

## Standing constraints, unchanged

- Never print or log a credential value. The registry holds labels only. `T5b` already guards this —
  keep it guarding the new code path too.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — both are held by another session.
- Do not add anything to `tests/known-red-suites.txt` and do not weaken an assertion to get green.
- Commit as you go. The machine is heavily loaded and workers have been dying from CPU starvation;
  uncommitted work has been lost twice on this lane already. Commit after each of the three items
  rather than once at the end.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-54e6f32d" "<question>" \
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