# MERGE-UP-PHASE8-GATES-01 — merge diverged phase8 gate copies into canonical (P1, Standard)

Repo: canonical leadv2 plugin. Context: docs/leadv2/freepool-backlog.md §MERGE-UP-PHASE8-GATES-01.

Facts (verified 2026-08-28): the leadv2 repo's OWN farm holds two REAL copies (not symlinks),
both mtime 2026-08-17, diverged BOTH WAYS vs canonical plugins/leadv2/scripts/:
- .claude/scripts/leadv2-phase8-assert.sh — 22 diff lines. Local carries the 08-17
  CLOSE-GATE-BYPASSABLE-BY-ENV-01 hardening canonical never received.
- .claude/scripts/leadv2-phase8-e2e-gate.sh — 48 diff lines. Same hardening; canonical
  meanwhile got newer fixes (GATE-WRONG-ROOT-FALSE-DEAD-01 813e564, GATE-FOREIGN-FAILURE-01
  3783c57, 6be3635) the copies lack.

Task — a real two-way merge UP into canonical, then symlink:
1. For each file: diff copy vs canonical. Identify the hardening hunks present ONLY in the
   copy (CLOSE-GATE-BYPASSABLE-BY-ENV-01: env-bypass refusals in the close gate path) and
   port them into canonical plugins/leadv2/scripts/<file>, preserving canonical's newer
   logic. NEVER take the copy wholesale — canonical is ahead elsewhere.
2. bash -n both canonical files; run the existing phase8/e2e gate test suites
   (plugins/leadv2/scripts/tests/ — grep for suites covering phase8-assert / e2e-gate) and
   any suite the ported hunks reference. All green.
3. Negative control, RUN red: in a scratch copy revert ONE ported hardening hunk -> the
   suite covering it (add a minimal test if none exists) must fail.
4. Replace both real copies in .claude/scripts/ with symlinks to
   ../../plugins/leadv2/scripts/<file> (relative, matching the farm's existing style —
   check how sibling symlinks there are shaped first).
5. Commit: fix(leadv2): MERGE-UP-PHASE8-GATES-01 — port 08-17 CLOSE-GATE hardening into
   canonical phase8 gates, symlink the farm copies.
Report: docs/handoff/MERGE-UP-PHASE8-GATES-01/report.md (max 250 words, raw suite tails),
end DELIVERABLE_COMPLETE.
