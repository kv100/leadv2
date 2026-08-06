# Sentinel Inventory — LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01

## Runner sentinel inventory (mission requirement 1)

| Runner | Run dir | Lane→run-dir mapping | Completion sentinel | pgid file |
|---|---|---|---|---|
| **glm** (`leadv2-glm-session-runner.sh` → `glm-coder.sh`) | `${GLM_RUNS_DIR:-~/.claude/cache/glm-runs}/<run_id>` | `docs/handoff/<tid>/.glm-session-runner.run-id` | **`.finalized`** (yes) | yes |
| **kimi** (`leadv2-kimi-session-runner.sh` → `kimi-coder.sh`) | `${KIMI_RUNS_DIR:-~/.claude/cache/kimi-runs}/<run_id>` | `docs/handoff/<tid>/.kimi-session-runner.run-id` | **`.finalized`** (yes) | yes |
| **codex** (`codex-task.sh`) | no run dir; state lives in `<state_root>/*/jobs/<id>.json` | `docs/handoff/<tid>/codex-plan.json` → `job_id` | **NONE — no filesystem completion sentinel.** Already covered by the existing `provider_status` path | no |
| **claude-subsession** (`leadv2-claude-subsession.sh`, `claude-subsession.sh`) | no run dir | n/a | **NONE.** No sentinel exists | no |

## Decision rationale

- `.done` is **rejected**: it is the watchdog's stop condition, set before finalization. Using it would declare lanes dead during finalize.
- `.outcome` is **display-only**: corroborating signal, never gates the verdict.
- `.finalized` is **the** completion sentinel: written by the runner itself after finalization.
- Positive death proof: `pgid` file + `os.kill(-pgid, 0)` raising `ProcessLookupError`.
