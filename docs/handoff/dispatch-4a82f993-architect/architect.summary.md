verdict: APPROVE
next_action: continue

Finisher scoped: codex rollout source must be lane-attributed, not newest-global.

- Sessions root overridable (`LEADV2_CODEX_SESSIONS_ROOT`, `LV2_*` alias); no attributing key → empty, rc 0.
- Candidate filter = mtime window AND sig8-in-body AND existing cwd guard.
- A7 fixture points at empty root; new A9 asserts foreign-sig8 rejection (17→18).

Full: full.md
