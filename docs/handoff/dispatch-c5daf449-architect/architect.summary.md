verdict: APPROVE
next_action: continue

A `LANE_DELIVERABLE:` mission line gates a report lane on its file, not its diff; `no_work` becomes unreachable for declared lanes.

- Gate lives in `leadv2-dispatch-product-close.sh` (`pc_scope_diff`), **not** `leadv2-review-run.sh` — the mission named the wrong file.
- Non-trivial = non-whitespace ≥32B + `DELIVERABLE_COMPLETE` marker + fresher than the run dir.
- Unsatisfied → `refused`/`deliverable_missing`; no new ledger word.

Full: architect.full.md
