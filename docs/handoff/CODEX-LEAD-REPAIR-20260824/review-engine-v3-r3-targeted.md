# REVIEW-ENGINE-V3-CORE-01-R3-TARGETED

Targeted continuation on worktree `b4e2f354` at `11c82f0`. Fix only the three
reproducible High findings; do not run another broad redesign.

1. Keep the paid attempt/spawn cap per task across diff hashes. A changed diff may
   reset diff-specific findings/mode, but must not reset task-total attempts or
   spawns. The sequence remains one exhaustive pass plus at most one targeted
   blocker recheck. Preserve legacy/corrupt-state fail-closed behavior.
2. Load `leadv2_review_signals` in the parent shell before risk/security selection;
   do not rely on a function sourced inside command substitution. Protected/high-
   risk changes must automatically enable the security pass. Missing/broken risk
   signals fail closed rather than silently disabling escalation.
3. Critical/High findings from the security pass are blocking and participate in
   the terminal verdict exactly like critic High findings. A critic PASS cannot
   override a blocking security result.

Add the review probes as executable fixtures and restore all failing legacy
roundcap cases. Run focused v3 plus legacy roundcap/exhaustive/pool suites. Commit
the two authorized files and leave clean.

acceptance:
  surface: review_gate
  observable: A task cannot buy more than two review passes by changing diffs, protected changes run security automatically, and security High findings block the gate.
  authored_at: 2026-08-24T21:48:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-engine-v3-core.sh
