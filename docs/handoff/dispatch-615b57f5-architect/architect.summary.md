```yaml
verdict: APPROVE
next_action: continue
```

Mechanism-closed design for the three BURN-GOVERNOR-01 fixes; no code written.

- Governor has TWO callers, not one: `_burn_gate` (dispatch-code:4769) and `burn-deferred retry-all` (:1174). Test (f) fails via a *grandchild* dispatch — fix must be `export`.
- Finding 3: copy `_lv2_selfcheck_timeout_run` (builder-selfcheck.sh:59) incl. its detached-watcher fix; rc 124 → discard output → existing no_telemetry branch.
- Residual: the two `python3` forks stay unbounded.

Full: architect.full.md
