verdict: NEEDS-INFO
next_action: continue

# architect.summary — BROAD-STATUS-RELAY-SCOPE-01 round 2

Design closes 3 HIGHs + 5 MEDIUMs; round-1 code is uncommitted in worktree 91f975bf.

- HIGH-1: `.pulse-session.<sid>` heartbeat + owner max_age 1×BEAT_S, no 3600 floor → Scenario E fails open.
- HIGH-2: ownership needs a live lane attributed via `arm-registered` + one new `LEAD_SESSION=` field — write-set extension needs lead OK (D1); setsid lanes make ancestry unusable.
- HIGH-3: T9–T19 drive real state, no seam.

Full: architect.full.md
