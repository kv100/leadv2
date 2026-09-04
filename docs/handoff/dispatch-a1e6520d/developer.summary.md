verdict: APPROVE
next_action: review_round_2

Skill-invocation collector + rollup shipped and green (39/39, both negative controls confirmed red-under-mutation); fixed 3 real bugs found while proving it out.

- Collector wrote non-compact JSON (space after `:`), silently mismatching every downstream grep pattern — fixed with `separators=(',', ':')`.
- Fixed a self-contradictory test fixture (INVOKED_PAST_ONLY vs window-exclusion) and a broken M2 negative-control (missing lock-helper copy).
- Live run against real transcripts: universe=89, 1146 real invocation rows collected, `leadv2-subagent-protocol` = 288 hits.

Full: full.md
