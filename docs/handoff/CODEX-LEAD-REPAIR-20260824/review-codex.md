[provider-quota-gate] OK — codex 60% < 95%
# Codex Adversarial Review

Target: branch diff against e3ed68c9294ebade15c23b33fc0493b97dabdb93
Verdict: needs-attention

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=5 medium=0 low=0
No-ship: active-slot release can delete a live foreign row, registrar-output failure can abort dispatch, fallback worktrees leak on signals, rollback is misrepresented, and launcher contracts have no executable evidence.

Findings:
- [high] Active-slot release is not owner-safe (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3527)
  FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=3527 dimension=correctness desc=The supposed owner check fails open on missing or unreadable YAML (3489-3501) and is separated from the bare task-id unregister, so a concurrent row refresh or worker handoff can still erase a foreign or live lane row.
  Recommendation: Implement registry-locked compare-and-delete requiring the captured session ID and PID role, and never unregister when ownership cannot be read.
- [high] Registrar output can terminate dispatch (plugins/leadv2/scripts/leadv2-dispatch-code.sh:5328)
  FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=5328 dimension=correctness desc=After sourcing the registry enables errexit and pipefail, so a register failure or nonmatching session ID makes this unguarded assignment pipeline return nonzero (controlled shell probe rc=1) and exits cmd_resolve before active_register_miss or cleanup can run.
  Recommendation: Put the pipeline in an explicit conditional that captures its status and treats malformed or failed registration as the documented non-fatal miss.
- [high] Signal exits leak disposable worktrees (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3394)
  FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=3394 dimension=correctness desc=An INT or TERM after worktree creation and before line 3449 invokes only the global exit cleanup, which has no ws_base, leaving the disposable checkout registered and on disk despite the every-terminal-path promise.
  Recommendation: Register the fallback workspace in signal-safe cleanup state immediately after creation and remove it from the global EXIT handler as well as normal returns.
- [high] The documented rollback is false (plugins/leadv2/scripts/leadv2-dispatch-code.sh:589-590)
  FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=589 dimension=design desc=Setting LEADV2_DISPATCH_ARCHITECT_FALLBACK=0 cannot restore the advertised byte-for-byte prior behavior because the same diff still changes CSV admission counting, v2 refusal handling, and preregistered-slot cleanup.
  Recommendation: Either scope every behavioral change behind the rollback switch or correct the contract and provide independent rollback controls for the other changes.
- [high] Fallback API contracts are untested (plugins/leadv2/scripts/leadv2-dispatch-code.sh:3290-3380)
  FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=3290 dimension=correctness desc=The Git worktree, descendant-kill, Codex, and GLM contracts driving fallback have no required live probe because the only added test explicitly never runs Git, the dispatcher, registry, or launchers and merely greps text and duplicates classifier logic.
  Recommendation: Add subprocess integration tests in a temporary Git repository with stubbed Codex and GLM launchers that exercise success, nonzero exit, timeout, signal cleanup, and registry ownership races.

Next steps:
- Fix the ownership release and registrar pipeline before merge.
- Add executable fallback integration coverage, including signal interruption.
- Re-state or implement the promised rollback boundary.
