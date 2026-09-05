# PREPASS-PROVIDER-FALLBACK-01-R1
Tooling-only repair: implement every requirement in `docs/handoff/CODEX-LEAD-REPAIR-20260824/prepass-provider-fallback.md` in the dispatcher itself.
Also fix the proven off-by-one write-count bug: the current `printf` without a final newline piped to `wc -l` counts one declared path as zero and two as one. Test/validate 0, 1, 2, duplicate, blank, and malformed declarations without using that bug as an admission shortcut.
This is dispatcher infrastructure, not application/product behavior. Preserve all mandatory gates for product missions.
acceptance:
  surface: log_line
  observable: With Claude OAuth unavailable, tooling admission remains available and a multi-file product dispatch either obtains a validated design from another configured architect arm or parks with the authentication cause while releasing its active slot; one and two write paths are counted truthfully.
  authored_at: 2026-08-24T18:39:00Z
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh
