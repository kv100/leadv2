# PREPASS-PROVIDER-FALLBACK-01-R2
Tooling-only bootstrap repair: implement every requirement in `prepass-provider-fallback.md` and `prepass-provider-fallback-r1.md` in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.
Live retry evidence: smart-router v2 returned `router_v2_unavailable rc=1` before worker launch, so this bootstrap dispatch uses the documented legacy rollback. The implementation must diagnose/fix that v2 refusal path as part of truthful architect fallback, but must not silently make legacy routing the final default.
Preserve mandatory product gates and add no new provider CLI bypass.
acceptance:
  surface: log_line
  observable: With Claude OAuth unavailable, tooling admission remains available and a multi-file product dispatch either obtains a validated design from another configured architect arm or parks with the authentication cause while releasing its active slot; one and two write paths are counted truthfully and router-v2 refusal is actionable.
  authored_at: 2026-08-24T18:42:00Z
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh
