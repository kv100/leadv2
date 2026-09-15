[provider-quota-gate] OK — codex 26% < 98%
# Codex Adversarial Review

Target: branch diff against bfab5aac14f07b152f8c0e93332898b0f8a7a4fd
Verdict: needs-attention

REVIEW_CODE_VERDICT: FAIL
REVIEW_MISSION_VERDICT: FAIL
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=0 low=0
No-ship: the change drops valid flat-list findings and does not implement the required findings_total contract.

Findings:
- [high] Required findings_total is absent (/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-mission-source.md:20-21)
  The normal fail gate emits only per-severity fields and the new test substitutes `high` for the mission-required `findings_total`, so the required observable equality is neither implemented nor tested.
  Recommendation: Emit findings_total on the normal gate path and assert it equals the count of all bracketed fixture findings.
- [high] Unanchored flat findings collapse during deduplication (plugins/leadv2/scripts/leadv2-review-run.sh:2040-2050)
  A flat bullet without a trailing location is emitted with blank file and line, causing every same-severity flat finding to share the existing deduplication key and silently reduce findings_total.
  Recommendation: Give each unanchored parsed item a stable unique dedup key or include normalized description in the key, with a multi-item unanchored regression test.
- [high] Structured findings suppress all bracket-list findings (plugins/leadv2/scripts/leadv2-review-run.sh:2028-2029)
  The new parser runs only when the report has zero `FINDING:` lines, so any mixed-shape report loses its bracketed findings despite the requirement to add flat-list parsing alongside existing shapes.
  Recommendation: Parse both shapes and deduplicate only equivalent findings, then add a mixed-report test that verifies every bracketed item is counted.

Next steps:
- Add findings_total to the normal gate artifact and cover mixed and unanchored bracket-list reports.
