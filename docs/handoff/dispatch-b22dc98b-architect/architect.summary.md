verdict: APPROVE
next_action: continue

Design complete; two mission premises are wrong and corrected in the design.

- `hour_key` is `YYYY-MM-DD-HH`, not `...THH` — mission's query drops up to 24h of burn (0 at 00:xx UTC).
- New rc 6 hits three untouched caller `case` blocks; `leadv2-fanout.sh` would escalate a refused lane to a full Opus cycle.
- `sqlite3 -readonly` fails on this db; db-locked rc 5 observed live — both fail-open.

Full: architect.full.md
