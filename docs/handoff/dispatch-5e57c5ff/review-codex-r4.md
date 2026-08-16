# Codex Adversarial Review

Target: branch diff against b90e40ed36d2e2f39d232d859330bb7f5c7c07eb
Verdict: needs-attention

No-ship: report-only lanes still have multiple paths to bypass or break the intended review gate.
REVIEW_VERDICT: fail
REVIEW_FINDINGS: critical=0 high=6 medium=0 low=0

Findings:
- [high] Rename laundering bypass (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1519-1521)
  Filtering the entire porcelain record with `grep -vF` lets a rename such as `agent/seed.py -> analysis/report.md` be treated as allowed report work, so a report verdict can land an unreviewed tracked-source deletion or replacement.
  Recommendation: Parse NUL-delimited porcelain records and allow only a non-rename/non-copy entry whose sole path exactly equals the declared report.
- [high] Committed source changes bypass the guard (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1518-1567)
  The branch clears `blocked_reason` after generating the baseline diff but checks only `git status`, so a worker that commits unrelated source changes leaves a clean status while its unreviewed committed diff is discarded before the report pass.
  Recommendation: Require the dispatch-start-SHA diff to be empty outside the declared report before clearing the diff-gate result.
- [high] Shared-tree fallback bypasses laundering protection (plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1518-1521)
  The only unscoped-work check requires a resolved lane worktree, while dispatch explicitly supports falling back to `PROJECT_ROOT`, so uncommitted source edits made by a worker on that fallback path can receive a report-only pass.
  Recommendation: Fail report lanes closed when no isolated worktree is available, or establish an attributable root-side baseline and scope it before review.
- [high] Recovery loses CLI deliverable overrides (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3889-3912)
  Recovery re-derives the deliverable only from `lane-mission.md`, so a valid higher-precedence `--lane-deliverable` not duplicated in that mission is lost and the replacement close gate reverts to diff-lane behavior.
  Recommendation: Persist the validated declaration with lane state and pass that exact value through `advance-arm` to `spawn_product_close`.
- [high] Repository metadata can be exfiltrated as a report (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:22-61)
  The parser accepts `.git/config` and the locator treats it as contained beneath ROOT, permitting a declared report to copy repository configuration, including credential-bearing remote URLs when present, into the external-review handoff.
  Recommendation: Reject `.git` and other control metadata explicitly and constrain report deliverables to an approved working-tree subtree.
- [high] GNU stat makes report lanes unavailable (plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh:59-60)
  On GNU `stat`, the first `stat -f %l` succeeds but returns the filesystem maximum filename length rather than link count, so the value is normally greater than one and every Linux report is rejected without reaching `stat -c %h`.
  Recommendation: Detect the stat implementation before choosing its format, or try the GNU link-count form first on GNU systems rather than relying on command failure.
