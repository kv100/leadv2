# GATE-PROVES-ITS-OWN-CONTROL-01 — round 2: a red run is not yet a kill

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-PROVES-ITS-OWN-CONTROL-01`

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-control-prover.sh,plugins/leadv2/scripts/tests/test-control-prover.sh,tests/run-all.sh,docs/handoff/GATE-PROVES-ITS-OWN-CONTROL-01/

**Round 1 is merged as `070da47` and stays.** Rebase onto current main first. I verified round 1
myself: removing the `shared_gate_kill` block turns the suite red (`FAIL: 4: shared-gate kill not
counted (rc=0) out=<<[KILLED] id=c4 kind=product`), restoring it turns it green.

I also checked the failure the V5 session reported against its own runner, and **we are already
safe from the exact one**: `leadv2-control-prover.sh:146` blocks `suite_missing`, so a `suite:`
pointing at a nonexistent path is `[BLOCKED]`, not `killed`. Do not redo that.

## [Critical] a non-zero exit from a broken run counts as a kill

`_run_suite` (`:126-129`) is `bash "${suite}"` and returns its exit code, and the scoring path
treats **any** non-zero as "this suite caught the mutation". It does not distinguish an
assertion failing from the run never happening. So a mutation that makes the target file
unparseable, or breaks the suite's own setup, scores a kill while proving nothing about the
assertion the catalog entry claims to protect.

Round 3's revert-must-be-green rule (`:193-201`) catches the always-red case, but not this one:
mutation → infrastructural failure → revert → green. Kill counted, guarantee unproven.

Fix with a third requirement, alongside "red by exit code" and "red alone":

- **the suite must be proven RUN and GREEN before the mutation.** Run it once on the untouched
  tree; if it is not green, the entry is `unscored`, never `killed`;
- **the suite must collect at least one test.** A run that executes nothing is `unscored`;
- **an infrastructural exit code is `unscored`, not a kill.** For pytest, rc 4 (usage) and rc 5
  (no tests collected) are infrastructural; for a bash suite, define the equivalent and say in
  `report.md` what you chose and why.

Introduce `unscored` as a real outcome — the word does not appear in the prover today
(`grep -c unscored` → 0) — and keep it out of both the product and self-test kill tallies, with
its own count in the summary line.

## [Critical] check the fixtures for a legalised fail-open

The V5 session found its own runner's self-test **encoding the bug as correct**: catalog cases
carrying `suite: does/not/matter.py` with case 1 expecting `killed`. A self-test like that does
not merely miss the hole, it ratifies it.

Audit `test-control-prover.sh` for any fixture whose `suite:` is a placeholder, a non-suite
file, or otherwise "doesn't matter", and say in `report.md` how many you found. Ours may be
clean — a first grep showed no `suite=` fixtures at all, which is itself worth explaining.

## Acceptance

Extend `test-control-prover.sh` — fixtures only, never a real lane:

1. suite green before, red after, green on revert ⇒ `killed` (unchanged);
2. suite **red before** the mutation ⇒ `unscored`, not `killed`;
3. suite collects zero tests ⇒ `unscored`;
4. mutation makes the target unparseable so the run fails infrastructurally ⇒ `unscored`, and
   the summary says so;
5. `suite:` pointing at a nonexistent path ⇒ still `[BLOCKED] suite_missing` (regression guard
   for round 1);
6. the summary line reports `scored`, `killed`, `unscored`, `product_killed`, `self_test_killed`
   and the invariant, and `unscored` entries are in none of the kill tallies.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
- A kill counts only if **this suite alone** goes red — and, after this round, only if it was
  green first.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- Do not weaken round 1: removing the `shared_gate_kill` block must still turn the suite red.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A run that never really ran can no longer be counted as a kill, `unscored` is reported
separately, and a mutation removing the pre-mutation green requirement turns the suite red with
the exit code following.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-055185da" "<question>" \
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