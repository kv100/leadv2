# REVIEW-ROUND-INFLATION-01 — measured findings (2026-09-02)

Subagent census, 30-day window. The agent's Write was refused by a hook, so the lead persisted this.

## Two populations
- **49 named lanes** with `fix-round-N.md` evidence = the round census.
- **467 `docs/handoff/dispatch-<8hex>/` dirs** that NEVER produce a `fix-round-N.md` — they die at the
  dispatch layer: `selfcheck_failed` 32, `no_work` 30, `worker_timeout` 24, `arm_produced_nothing` 19,
  `all_arms_unavailable` 16. Invisible to any round metric.

## Round distribution (49 lanes)
| rounds | 1 | 2 | 3 | 4 | 5 | 7 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|
| lanes | 8 | 17 | 7 | 8 | 4 | 1 | 1 | 1 | 2 |

51% close in 1-2 rounds; 49% need 3+; 5 lanes need 5+.
Worst: DISPATCH-PIN-CLUSTER-01 (11), ANTI-SILENCE-STATUSLINE-01 (11), FABLE-THINK-TIER-01 (10),
DISPATCH-CLOSE-GATE-01 (9), PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 (7).

## Cause taxonomy — the deliverable
**Content-level (98 High/Critical findings across 36 deduped `review-findings*.json`):**
- **A. real code defect — 91 = 93%**
- B. evidence discipline — 7 = 7%
- C. gate malfunction — 0% (gate failures never reach findings JSON at all)
- D. brief defect — 1 self-admitted instance, not the sole cause of its round

**Gate-malfunction axis (separate — produces `status:blocked reason:X`, no findings):**
12 distinct lanes hit `empty_response` / `review_body_lost` / `provider_error` /
`suite_falsifiability_undetermined` / `review_roundcap` in 30d. **8 of the 49 census lanes (16%) are
stuck on a gate malfunction rather than a verdict about their work**, including 2 of the top-5 offenders
(BRAIN-CLASS-LIVE-01 `empty_response`, BROAD-STATUS-ROWS-02 `provider_error`). 3 more lanes die before
producing `fix-round-1.md`.

## Reviewer strictness — the hypothesis that died
15 High/Critical findings sampled every 6th across 17 lanes: **15/15 genuinely blocking.** Zero style,
zero speculation, zero rubber-stamp. Hedge-language scan across all 98 findings: **1 hit**, and it named
a concrete mechanism. The reviewers are not too strict.

## The pattern behind the 11-round lanes
Not eleven different bugs — the same **unfalsifiable test resubmitted**. DISPATCH-PIN-CLUSTER-01 round 1:
"three of the four negative controls are grep-for-a-string assertions... do not execute the production
path"; round 11: "the fail-closed proof passes for the wrong reason" [Critical]. Same shape in
ANTI-SILENCE-STATUSLINE-01. Correctly rejected each time. **Long lanes measure worker misunderstanding of
what evidence is, not task difficulty.**

## Cheapest fixes, in order
1. **Fix `empty_response`/`review_body_lost`/`provider_error` handling**: retry the reviewer capture
   instead of leaving the lane `blocked` in a state indistinguishable from a content fail. Mechanical, no
   judgement. Recovers a floor of **8 lane-rounds**, plus 3 lanes dead pre-round-1, plus 59 same-shape
   failures in the dispatch-layer graveyard.
2. **Pre-dispatch lint rejecting grep-only "negative controls"**: an estimated **4-6 rounds** off
   DISPATCH-PIN-CLUSTER-01 and ANTI-SILENCE-STATUSLINE-01 alone.

93% of blocking findings are real defects that no gate fix will touch. The gate fix stops charging lanes
for the reviewer's own outages; it does not make us write better code.

## Note on method
The subagent's own Write was refused by a hook telling it to return text instead of writing a report.
That hook cost this census its durable artifact — it existed only in the lead's transcript until the lead
copied it here. Worth a look: a diagnosis agent that cannot persist its diagnosis is a diagnosis that
dies with the session.
