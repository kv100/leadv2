verdict: APPROVE
next_action: continue

Mechanism-closed design for WORKER-PARKED-ON-BG-01, plus one framing correction.

- Measured lane b7bcf98a is arm=**sonnet**; only glm/kimi run the outcome classifier and have a resume launcher, so half B hardens glm/kimi only — half A covers all four arms.
- New `parked` outcome token + widened `pc_dwr_resume_once` gate; three token readers updated.
- Checkpoint wording made arm-agnostic via a shared parked-detect lib.

Full: architect.full.md
