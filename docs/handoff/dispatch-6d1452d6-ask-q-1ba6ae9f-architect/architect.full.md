# architect.full.md — dispatch-6d1452d6 (ask-timeout decision)

DECISION_OPTION: a
RATIONALE: Worker-detection is already fully covered by live env exports (glm-coder.sh, freepool-coder.sh) plus the run-dir/transcript path signal (~/.claude/cache/{glm,kimi}-runs/<run-id>/, docs/handoff/<task>/), with fail-open+journal for unknown sessions — option (b) expands LANE_WRITES mid-lane for a redundant change, cost with no functional gain.

## Decision

Option **(a)** — skip the launcher edits (no `LEADV2_WORKER_ARM=1` export added to kimi-coder.sh or claude-subsession.sh this lane).

## Basis

1. **The mission's own goal (orphan detection) is already met.** Verified from the launcher headers:
   - `plugins/leadv2/scripts/kimi-coder.sh:27` — kimi runs are journaled under `~/.claude/cache/kimi-runs/<run-id>/` ("v2 workbench: `bg` detaches immediately and runs under ~/.claude/cache/kimi-runs/<run-id>/"). It is an explicit structural clone of glm-coder.sh, which uses `~/.claude/cache/glm-runs/<run-id>/` (`glm-coder.sh:8`). So the `*-runs/<id>` transcript-path signal stated in the question is real and covers the kimi channel even without the env export.
   - `claude-subsession.sh` sessions write under `docs/handoff/<task>/`, which the path signal also covers (per the question's evidence; consistent with the handoff-discipline protocol that mandates that directory).
2. **Residual risk is bounded and fail-safe.** Sessions matching neither signal fall into the existing fail-open arm + journal path — they are *logged as unknown*, not silently accepted. That is the correct conservative default for a sweep whose failure mode is "terminate a legitimate worker".
3. **Option (b) is a mid-lane scope expansion for a redundant change.** LANE_WRITES exists to bound blast radius of a lane; expanding it to two files that per-churn history are heavily edited (both are in the current dirty set alongside 8 other plugin scripts) buys zero detection capability. Consistent with prior ask-timeout rulings on this lane family (dispatch-a288d3f8, dispatch-6280f73a): skip scope expansion when the in-lane evidence already covers the requirement; expand only when the brief's requirement is *not otherwise met* (dispatch-168e6ff1, where owner-stamping was explicitly required and uncovered).
4. **If a future gap shows up** (a real worker class that neither exports the env var nor leaves a recognizable run-dir), the right fix is a dedicated tiny task that edits both launchers once in canonical `~/Projects/leadv2` with the LANE_WRITES expansion decided up front — not a mid-lane graft.

## What the lane should do with this answer

- Proceed on option (a): no edits to kimi-coder.sh / claude-subsession.sh.
- Note the deferred item in the deliverable/STATE: "LEADV2_WORKER_ARM export in kimi-coder.sh + claude-subsession.sh — deferred; detection covered by env (glm/freepool) + run-dir path signal; revisit only if an unknown-worker class appears in the journal."

## Constraints checklist

- Env var naming: `LEADV2_WORKER_ARM` follows `LEADV2_*` convention — but no env var is introduced under option (a); nothing to cross-check in settings.json.
- Paths: both launchers exist and were spot-read; no new files proposed.
- No `claude -p` invocations in this decision.
- Concurrent access: n/a — decision-only, no writes outside this handoff dir.
- Config contradiction check: n/a for (a). Under (b) it would have been required (two launchers would start exporting a var two others already export — semantics consistent, but the write-set expansion is the blocking issue, not the var).

DELIVERABLE_COMPLETE
