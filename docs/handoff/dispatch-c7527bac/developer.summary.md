verdict: APPROVE
next_action: review_round_2

Round 4: all four named FLEET-RUNTIME defects fixed, verified, committed.

- Restart=on-failure + SuccessExitStatus=42 (controlled stops never respawned); unit quoting fixed (WorkingDirectory unquoted, Environment= fully quoted); all c*-mut markers removed; guard reap no longer forces.
- Found + fixed a real regression edit 4 exposed: the in-tree `.fleet-terminal` marker itself blocked non-forcing removal — moved to a sibling file.
- 42/42 suite green, 4 done-means greps clean, both mission controls + 1 extra (Group K) RUN with negative sides.

Full: docs/handoff/dispatch-c7527bac/developer.full.md
