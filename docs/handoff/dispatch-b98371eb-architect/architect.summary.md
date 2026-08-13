verdict: APPROVE
next_action: continue

Merge the classification, not the census: extract `classify()` into a shared
`leadv2-lane-class.py` both heredocs load; `render_single_lead` becomes a live-only
projection over it.

- Censuses read different sources — merging them is a rewrite; classification drift is what
  broke the panel and fits this budget. Discovery-parity gap stated as R-7.
- Defect 2 (`sig <hex8>` row) already fixed in `.5s.sh`; locked by assertion, no new code.
- Deleting `terminals unreadable` inverts single-lead:416 — rewrite in place, suite stays 23/0.
  Baseline verified green: 23/15/12.

Full: architect.full.md
