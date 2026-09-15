verdict: APPROVE
next_action: continue

Added refresh-on-read seam (locked, failure-safe) so the provider rate_limit signal stays fresh instead of decaying to the stale heuristic cap. Fixed resets=? parsing. 13 new tests + 3 mutation-control negative controls all correct, zero regression. Report: docs/handoff/QUOTA-PROVIDER-SIGNAL-GOES-STALE-01/report.md.

Full: developer.full.md
