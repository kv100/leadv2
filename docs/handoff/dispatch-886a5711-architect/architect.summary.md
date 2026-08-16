verdict: APPROVE
next_action: continue

Failed beats must rewrite `founder-status.md` as an explicit degraded block, or emit no READY at all.

- `_write_degraded_status` + `_emit_fail_line`; routes **both** failure paths (collector:83 and render:294 — review named only one).
- Reader-side staleness check: ready-line `at=` vs file line-1 stamp.
- Tests T9a–T9d assert on the published artifact, not on READY.

Full: architect.full.md
