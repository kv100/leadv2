# Three suites are red on main and on no allowlist — so no lane can gate green honestly

**Priority 0.** While these three fail, every lane whose scope selection touches them gets
`verdict=fail` for breakage it did not cause. That already happened once today, to lane `a0b9aa86`,
via status-surface. This is the precondition for every other gate row.

---

## Measured on `~/Projects/leadv2` main, 2026-09-08, after the P1b (45efe543) and empty-lane
## (34e9fefa) merges. Do not re-derive; do re-run.

`tests/known-red-suites.txt` holds 14 entries. These three are in none of them:

| suite | path | rc | time |
|---|---|---|---|
| `test-claude-subsession-sentinel.sh` | `.claude/scripts/tests/` | 1 | 7-12s |
| `test-lane-liveness-authoritative.sh` | `.claude/scripts/tests/` | 1 | 15-28s |
| `test-lane-finished-state.sh` | `plugins/leadv2/scripts/tests/` | 1 | 80s |

For contrast, `test-lane-truth-batch-01.sh` IS listed (1 match) — so the allowlist mechanism works;
these three were simply never added.

**The sentinel suite is not test rot. Read its three failures before deciding anything:**

    [TEST] FAIL: .finalized stamped while worker alive (false-dead)
    [TEST] FAIL: E2: .outcome carries real child exit code (4)
    [TEST] FAIL: E3: verdict is dead:sentinel_finalized

That first line describes a live defect in the liveness machinery: a worker that is alive gets
stamped finalized and read back as dead. There is a standing filed observation that matches its
shape exactly — the anti-silence pulse printed `da195ecf5abc=35m STALL` for a lane that had
committed **16 seconds earlier**.

The second suite fails in the same family, which is why the hypothesis is worth stating:

    [TEST] FAIL: D6 -- degradation ladder dropped a lane

Two of the three reds are lane-liveness. Treat "these are one bug" as the leading hypothesis to be
confirmed or killed, not as an established fact — the third suite may well be unrelated, and
forcing it into the same story would be the easier mistake to make here.

---

## What to do, in this order

1. **Run all three yourself and capture the failures.** Paths differ per suite (see the table);
   two live under `.claude/scripts/tests/`, one under `plugins/leadv2/scripts/tests/`. Do not
   assume a common runner.

2. **Classify each one, separately, into exactly one of three:**
   - **live defect** — the suite is right and production is wrong. Fix production.
   - **test rot** — the suite encodes an obsolete contract. Fix or delete the suite, and say
     which decision record or commit changed the contract underneath it.
   - **environment** — red only under some condition (a worktree, a macOS quirk, a missing
     binary). Then say precisely which condition, and make the suite skip explicitly with a
     reason rather than fail.

   A classification with no evidence line is not a classification. "Looks like rot" is refused.

3. **Do not reach for the allowlist first.** Adding a suite to `tests/known-red-suites.txt` is
   correct ONLY for a red that is deliberate and documented. Using it to silence a live defect is
   the lying-green disease with extra steps, and the sentinel failure above is very likely a live
   defect. If you do add an entry, the same commit carries the reason and the condition under
   which it comes back off.

4. **The sentinel one gets the deepest look**, because a false-dead verdict does not merely fail a
   test — it makes the orchestrator kill or ignore live work. Establish whether the false-dead path
   can fire in production today, and under what timing. If it can, that finding outranks the gate
   question entirely and should be reported immediately rather than bundled into a close.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable)

For every suite you turn green, name and RUN the mutation that must make it red again, inserted
**inside the function body** under test, not at top level, and going red on a **value**, never on a
log string. Show the red output and the restored green. A suite that cannot be made red by breaking
the thing it covers has not been fixed; it has been silenced.

If you fix a live defect, the mutation is the defect re-introduced.

---

## Constraints

- Repo: `~/Projects/leadv2`. Its `main` IS the live path — this is a symlink deploy, so a fix that
  is not committed to main is not delivered. Do not merge; report, and the lead merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- **Dispatch and work in `~/Projects/leadv2`, not persona-engine.** The first attempt was launched
  from persona-engine and the dispatcher rooted the lane worktree there, where none of the three
  suites exist — the worker correctly refused to guess and recorded the blocker instead of
  inventing paths. Every path in this mission is leadv2-relative.
- Report to `docs/handoff/three-unlisted-reds-report.md` (inside leadv2): one section
  per suite, its classification, the evidence line, the fix, and the control output.
- If a suite turns out to need a change outside the write set below, stop and say so in the report
  rather than widening it yourself.

LANE_WRITES: docs/handoff/three-unlisted-reds-report.md, .claude/scripts/tests/test-claude-subsession-sentinel.sh, .claude/scripts/tests/test-lane-liveness-authoritative.sh, plugins/leadv2/scripts/tests/test-lane-finished-state.sh, plugins/leadv2/scripts/lib/leadv2-lane-liveness.sh, tests/known-red-suites.txt

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2dfefcdd" "<question>" \
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