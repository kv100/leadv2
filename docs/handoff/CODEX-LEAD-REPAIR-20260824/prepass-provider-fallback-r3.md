# PREPASS-PROVIDER-FALLBACK-01-R3

Continue the tooling-only bootstrap repair from `prepass-provider-fallback-r2.md`.
The preceding GLM run completed diagnosis but made no source changes because the
session-wide Bash tool budget stopped it at 50 calls. This retry is launched
with `LEADV2_TOOL_HARD_LIMIT=200`; do not repeat broad discovery.

Implement every requirement from:

- `prepass-provider-fallback.md`
- `prepass-provider-fallback-r1.md`
- `prepass-provider-fallback-r2.md`

Use the prior diagnosis as a lead, but independently falsify it before changing
behavior. Keep the exact write boundary:

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`

The result must include a descriptive commit and the raw required self-checks.

acceptance:
  surface: log_line
  observable: The dispatcher truthfully counts write paths, reports actionable architect/provider and router-v2 failures, releases active capacity when parking, and can use an existing configured architect arm without bypassing provider launchers or mandatory product gates.
  authored_at: 2026-08-24T18:41:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh
