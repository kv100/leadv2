# Codex Adversarial Review

Target: branch diff against b90e40ed36d2e2f39d232d859330bb7f5c7c07eb
Verdict: needs-attention

Do not ship: report-only gates can falsely land unproduced, non-durable, or differently reviewed artifacts. REVIEW_VERDICT: fail; REVIEW_FINDINGS: critical=0 high=5 medium=0 low=0

Findings:
- [high] Pre-existing files satisfy a new report deliverable (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:43-45)
  The locator and size-only substantive check accept any inherited file in the lane or main checkout, so `report:README.md` can pass after the worker produces no report and bypasses the normal no-diff/no-writes protection.
  Recommendation: Record the declared file’s pre-dispatch digest/absence and require a lane-attributable post-worker change before accepting it.
- [high] Report paths can exfiltrate files outside the repository (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:43-44)
  `-f` and the subsequent copy dereference symlinks, so a report path pointing to a symlink in the worktree can harvest and submit any readable host file to the handoff and external reviewer.
  Recommendation: Reject symlinks and verify the canonical source path remains beneath the selected worktree or repository root before reading it.
- [high] Harvest success is not verified before landing (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1513-1514)
  The caller ignores `lv2_report_harvest` failure, and an existing `report.md` directory makes `mv` place the temporary file inside that directory while returning success, allowing a pass that advertises a non-file deliverable which disappears with the worktree.
  Recommendation: Fail closed unless harvest succeeds and the advertised destination is a regular non-symlink file containing the expected digest.
- [high] The reviewed bytes are not the harvested deliverable (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1522-1527)
  After harvest, the review input is read from the mutable worktree source rather than `_pc_report_dest`, so a surviving child or worktree sweep can replace or remove it and cause review to approve different bytes from the canonical report.
  Recommendation: Build `review.diff` from the harvested destination, then revalidate and bind its digest to the review and terminal record.
- [high] Review-engine mode drops report-only semantics (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1788-1793)
  With `LEADV2_REVIEW_ENGINE=1`, report lanes enter the generic engine without kind, deliverable, or prose-rubric context, so a PASS produces the diff-shaped gate and landed terminal without the harvested report metadata.
  Recommendation: Pass report metadata and the prose rubric through the engine and make its pass/terminal writers emit the report contract, or prohibit engine mode for report lanes.

Next steps:
- Fix the five high-severity integrity gaps and add regression cases for stale files, symlinks, destination collisions, post-harvest mutation, and review-engine mode.
