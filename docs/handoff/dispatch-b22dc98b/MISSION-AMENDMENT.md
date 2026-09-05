# MISSION AMENDMENT — BURN-GOVERNOR-01 (from lead, 2026-08-23)

Deliverable 3 (compact-trigger interactive EMERGENCY block) is AMENDED:

Founder order 2026-08-19 (commit 7daf57f in this repo): "never block a founder prompt on turn
count" — the previous turn-cap BLOCK gate was deleted the same day it shipped, by that order.
An interactive decision:block -> /compact at EMERGENCY level is the same class of intervention.

Change: implement the interactive escalation as DEFAULT OFF (LEADV2_COMPACT_INTERACTIVE_BLOCK
default 0, not 1), and in the EMERGENCY warn message state plainly that the session is past
emergency width and name the env to enable auto-block. Blocking must never be the default.
Deliverables 1, 2, 4, 5 unchanged.
