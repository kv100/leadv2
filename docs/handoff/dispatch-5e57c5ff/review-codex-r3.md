# Codex Adversarial Review

Target: branch diff against b90e40ed36d2e2f39d232d859330bb7f5c7c07eb
Verdict: needs-attention

No-ship: the report gate still permits host-file substitution and can mark unreviewed source changes as landed. REVIEW_VERDICT: fail, REVIEW_FINDINGS: critical=0 high=2 medium=0 low=0.

Findings:
- [high] Report path validation is vulnerable to TOCTOU substitution (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:49-61)
  After `lv2_report_locate` validates the source as a contained non-link, later `wc`, `tr`, and `cp` reopen the pathname, so a concurrent worker can replace it with a symlink to an arbitrary host file that is then harvested and sent to the reviewer.
  Recommendation: Open and validate the report through directory FDs with no-follow semantics, then create and review a single snapshot from that validated descriptor rather than reopening the pathname.
- [high] Report-mode success can launder unrelated code changes (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1543-1551)
  The report branch overwrites the generated diff with report prose and clears `blocked_reason`, so source changes made by the same lane are neither diff-reviewed nor blocked before the terminal path can mark the task landed.
  Recommendation: Reject report lanes with changes outside the declared report artifact (or submit those paths to the normal diff review) before allowing report-mode review and landing.

Next steps:
- Eliminate pathname races in report harvesting and review.
- Enforce an empty or explicitly allowlisted non-report diff for report-only lanes.
