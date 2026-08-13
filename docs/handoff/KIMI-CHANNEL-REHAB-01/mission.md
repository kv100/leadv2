# KIMI-CHANNEL-REHAB-01 — reinstate Kimi arm with mission-shape guards

Repo: ~/Projects/leadv2. Founder order 2026-08-03: the 2026-08-02 Kimi removal (79e239a routing, 5e8730a dispatch ladder) is revertible — root cause of 19/19 empty dispatches was MISSION SHAPE, not the channel.

EVIDENCE (docs/leadv2/open-threads.md KIMI-CHANNEL-REHAB-01 + ~/.claude/cache/kimi-runs/):
- 6 sampled failed runs: exit=0, stop_reason=end_turn, 10–23 turns, reads>0 (often same file re-read), writes=0 — model silently gives up on broad product missions with architect-prepass designs.
- Live micro-probe 260803-031335-kimi-probe-7f36: narrow explicit single-file mission → 4 tool actions, file created+verified, exit 0. Channel works.

WRITE SET: the files touched by 79e239a and 5e8730a (routing yaml + dispatch ladder in plugins/leadv2/scripts/leadv2-dispatch-code.sh or its routing config), plugins/leadv2/scripts/kimi-coder.sh, plus tests.

REQUIREMENTS:
1. Revert the arm removal: restore kimi to the build spill ladder as glm → kimi → codex → sonnet (git revert or equivalent minimal re-add; keep history readable).
2. Admission guard (the actual fix): kimi arm is admissible ONLY for narrow missions — heuristic at dispatch time: mission text ≤ 2500 chars AND declared write-set ≤ 2 files AND no architect-prepass design attached (or an explicit --kimi-fit flag). Non-fitting missions skip kimi in the ladder (journal `kimi_skipped reason=mission_too_broad`).
3. No-work detector: in kimi-coder.sh, after child end_turn — if zero Edit/Write/mutating-Bash tool calls in progress.log AND non-empty mission, exit with the existing channel-bail code (77/78 family, pick the right one) so the caller spills to the next arm and the ledger records `channel_no_work`, NOT a task failure. This must NOT fire when the mission legitimately needs no writes (read-only discovery kind) — gate on mission kind.
4. Tests: extend the existing kimi/dispatch test suites: (a) broad mission → kimi skipped in ladder; (b) narrow mission → kimi admitted; (c) simulated no-write end_turn → bail code + spill; (d) read-only kind + no writes → NOT a bail.

ACCEPTANCE: bash -n all touched; run the repo's dispatch/kimi test suites + run-core-offline.sh (the codex-recursion fixture failure is pre-existing, ignore it). Report per-requirement status + test summary. Do NOT commit; leave diff in tree.

NON-GOALS: no changes to glm/codex arms, no supervisor code, no persona-engine files.
Rollback: git checkout of touched files.
