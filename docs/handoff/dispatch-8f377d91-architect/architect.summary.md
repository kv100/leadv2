verdict: APPROVE
next_action: continue

Design locked for C1-C3/H1-H3/M1-M5 on lane eb2d7143.

- C1: park+count also on the precheck bench path (new reason `glm_refused_quota_precheck`); counter keyed by distinct sig8/day; shared-cache harness workaround deleted.
- C2/C3/H3: mission parked to `docs/leadv2/glm-deferred.d/<sig8>.md`; retry dispatches a NEW sig8, terminal row reaps instead of blocking; retire only on rc=0; six new suite legs.
- H1/H2/M1-M5: `.gitignore` committed (+`*.lock`, `glm-deferred.d/`), 4 bare `flock 8` → `lv2_lock_wait`, dead helper + SC2034 locals deleted.

Full: architect.full.md
