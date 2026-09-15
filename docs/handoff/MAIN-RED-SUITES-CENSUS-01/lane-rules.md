# Standing rules for every lane in the 93/93 plan

Read this in full. Every mission in this plan references it instead of repeating it.

## The one rule that matters most
**Never make a suite green by deleting an assertion, loosening a grep, adding `|| true`, or
widening a matcher until it matches anything.** A suite you cannot fix honestly stays red, and you
name it as still-red with its cause in your report. **That is a passing outcome for your lane.** A
suite made green dishonestly is worse than a red one, because it stops reporting defects forever
and nobody will look at it again.

There is one legitimate case for changing a test rather than the subject: the test encodes a
requirement that has since been **superseded by a founder decision recorded in the code**. When that
happens you must quote the recorded decision (its id, its date, its `file:line`) in the report, and
you must leave one case asserting the NEW behaviour so the decision itself is guarded. Never assume
this case — prove it from a comment or a commit, or treat the subject as broken.

## Order of work
1. **Reproduce first, from your branch, before reading any fix-shaped code.** Paste the command and
   its output. If it does not reproduce, say so and stop — a fix for a failure you never saw is a
   guess.
2. **Name the cause class per suite before any diff appears**, from exactly this list:
   `never_reaches_subject` · `real_regression` · `environment_dependent` · `rc_127` · `timeout` ·
   `test_encodes_superseded_requirement` · `harness_self_interference`.
   A suite whose case never reaches the code it claims to test is `never_reaches_subject`, and the
   fix is usually in the fixture, not the subject.
3. Fix.
4. Re-run the whole suite, not just the case you touched.

## Negative controls
**One control per independent claim. One mutation is not a control for N checks.**
For each fix: apply a mutation INSIDE the function body you changed (never a top-level `exit 1`),
show the suite go red, revert, show it go green. Paste BOTH outputs. A control you did not run is
not a control, and a control whose target text no longer exists is a permanent green — check that
your mutation actually lands.

If a suite has several independent assertions and you fixed several, each needs its own mutation.

## Measurement hygiene
- **Every count carries its boundary**: how many, of how many, at what per-suite ceiling, on which
  platform, from which commit. "12 pass" is not a result; "12 of 12 at a 400s ceiling on macOS
  Darwin 25.6.0 at `<sha>`" is.
- **An enumeration over zero items prints success.** If your check loops over a list, assert the
  list is non-empty first.
- Some suites in this plan exceed the census's 120s ceiling (`test-burn-governor.sh` 195s,
  `test-lane-truth-batch-01.sh` 204s, `test-stop-gate.sh` 256s). Give them room and report the wall
  time; a timeout is a different verdict from a failure and must not be reported as one.
- If you find that a suite is red only because of the environment the **runner** creates, that is
  `harness_self_interference` and it is a real defect — in the runner, not the suite. A confirmed
  instance already exists: `run-core-offline.sh:179` re-execs as
  `env _LV2_CORE_OFFLINE_LOCK_HELD=1 …`, and that variable is inherited by every suite body it
  runs.

## Platform boundary — do not overstate what you fixed
This whole plan is measured **on macOS**. Three separate backlog rows describe the opposite
population — suites green on macOS and red on Linux (`TWELVE-LINUX-ONLY-SUITES-01`,
`LAST-LINUX-RED-FAST-NAMES-01`, `CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01`). **Green here does not mean
green in CI.** Never write a sentence that mixes the two populations.

A failure that is genuinely platform-bound counts as fixed when the suite **declares the difference
itself** — so the falsifiability check stops answering `could_not_determine` — not when it is forced
green.

## Write sets
- `--writes` names **FILES, never directories.** The match is by prefix, so a directory conflicts
  with everything beneath it and serialises the whole board.
- Your write set is fixed at dispatch and cannot be widened. If your fix needs a file that is not in
  it, **stop and say so in the report** with the file you needed and why. Do not write outside the
  declared set, and do not work around it.

## Report
Write it at the path your mission names. It must contain, per suite:
reproduction command · observed output · cause class · the mechanism at `file:line` · the fix ·
the negative control with both outputs · the final suite run with its boundary.
And, at the end, an explicit list of anything you left red and why.
