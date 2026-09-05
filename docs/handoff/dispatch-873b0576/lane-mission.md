# CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01

`test-skill-proof-gate.sh` passes on macOS and fails on Linux CI. It is the LAST thing standing
between us and a green `main`, and a green `main` is what unlocks required status checks on
`kv100/leadv2` (ledger row `SD-CI-REQUIRE-STATUS-CHECKS-01`). Treat it as a blocker, not a nit.

## Evidence

CI run `33703800486` (ubuntu-latest, commit `692fd94f`) — the suite reports `PASS=10 FAIL=6`:

    FAIL: shellcheck: leadv2-skill-proof.sh
    FAIL: shellcheck: leadv2-proof-lib.sh
    FAIL: (a) valid+passing → expected GREEN exit 0, got rc=1
    FAIL: (e) mixed tree → expected green=1 in summary
    FAIL: (e) mixed tree → expected red=2 in summary

The same suite on this Mac, same commit: `rc=0`, `PASS=16 FAIL=0`, and both shellcheck
assertions PASS. Verified by the lead 2026-09-03T01:40Z.

`bash -n` passes on BOTH platforms — this is not a syntax error.

## Two independent causes; do not conflate them

**(1) The shellcheck assertions depend on the tool VERSION, not on the code.**
`test-skill-proof-gate.sh:60-64` runs `shellcheck -x "$GATE"` and fails the test on any non-zero
exit. Local shellcheck is 0.11.0; ubuntu-latest ships an older one, which emits findings 0.11
does not (and `-x` follows sourced files, so the resolved set can differ too). A suite whose
verdict depends on whichever shellcheck the machine happens to have is not a test, it is a
coin flip. Decide and implement one of: pin the version the gate asserts against, assert only on
a fixed severity level, or drop the lint from this suite and run shellcheck as its own CI step
where a version can be pinned. Whatever you choose must give the SAME verdict on both platforms.

**(2) The (a) and (e) failures are runtime behaviour, not lint.**
`(a) valid+passing → expected GREEN exit 0, got rc=1` means the gate itself returns 1 on Linux for
a fixture that is green on macOS; `(e)` then miscounts the mixed tree. Diagnose this separately —
do NOT assume it is a knock-on of (1). Read the CI log for the actual gate output before forming a
hypothesis, and name the concrete platform difference you found (a GNU-vs-BSD flag, a `date`/`stat`
form, a locale/sort order, a `/tmp` path shape) with the line that produced it.

## Definition of done

1. `test-skill-proof-gate.sh` is green on Linux. Proof is a CI run on your branch, not a local run.
2. For each of the two causes, state the exact platform difference and the file:line you changed.
3. A negative control per cause: name the mutation, show the suite goes red on it, revert, show green.
4. Do NOT allow-list this suite in `tests/known-red-suites.txt` to make CI green. The allow-list is
   for pre-existing reds we have decided to carry; hiding a fresh platform bug in it is exactly the
   lying-green disease this repo has a rule against.
5. Run only the suites you touched, individually, and paste each exit code. Do NOT run the full
   83-suite `run-core-offline.sh` — the machine is shared.
6. Commit in this lane before you finish.

Off limits: `main`, the allow-list, and any change that makes the assertion weaker rather than
platform-independent.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-873b0576" "<question>" \
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