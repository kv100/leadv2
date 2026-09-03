Plan authored by the lead 2026-08-31 from the live refusal logs; gate 1 taken by the lead.
Full plan: docs/handoff/DISPATCH-PHASE-DEADLOCK-01/fix-round-2.md
This lane exists because the phase gate today cannot tell a never-started lane from a lane that skipped planning, so every new lane is refused and the lead has been bypassing the gate with --task-class light. That bypass ends when this lands.
