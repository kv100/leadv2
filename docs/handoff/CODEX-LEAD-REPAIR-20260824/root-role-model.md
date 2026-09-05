# CODEX-LEAD-ROOT-ROLE-MODEL-01

Make the Codex root-lead contract internally consistent and launchable.

Premise:
- The marketplace `leadv2` skill says Codex is the root brain, while the separately installed `source-command-leadv2` skill describes a Codex child under a Claude/Opus parent and has overlapping trigger language.
- The runbook currently launches `gpt-5.6-sol` with `xhigh`, contrary to the founder's chosen root configuration: `gpt-5.6-terra` with `high` reasoning effort.
- The runbook still says WIP=1 even though runtime state supports `hard_limit: 5`, `standard_max: 4`, and `heavy_max: 3`. The founder explicitly rejected fixed WIP=1.

Required behavior:
1. Disambiguate root-lead and child-session skills so a founder starting leadv2 in a normal Codex chat always gets the root orchestrator; the child skill triggers only when runner-owned child-session evidence is present.
2. Make the supported CLI root launch select `gpt-5.6-terra` and `model_reasoning_effort=high`. Add a small launcher/check if that is the only reliable way to make the root configuration deterministic; do not claim a skill can mutate the already-running model.
3. Update the root skill/runbook from fixed WIP=1 to dynamic bounded concurrency: use canonical runtime limits, quota/lockout state, task class, and exact write-set overlap. Independent lanes may run in parallel; overlapping writes serialize.
4. Preserve root/worker separation: root thinks/routes/reviews/closes; workers may be GLM, Sonnet/Opus, or Codex as selected by dispatcher.
5. Make the startup mismatch visible and actionable in both CLI and desktop-app guidance. Existing wrong-model sessions must not be falsely reported as corrected.
6. Add focused tests/static assertions for the role trigger boundary, Terra/high launch contract, and absence of fixed WIP=1 in the root workflow.

Non-goals:
- Do not edit worker tier mapping in `codex-task.sh` or smart-router scoring.
- Do not modify pulse hook files or the pre-tool guard adapter.

acceptance:
  surface: rendered_line
  observable: Starting the documented root workflow clearly identifies Codex as root lead on Terra/high, while a runner-created child identifies itself as non-dispatching child; independent lanes are allowed up to live runtime limits.
  authored_at: 2026-08-24T18:25:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2/SKILL.md,plugins/leadv2/codex-skills/source-command-leadv2/SKILL.md,plugins/leadv2/docs/codex-lead-AGENTS-pilot.md,plugins/leadv2/docs/codex-lead-pilot-runbook.md,plugins/leadv2/codex-lead/launch-root.sh,plugins/leadv2/codex-lead/tests/test-codex-root-contract.sh
