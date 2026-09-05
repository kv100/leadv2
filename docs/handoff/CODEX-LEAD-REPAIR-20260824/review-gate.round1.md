arms: codex
fanout: 1/1 degraded=false launched=1 pool_ok=1 source=pool reason=none excluded=-
verified: 0/0
status: fail
critical: 0
high: 4
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/leadv2-dispatch-code.sh:3335 — Both fallback branches invoke code-capable launchers with --cwd ${PROJECT_ROOT} and no read-only or architect isolation boundary, so a model deviation can modify the shared checkou…
- [High] plugins/leadv2/scripts/leadv2-dispatch-code.sh:3377 — The new cleanup deletes by shared reg_id without a PID or registration token, so a concurrent retry that parks can remove another live worker's active row and bypass supervision/ca…
- [High] plugins/leadv2/scripts/leadv2-dispatch-code.sh:3365 — The added every-exit release contract is not met because no-worker exits at 5453, 5497, 5508, 5526, 5536, 5608, 5639, 5656, 5684, 5937, 5960, 5965, and 5983 still leave the pre-reg…
- [High] plugins/leadv2/scripts/leadv2-dispatch-code.sh:3230 — The decision-driving mappings from provider text to auth/rate/quota classes at 3230-3232 and the Codex/GLM launcher-output contracts at 3307-3310 and 3335-3350 have neither inline…
report: docs/handoff/dispatch-PREPASS-PROVIDER-FALLBACK-01-R4/review-codex.md
