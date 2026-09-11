# Review round cap reached

Task `41d918c32ef0` has been reviewed 2 time(s) without converging to a passing verdict (configured maximum: 2). The engine is refusing to spend another review round on it.

This lane needs architect escalation or PARK — a human or the lead must decide next steps.

Next step, by name: Skill(leadv2-judge) mode=review — do not hand-write an
equivalent Agent prompt — the skill carries the verdict vocabulary and the mode
contract, a hand-written one carries neither and leaves no record.
Raise the limit for one more attempt with LEADV2_REVIEW_MAX_ROUNDS, or set it to 0 to disable the cap entirely.
