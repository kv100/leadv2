# Codex Adversarial Review

Target: branch diff against b90e40ed36d2e2f39d232d859330bb7f5c7c07eb
Verdict: needs-attention

No-ship: six high-impact report-gate bypasses and integrity failures remain, including the accepted pre-existing-file rationale.

Findings:
- [high] Non-product report lanes bypass every close gate (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3648)
  A valid report declaration bypasses the writes guard but `spawn_product_close` runs only when `product_class` is `product`, so natural `docs`, `diagnosis`, or `investigation` report lanes receive no locate, substantive, harvest, or review enforcement.
  Recommendation: Launch an appropriate report close gate for every parsed report declaration, or reject report declarations outside the product class.
- [high] Arm recovery drops report-lane state (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3893-3894)
  The silent-arm retry respawns product close without the declaration, so a recovered report lane is reclassified as a diff lane and can block as no-work despite producing its required report.
  Recommendation: Persist the validated declaration with the lane state and pass it through `advance-arm` into the replacement close gate.
- [high] Hardlinks bypass report containment (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:49-55)
  The locator rejects symlinks but accepts any regular file under a contained directory, allowing a same-volume hardlink to a host file to be harvested and exposed to an external reviewer.
  Recommendation: Reject multi-linked source files using platform-appropriate `stat` link-count checks, or require a newly-created, provenance-bound report artifact.
- [high] A destination symlink can falsely satisfy harvest (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:94-97)
  Because `-f` and `-ef` follow symlinks, a pre-existing handoff `report.md` symlink to the worktree source skips the copy and passes validation, leaving the supposedly durable deliverable dangling after the worktree is swept.
  Recommendation: Reject symlink destinations explicitly before both the regular-file and same-file checks, and verify the final destination with `! -L`.
- [high] Only a prefix of the landed report is reviewed (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1533-1536)
  The gate publishes the complete harvested report but supplies reviewers only the first configured 60,000 bytes, so unsupported conclusions or unsafe content appended after that boundary can land without review.
  Recommendation: Enforce a report-size ceiling or provide and require review coverage for every chunk of the exact harvested-content hash.
- [high] The pre-existing-file acceptance cannot establish task fulfillment (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2001-2005)
  The report reviewer is given only the report-derived `review.diff` and prose rubric rather than the founder mission, so an internally coherent but unrelated pre-existing report can pass and mark the requested task landed.
  Recommendation: Bind the original founder mission and task-specific acceptance criteria into immutable review input and require the reviewer to assess the report against them.

Next steps:
- Block shipment until report declarations are preserved across all dispatch and recovery paths and the harvested artifact is securely, fully reviewed.
