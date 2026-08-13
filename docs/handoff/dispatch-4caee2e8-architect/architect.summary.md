verdict: APPROVE
next_action: continue

Cause is nesting, not re-exec: `pc_scope_diff()` spans 843–1216, so the new helpers
(946–1064) exist only once it runs at 1277 — after the 1267 call.

- A: hoist 932–940 + 946–1064 above line 843 (verbatim, `_pc_arm_advance` included).
- B: line 1162 needs pathspec `.` — untracked work invisible; that is Case 2.
- C: drop `<<<` from the new suite.

Full: architect.full.md
