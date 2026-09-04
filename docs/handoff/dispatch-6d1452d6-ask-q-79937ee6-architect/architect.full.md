# Architect decision — BEAT-LOOP-ORPHANS-01 r2 fail-closed vs founder blindness

DECISION_OPTION: a
RATIONALE: A loop that arms on a misclassified session is self-perpetuating damage; a loop that doesn't arm is a visible, non-propagating journal row — fail closed is the correct default for anything that self-perpetuates, and the founder case is solved mechanically by the LEADV2_SESSION_KIND=lead pin, not by heuristic inference.

## Context

Reviewer requirement (r2): transcript-content classifier; unknown MUST NOT arm a beat loop (fail closed). Conflict raised: the founder's lead session runs at repo root, founder-typed first message, no env pin — under strict fail-closed it classifies unknown, so the founder beat loop never arms → founder blindness, the failure the loop exists to kill. Prior thread q-1ba6ae9f chose fail-open+journal.

## Why option (a), not (b)

1. **Asymmetry of failure modes.** Arming on a misclassified session spawns automated dispatches that no human asked for — silent, self-perpetuating, expensive. Not arming on a misclassified founder session produces a `session_kind=unknown` journal row: visible, inert, one-time. For a mechanism whose whole job is to fire autonomously, the conservative error direction is "didn't fire," not "fired wrong." Option (b) concedes this itself: its residual case ("root-cwd unpinned workers fail open to lead") recreates the exact hazard the reviewer flagged — a worker classified as lead arms a loop about itself. That is fail-open by another name.
2. **(b) is inference from absence of evidence.** "No mission markers in transcript" proves a marker-stamping path didn't run; it does not prove lead. Any spawn path that doesn't stamp markers (a new script, a manual `claude -p`, a third-party wrapper) silently classifies as lead and arms. Cwd-munging (`-claude-worktrees-`) is an artifact of this repo's worktree convention, not a property of session identity — it breaks silently if the convention changes and ports to nothing else. The reviewer asked for a content classifier precisely to get away from this class of heuristic.
3. **Decision-history conflict, resolved deliberately.** q-1ba6ae9f's fail-open+journal predates the r2 review requirement. Protocol says conflicts surface, not work around: **LEAD_ACTION: record that q-1ba6ae9f's fail-open choice is superseded for the classifier's unknown class**; the journal line is retained as the visibility mitigation, which is the part of that decision worth keeping.

## Founder-blindness mitigation (the real risk in (a), and it is bounded)

- The founder lead session must be launched with `LEADV2_SESSION_KIND=lead` pinned (settings.json `env` block for that session or the launching shell profile). Naming follows the `LEADV2_*` convention; no new env var is introduced by this decision.
- Starvation is observable, not silent: any `session_kind=unknown` journal row for a repo-root session means the pin is missing. One grep after the first founder session under the new classifier confirms the pin works.
- report.md must document the pin as required founder-side wiring (option a's own text).

## Required work under (a) (for the implementing agent — this decision implements nothing)

1. Classifier reads transcript content; classification result `unknown` → do not arm, write journal line with `session_kind=unknown`.
2. Document `LEADV2_SESSION_KIND=lead` pin in report.md as required founder-side wiring.
3. Lead records supersession of q-1ba6ae9f's fail-open choice for unknown (see LEAD_ACTION above).

## Risks

| Risk | Mitigation |
|---|---|
| Founder pin never wired → founder blindness | Journal `unknown` rows are the probe; documented pin in report.md; one-time post-deploy check of the first founder session's classification |
| Decision conflict with q-1ba6ae9f | Explicit supersession recorded by lead (LEAD_ACTION), journal visibility retained |
| Env pin name drift across launch paths | Same name must be used at every launch site; commit 38be66c already pinned all `claude -p` sites — founder session is the remaining one |

## Self-check (mandatory constraint checklist)

1. Env vars: no new env var introduced; `LEADV2_SESSION_KIND` follows `LEADV2_*` convention — consistent, no drift flagged.
2. Paths: no `reads`/`writes` beyond these two deliverables; `context.yaml` does not exist for this task (verified) — mission text is the binding source.
3. `claude -p`: no `claude -p` invocation specified by this decision.
4. Concurrent access: deliverables are single-writer (this role only).
5. Config contradictions: none — this decision changes no config; it only selects classification semantics already briefed.

## Out of scope

- Implementing the classifier or journal line (developer lane).
- Wiring the founder pin into the founder session environment.
- Any change to loop arming for explicitly classified kinds.

DELIVERABLE_COMPLETE
