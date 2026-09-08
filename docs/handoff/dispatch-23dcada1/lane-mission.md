# Two suites eat 64% of the close gate's budget

**Priority 0.** Row B2 of `PRE-WAVES-PLAN.md`, and one of the two things holding gate row A6
(«review runs real N-round gates scaled by complexity») shut. The close gate has **never once
reached a verdict on this machine** — every run ends `verdict=timeout rc=124 timeout_s=900`.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

This mission supersedes the older `gate-budget-too-small-for-run-all.md`, which was written before
the per-suite measurement below existed and reasons about scope forwarding rather than cost.

---

## The measurement, taken by the lead 2026-09-08

Per-suite timing of the gate's own leaf suites:

- **15 leaf suites = 1049s** against a **900s** budget. They do not fit *even before*
  `run-core-offline.sh` is delegated a further 25 suites.
- `plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh` — **355s**, and it is **red**. It is
  listed in `tests/known-red-suites.txt` at line 35.
- `tests/test-status-surface-bash32.sh` — **321s**, and it is **green**.
- Together **676s = 64%** of the whole budget, and roughly six minutes of that fifteen-minute
  budget is spent failing a suite we already know fails.

Verify these numbers yourself before building on them — a per-suite timing is cheap to re-take and
I would rather you contradict me than inherit a wrong constant.

---

## Three directions, in this order. The order matters.

**1. Take known-red suites out of the CLOSE budget without dropping them from runs entirely.**
This is the largest single win (355s) and the cheapest. But the naive form of it is a trap: if a
known-red suite stops being run at all, nobody ever notices when it goes green, and the allowlist
becomes permanent. Whatever you build must still execute it somewhere and still surface a
red→green transition. Say where that happens.

Related and already filed: `E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01` — the allowlist cannot currently
unblock a gate at all. Read that row before you design; if your fix subsumes it, say so explicitly
rather than leaving two rows that half-overlap.

**2. Find out why a green bash-3.2 compatibility suite costs 321s.** That is not a plausible cost
for what it checks. Do not optimise it blind — measure *inside* it first and report where the time
actually goes. A per-suite 321s may itself be a bug worth its own row.

**3. A per-suite ceiling.** One suite must not be able to consume the whole budget. A ceiling turns
"the gate timed out, verdict unknown" into "suite X exceeded its ceiling", which is a *verdict* —
and a verdict is the thing the gate currently cannot produce.

**Explicitly rejected: raising `E2E_TIMEOUT_S`.** The sum grows with every suite added, so a bigger
constant is a race with no finish line. If after measuring you believe a raise is genuinely part of
the answer, argue it — but it may not be the whole answer, and it may not be the first move.

---

## What the fix has to achieve

**The close gate reaches a verdict — any verdict — inside its budget, on this machine.** That is
the acceptance criterion, and it is behavioural: show a real gate run whose terminal is a verdict
rather than `rc=124`.

What it must not do:

- It must not reach a verdict by not running things. A gate that passes because its selection went
  empty is the lying-green disease and this repo has already had it.
- It must not silence a suite permanently. Anything excluded from the *budget* must still be
  executed and still be able to report a state change.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** A selection whose suites exceed the budget must produce a verdict, not a
   timeout. Assert the terminal **value**, not a log string.
2. **The guard.** A genuinely failing suite that is NOT on the allowlist must still fail the gate.
   Break your own exclusion rule deliberately (exclude everything red) and show the suite goes red
   — otherwise the fix is a gate that always passes.

Insert every mutation **inside the function body**, never at top level: a top-level insert reddens
everything for the wrong reason and reads as a pass. That mistake has already invalidated one
measurement in this repo.

Register your suite with a `# run-all-triggers: <stem>` header. **Then prove selection correctly** —
`--scope changed` lies in three separate ways and has produced two wrong conclusions in one day:

