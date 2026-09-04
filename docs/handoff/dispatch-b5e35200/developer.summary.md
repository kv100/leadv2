verdict: APPROVE
next_action: review_round_2

Fixed guard-census parser (regex .sh capture) + dispatcher-follow (MANIFEST routing) + runner-side ran/verdict recording in leadv2-bash-pre-dispatch.sh.
- Real-tree re-run: missing 31->1, not-wired 53->13 (remaining rows are genuine gaps, not parser bugs).
- 6 new test cases incl. 2 mutation negative controls, all green (29/29); registered already in run-all.sh.
- Deferred: centralized ran-recording for the ~110 guards wired directly in hooks.json (would require editing hooks.json, outside LANE_WRITES); extra founder columns; per-guard fixture expansion.
Full: full.md
