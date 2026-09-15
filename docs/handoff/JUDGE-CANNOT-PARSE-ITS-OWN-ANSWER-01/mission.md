# JUDGE-CANNOT-PARSE-ITS-OWN-ANSWER-01

Backlog row `13db3e723bcc`. All writes in **`~/Projects/leadv2`**, file
`plugins/leadv2/scripts/leadv2-task-judge.sh`.

## The defect
`envelope_parse` fails on **23 of 38** recorded cases. Every failure falls through to a constant
`standard` size class. So for roughly two thirds of judgments the judge's answer is discarded and
replaced by a default that wears the judge's name — the caller cannot tell a real `standard` from
a parse failure.

This is the same shape as a default bucket carrying a theme name: the output asserts something the
system never determined.

## First — a census, before any fix
Enumerate all 38 cases and classify each failure by its actual cause. Do not report "23 fail";
report how many fail for each distinct reason (unexpected key order, missing field, prose before
the envelope, code fence, multi-line value, …). A fix aimed at the wrong majority cause is a
wasted round. Paste the census table.

## Fix what the census justifies
Make the parser accept the shapes the census shows are real. Then, separately and
non-negotiably: **a parse failure must be distinguishable from a real `standard` verdict.** Emit a
named outcome (`envelope_unparsed` or equivalent) that the caller can see. Whether you keep
`standard` as the fallback behaviour is your call — that it announces itself is not.

## Acceptance
- All 38 recorded cases parse, or the ones that still do not are named individually with the
  reason they are genuinely unparseable. "A loop over zero items prints success" — if your check
  enumerates nothing, that is a named outcome, never a pass.
- A deliberately malformed envelope yields the explicit unparsed outcome, **not** a silent
  `standard`.
- A genuinely `standard` verdict is still reported as `standard`, and is distinguishable from the
  failure case in the output.

## Negative controls — one per independent check, RUN them
1. Restore the old parser and show the 38-case suite go RED.
2. Remove the `envelope_unparsed` signal and show the malformed-envelope test go RED.
One mutation is not a control for two defects. Paste both red/green pairs.

## Off limits
- Do not change what the judge *decides* — only whether its answer survives the trip back.
- The size-class vocabulary (`trivial|light|standard|heavy|strategic|bulk`) is fixed; do not add
  or rename a class.
- Do not touch the admission classifier or the route arbiter.

## Report
`docs/handoff/JUDGE-CANNOT-PARSE-ITS-OWN-ANSWER-01/report.md`: the census table, the fix, the
tests, both controls. End with `DELIVERABLE_COMPLETE`.
