verdict: APPROVE
next_action: continue

Design ready: extend the existing round counter, move cap enforcement from the lead into the engine.

- Mission's F4 is wrong — a round counter DOES exist (`_review_round_context:592`, `.review-round.state`); computed, never enforced (`phases.md:291`).
- Add `attempts`/`spawns` there; refuse at cap with new rc 8, `status: blocked`, escalation file. Fail-open throughout.
- Dedup exemption (req 4) is itself a money hole — `spawns` backstop covers it.

Full: architect.full.md
