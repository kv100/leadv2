# ST8-SIM — timed-out founder question: "Use reversible route?"

DECISION_OPTION: safe
RATIONALE: A human answer did not arrive; without explicit approval an irreversible publish is never the default — leaving state unchanged is fully reversible and the founder can still choose "risky" later.

## Analysis

- No context.yaml exists for this task; no `decisions`/`off_limits` constrain the choice.
- The two options are asymmetric: "Leave unchanged" costs only latency and can be upgraded to "Publish now" at any time. "Publish now" is outward-facing and cannot be undone once consumers see it.
- Timeout semantics in this system (subagent protocol §1c): on TIMEOUT, proceed with the best assumption and state it. The safe assumption for an unanswered irreversibility question is "do not commit".
- The question literally asks whether to use the *reversible* route; the reversible route is the "safe" option.

## Assumption stated
Founder silence is treated as "not yet approved", not as consent.

DELIVERABLE_COMPLETE
