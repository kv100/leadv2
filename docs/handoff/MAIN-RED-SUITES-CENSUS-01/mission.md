# MAIN-RED-SUITES-CENSUS-01 — measurement only, no code fix

Step 1 of `MAIN-RED-SUITES-BLOCK-EVERY-LANE-01`, split out so it can run while other lanes hold
the suite files. Repo: **`~/Projects/leadv2`**.

**This lane writes exactly one file:** `docs/handoff/MAIN-RED-SUITES-CENSUS-01/report.md`.
You may run anything; you may modify nothing. If you find a fix, name it in the report — do not
apply it. Another lane will.

## Why this measurement is being paid for
The review gate runs a falsifiability check on the suites a lane's diff maps to. A suite that is
**already red on main** returns `could_not_determine`, so the gate answers
`blocked: suite_falsifiability_undetermined` and the lane's own work is never judged. Every red
suite on main is therefore a tax on every future lane — and two of the three cases found so far
had **never reached their own assertions at all**: they refused at a premise gate added after they
were written and reported that refusal as a test failure, for months
(`test-dispatch-architect-prepass-late-artifact.sh` and `-orphan-timeout.sh`, fixed in `62e7a253`
by passing the audited `--no-probe-yet` escape hatch).

We do not know how many more of those exist. That is the question this lane answers.

## What to produce
Run **every** suite under `plugins/leadv2/scripts/tests/` on unmodified `main`, one at a time,
each under an explicit per-suite timeout that you state. Produce one table:

| suite | rc | cause class | evidence (`file:line` or the refusing line) |

Cause classes, and a red suite must be assigned exactly one:

- `never_reaches_subject` — refused at a gate before its own assertions. The cheapest and the most
  dangerous: it has been reporting a verdict while asserting nothing.
- `real_regression` — the subject genuinely broke.
- `environment_dependent` — passes alone, fails under the runner, or is platform-bound. **Name the
  specific difference.** Several suites are known Linux-only (rows `TWELVE-LINUX-ONLY-SUITES-01`,
  `LAST-LINUX-RED-FAST-NAMES-01`) — those belong here with the difference named, never as "flaky".
- `rc_127` — three causes wear this one code: missing file, missing interpreter, cwd-relative path.
  Say which. Never report it as a test failure.
- `timeout` — its own verdict, neither pass nor fail. State the bound.

## Rules the census must obey
- **A loop over zero items prints success.** State the suite count **before** any result. If the
  enumeration finds nothing, that is a named outcome, not a pass — say how you enumerated.
- **A number carries its boundary.** "16 red" without "of how many, on which platform, at what
  timeout" is not a number. Every count in this report states its denominator and its platform.
- **Distrust `2>/dev/null`.** A swallowed error reads exactly like success. Where a suite hides its
  own stderr, say so — that is itself a finding.
- A suite that passes is one row too. The table covers all of them, not just the red ones.
- If two suites fail for the same cause, group them and say so. The count of *causes* is the
  number that matters for the fix lane; the count of *suites* is the number that matters for the
  tax.

## Then: a ranked fix plan
After the table, list the causes in the order a fix lane should take them, cheapest-and-most-
dangerous first (`never_reaches_subject` leads). For each cause give:
- the exact set of suite files a fix would write — this becomes the next lane's `--writes`, so
  name **files**, never a directory;
- whether the fix is small-and-obviously-correct, or needs design (the latter is a **new row**, not
  a fix — propose its title);
- the negative control that would prove it.

## Off limits
- **Change no file except your report.** No suite edits, no script edits, no config edits.
- Do not `git stash`, `git reset --hard`, or `git clean` — this checkout is shared with live
  sessions in other repos.
- Do not re-do `test-dispatch-architect-prepass-late-artifact.sh` or `-orphan-timeout.sh`; they are
  fixed in `62e7a253`. List them as the worked example of `never_reaches_subject`.

## Report
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/report.md`: the suite count and how you enumerated it,
then the full table, then the ranked fix plan. End with `DELIVERABLE_COMPLETE`.
