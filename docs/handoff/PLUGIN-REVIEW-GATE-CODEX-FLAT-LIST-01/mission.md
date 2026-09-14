# PLUGIN-REVIEW-GATE-CANNOT-PARSE-CODEX-FLAT-LIST-01 — round 2

Round 1 landed `1b8b0243` on this lane's branch. Round 2 fixes it. All writes stay in
**`~/Projects/leadv2`**, in THIS worktree.

## The round-1 fix does not work, and the proof is this lane's own review
Codex reviewed `1b8b0243` and emitted three `[high]` findings as a flat bracket list into
`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md`. The gate then wrote:

```
status: blocked
reason: findings_lost
declared_verdict: FAIL
findings_total: 0
```

Three real findings in the file, zero counted — the exact defect the row names, reproducing on
the fix meant to remove it. Treat that artifact pair as your regression fixture: it is a real
Codex report, not a synthetic one.

## The three findings — fix all three
1. **`findings_total` is absent on the normal gate path** (`review-mission-source.md:20-21`).
   The normal fail gate emits only per-severity fields, and the round-1 test substituted `high`
   for the mission-required `findings_total`, so the required equality is neither implemented nor
   tested. Emit `findings_total` on the normal gate path and assert it equals the count of ALL
   bracketed findings in the fixture.
2. **Unanchored flat findings collapse during dedup** (`leadv2-review-run.sh:2040-2050`).
   A flat bullet with no trailing location is emitted with blank file and line, so every
   same-severity unanchored finding shares one dedup key and silently reduces the count. Give each
   unanchored item a stable unique key (e.g. include the normalized description), and add a
   multi-item unanchored regression test.
3. **Structured findings suppress bracket-list findings** (`leadv2-review-run.sh:2028-2029`).
   The new parser runs ONLY when the report has zero `FINDING:` lines, so a mixed-shape report
   loses every bracketed finding. Parse BOTH shapes, dedup only genuinely equivalent findings, and
   add a mixed-report test proving every bracketed item is counted.

## Acceptance — behavioural, not a grep
- Re-run the gate against the real `review-codex.md` above: `findings_total` must be **3**, and
  `reason` must NOT be `findings_lost`.
- Tests for all three shapes: flat-only, mixed (`FINDING:` + brackets), unanchored-multi.
- `findings_lost` must still fire for a genuinely unreadable or empty report — do not make it
  unreachable.
- **Negative control, RUN it three times, once per fix:** revert each of the three changes
  individually inside the function body in a scratch copy, re-run, show the matching test goes RED,
  restore. Paste all outputs. One mutation is not a control for three independent defects.

## Known trap, still open from round 1
`review_gate` is emitted from **two** sites. Round 1's report says `leadv2-dispatch-product-close.sh`
was investigated and found unaffected — verify that claim yourself rather than inheriting it, and
say in your report which site you tested against.

## Off limits
- Reviewer-arm selection, quota filtering, author exclusion — untouched.
- Do not weaken a fixture to get green. The pre-existing `test-review-gate-shows-findings.sh`
  B/C failures were traced in round 1 to a selfcheck-gate/dirty-worktree interaction unrelated to
  this fix — leave them, but say whether they still reproduce.

## Report
Append to `docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/report.md` under `## Round 2`.
End with `DELIVERABLE_COMPLETE`.
