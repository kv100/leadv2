# FOUNDER-LANE-VIEW-01 — see every live lane

- **Command:** `bash plugins/leadv2/scripts/leadv2-lanes.sh` (add `--json` for machine rows, `--all` for the old full/dead listing). Liveness is judged by process existence — a lane that is running but has written no log yet still shows.
- **Columns:** `lane id · @repo (only when >1 repo has lanes) · arm (glm/kimi/codex/claude) · title · run <how long its oldest process has run> · <last artifact touched> <age> ago · phase or gate status`.
- **Watch one lane live:** `tail -f docs/handoff/<lane-id>/*.stream.jsonl` (e.g. `tail -f docs/handoff/dispatch-886a5711/developer.stream.jsonl`).