- it counts from `$GIT_DIR/leadv2-run-all-last-checked-sha` when that file exists (`:294-310`);
- with no checkpoint and no resolvable base ref it degrades to `HEAD~1..HEAD`, the last commit only
  (`:308-317`);
- so a correctly registered suite can look unregistered, and a broken one can look fine.

Pin the range to the merge base for the proof (write the merge-base sha into the checkpoint file,
run, then remove it) and state in your report which range you measured from.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD` — two dots renders every commit that landed
  on main after your branch point as a deletion, which has produced two false alarms already.
- Timing measurements on this machine are noisy — it is running many lanes. Take each timing more
  than once and say which number you are reporting.

LANE_WRITES: tests/run-all.sh, tests/known-red-suites.txt, plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh


---

## CORRECTION 2026-09-08 — the first attempt was right and this mission was wrong

The first lane did NOT fail. It refused to invent paths and reported exactly why, which is the
behaviour I want. Two errors were mine and are fixed above; a third is corrected here.

1. **The write set named paths that do not exist.** This mission originally authorized
   `plugins/leadv2/scripts/tests/run-all.sh` and
   `plugins/leadv2/scripts/tests/known-red-suites.txt`. Verified by me just now: **neither exists.**
   The real runner is `tests/run-all.sh` and the real allowlist is `tests/known-red-suites.txt`,
   both at the repository root. LANE_WRITES above is corrected.
2. **The allowlist is not a one-entry file.** I wrote "16 lines, one of which is this suite".
   Verified: 35 non-empty lines, **14 of them `core:` entries**, with the lane-truth-batch suite at
   line 35. So "known-red" is an established mechanism with real contents, not a special case built
   around one suite — design accordingly.
3. **The two suites live in different trees.** `test-lane-truth-batch-01.sh` is under
   `plugins/leadv2/scripts/tests/`; `test-status-surface-bash32.sh` is under `tests/`. A fix that
   assumes one location will miss half the problem.

The first lane also observed, from source only and claiming no behavioural proof, that
`tests/run-all.sh` already parses `[CORE-OFFLINE] FAILED:` labels and classifies them with
`is_known_red`. Check whether that subsumes row `E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01` before you
build anything for it — and say which, because two half-overlapping rows is how work gets done twice.


---

## ADDENDUM 2026-09-08 (late) — the file under you was rewritten, and that was my fault

Three previous attempts at this row produced an empty worktree. The last one is explained and
it is a dispatch error of mine, not a worker failure: **I ran this lane and row B6 at the same
time, and both declared `tests/run-all.sh` in their write set.** B6 has since merged
(`dbfd805b`) with 187 changed lines in exactly that file, so this lane's base was stale while
it worked and anything it wrote would have collided.

**Start from current `main`.** What B6 changed there, because it moves your ground:

- `--scope changed` now means *what this branch changes* — `merge-base..HEAD` — and it can no
  longer see `$GIT_DIR/leadv2-run-all-last-checked-sha` at all. Asking twice gives one answer.
- The checkpoint semantics survive under their own scope (`changed-since`), for incremental CI.
- An unresolvable base ref is now a named FATAL refusal (`no_base_ref`), never a silent
  degradation to `HEAD~1..HEAD`.
- `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` prints the discovered
  `<stem>:<suite>` map and exits. **Use that for every selection proof.** It is stateless, and
  it is the instrument the lead has used for four merges today.

Nothing about the budget problem itself changed: 15 leaf suites still total ~1049s against a
900s budget, `test-lane-truth-batch-01.sh` is still ~355s and red, `test-status-surface-bash32.sh`
still ~321s and green. Re-measure rather than trusting those numbers — the machine was loaded
when I took them.

**One more thing that is now true and helps you:** row B5 merged, so a write set consisting only
of `docs/handoff/` paths is refused at dispatch time instead of killing your lane 25s after
spawn. You will not lose work to that any more.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-23dcada1" "<question>" \
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