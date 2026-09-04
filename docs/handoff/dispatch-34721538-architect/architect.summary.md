verdict: NEEDS-INFO
next_action: continue

Deletion plan scoped; 3 of 4 scripts die, `-resume.sh` must be renamed not deleted (DECISION-A; default A1 if lead is silent).

- `leadv2-lanes-snapshot.sh:138,1394` exec `leadv2-supervise-resume.sh` on live paths and fail *soft* — deleting it degrades silently. `git mv` → `leadv2-lanes-resume.sh`.
- `test-ensure-adopt.sh:27` (not in mission) targets the loop; subject moved to lanes-snapshot → retarget. Other 4 supervisor-named suites: subjects verified alive, KEEP.
- Mission's grep-proof can't go green as worded — `supervise-loop.log`/`.json`/`.heartbeat` are surviving state names. Use a filename-anchored grep.

Full: architect.full.md
