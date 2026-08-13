verdict: APPROVE
next_action: continue

Revert is a 2-array + 1-yaml re-add; all kimi spawn/rc machinery survived both removal commits.

- Guard `_kimi_admissible` (≤2500 chars AND ≤2 declared writes AND no prepass artifact, or `--kimi-fit`) must be applied at **three** chain-build sites — the router-v2 one is the easy miss.
- No-work bail reuses existing `mission_is_code_shaped` + `work_delta_present`; exit 78, before `finalize_meta`. Strict `== "no"` — `skip` must not bail.

Full: architect.full.md
