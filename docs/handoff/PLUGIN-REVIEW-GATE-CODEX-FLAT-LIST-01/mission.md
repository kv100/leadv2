# PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01 — round 3

Round 2 landed `5e9274e7`. Codex reviewed it and returned **FAIL: 3 High**, all in
`plugins/leadv2/scripts/leadv2-review-run.sh`. The full review is at
`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md` — read it first.
All writes stay in **`~/Projects/leadv2`**, in THIS worktree.

**The defect is still reproducing on this lane's own review.** The round-2 gate artifact reads
`status: blocked / reason: findings_lost / declared_verdict: FAIL / findings_total: 0` while the
Codex report it was parsing carries `REVIEW_FINDINGS: critical=0 high=3` and three `- [high]`
bullets. That is the bug this row exists to kill, measured on itself for the second round running.

## H1 — structured findings suppress every bracket-list finding (`:2028-2029`)
The new flat-list parser runs **only when the report has zero `FINDING:` lines**. Any mixed-shape
report therefore loses all of its bracketed findings — the exact loss the row was opened for, just
moved one condition to the left.

**Fix:** parse both shapes unconditionally and deduplicate only genuinely equivalent findings.

**Test:** a mixed report carrying both a `FINDING:` block and `- [high] …` bullets; every item of
both shapes appears in `findings_total`.

## H2 — unanchored flat findings collapse in dedup (`:2040-2050`)
A flat bullet with no trailing `(file:line)` is emitted with blank `file` and `line`, so every
same-severity unanchored finding shares one dedup key and silently reduces `findings_total`.
Silent reduction is indistinguishable from "there was only one".

**Fix:** give each unanchored item a dedup key that is stable and unique — e.g. fold the
normalized description into the key. State which key you chose.

**Test:** three unanchored `- [high]` bullets with different text → `findings_total` is 3, not 1.

## H3 — `findings_total` is absent on the normal gate path (review-mission-source.md:20-21)
The normal fail gate emits only per-severity fields, and the round-2 test substituted `high` for
the mission-required `findings_total`. So the required observable is neither emitted nor asserted —
the test passed by testing a different field.

**Fix:** emit `findings_total` on the normal gate path.

**Test:** assert `findings_total` equals the count of **all** bracketed fixture findings. Not
`high`. Not a per-severity sum computed the same way the producer computes it — count the fixture's
items independently.

## Negative controls — one per finding, all three RUN
Three independent defects need three mutations; one mutation is not a control for three. For each:
restore the round-2 behaviour (H1: re-add the zero-`FINDING:`-lines condition; H2: blank out the
unanchored dedup key again; H3: drop the `findings_total` emit), show the matching test go RED,
restore, show it green. Paste all three red/green pairs.

## The acceptance that matters
Re-run the round-2 review artifact through the fixed parser. The file
`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md` is a real Codex report with
three real `[high]` findings and a `REVIEW_FINDINGS:` header. The fixed parser must yield
`findings_total: 3` and a gate status that is `fail` (the verdict Codex declared) — **not**
`blocked / findings_lost`. Paste the before and after.

## Off limits
- Reviewer-arm selection, the route arbiter, quota logic — untouched. This row is the parser and
  the gate artifact only.
- Do not make the gate permissive to clear `findings_lost`. `findings_lost` must keep firing when
  findings really are lost; the fix is that they stop being lost.
- `leadv2-review-run.sh` is the sole owner of arm selection — do not move that responsibility.

## Report
Append `## Round 3` to `docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/report.md`: the fix per
finding, the three tests, the three controls, and the before/after of the self-parse acceptance.
End with `DELIVERABLE_COMPLETE`.
