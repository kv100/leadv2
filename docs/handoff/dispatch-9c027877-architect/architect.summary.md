verdict: APPROVE
next_action: continue

Selfcheck gate lands between `pc_scope_diff` (:1802) and the e2e stamp (:1817) of dispatch-product-close.sh, backed by a new pure lib; blocks `reason=selfcheck_failed terminal=refused` before any arm is spent.

- Preamble injects at dispatch-code.sh:3610 (post-sig, dedup-safe).
- Suite check delegates to the e2e stage in `auto` — e2e already runs `--scope changed`.
- 6-case red-first suite; review-arm sentinel proves no arm spent.

Full: architect.full.md
