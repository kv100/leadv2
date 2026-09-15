# REVIEW-BODY-LOST-FIRES-ON-A-SHORT-CLEAN-PASS-01

Measured defect, taken 2026-09-15 under the founder's standing order to take anything found broken.
All writes in **`~/Projects/leadv2`**, file `plugins/leadv2/scripts/leadv2-review-run.sh`.

## The defect
The review gate blocks with `reason=review_body_lost` when the reviewer's body is merely **short**,
not truncated. Measured on lane `a9522ee7` (E2E-GATE round 2):

```
status: blocked
reason: review_body_lost
arm: codex
body: docs/handoff/dispatch-a9522ee7-review/review-codex.md
bytes: 254
```

That 254-byte file was **complete and coherent**:

```
[provider-quota-gate] OK — codex 30% < 98%
# Codex Adversarial Review
Target: branch diff against HEAD
Verdict: approve
PASS — clean: the diff consistently corrects unset TMPDIR handling in test-only temporary-file creation.
No material findings.
```

`review-codex.err` showed a normal model line and no error. A terse clean PASS is a legitimate
verdict, and to a byte-length threshold it is indistinguishable from a truncated body.

Cost: the lead had to verify the entire round by hand before landing it — and that round carried
two Criticals, so the manual verification was not cheap.

## Why this matters beyond one lane
This is the same family as `findings_lost` vs `parse_failed`, which this repo already fixed: a
gate must distinguish **"I could not read it"** from **"there was nothing to read"**. A length
threshold cannot make that distinction, so it converts every short verdict into a false block —
and a false block costs exactly what a false pass costs.

## Fix
Test completeness by **structure, not size**. A body carrying a parseable verdict marker (the
arm's `REVIEW_VERDICT:` / `Verdict:` line, whatever this repo already treats as authoritative) is
complete regardless of byte count. Only a body missing its verdict marker is lost.

Read how the existing parser identifies a verdict before inventing a new rule — there is already a
notion of the authoritative marker in this file, and the two must not drift apart.

State in one sentence which marker you made authoritative and why.

## Acceptance
- The exact 254-byte fixture above yields a **pass** gate, not `review_body_lost`.
- A genuinely truncated body — cut mid-sentence, no verdict marker — still yields
  `review_body_lost`. This is the property that must not be traded away; a fix that accepts
  everything is the same bug with the sign flipped.
- An empty body still yields `review_body_lost`.
- A body whose only content is a verdict marker and nothing else: state what your rule does with
  it and why that is right.

## Negative controls — one per independent check, all RUN
1. Restore the byte-length threshold → the 254-byte fixture goes RED (blocked again).
2. Remove the missing-marker check → the truncated-body fixture goes RED (wrongly accepted).
One mutation is not a control for two checks. Paste both red/green pairs.

Every mutation anchor must fail loudly when it does not match — an unmatched anchor is a test
failure, never a silent skip.

## Off limits
- Reviewer-arm selection, the route arbiter, quota logic — untouched.
- Do not change the findings parser or the `findings_lost` / `parse_failed` logic; that is a
  separate, already-landed fix and this row must not disturb it.
- Do not relax any other gate to make this one pass.

## Report
`docs/handoff/REVIEW-BODY-LOST-FIRES-ON-A-SHORT-CLEAN-PASS-01/report.md`: the marker you chose and
why, the four acceptance cases with their gate output, both controls.
End with `DELIVERABLE_COMPLETE`.
