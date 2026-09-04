verdict: APPROVE
next_action: continue

Round-2 design: drop the run-all.sh branch, add flag+depth re-entry guard, fd-clean group-kill timeout, merge-base baseline attribution, checks=0→DEGRADED.

- Round-1 code is uncommitted in worktree 9c027877; C1/C2 mechanisms confirmed from source.
- 15 red-first cases cover the suite branch; one run_check line registers it; wall <25s.
- 5 lane writes; acceptance at journal/artifact/rendered surfaces.

Full: architect.full.md
