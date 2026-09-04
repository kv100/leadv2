---
verdict: REVISE
next_action: continue
---

Design scoped; mission premise corrected twice.

- `explicit_mission_fast_path` is CORRECT (all 17 fixtures start `plugin-only`) — a red herring, not RED-1's cause; rc=4 fires later at one of 5 `exit 4` sites.
- Real leak: `PROJECT_ROOT` (:264) omits `LEADV2_PROJECT_ROOT`, falls through to the live repo.
- r2/r3 edits already committed (4077109), not uncommitted.

Full: architect.full.md
