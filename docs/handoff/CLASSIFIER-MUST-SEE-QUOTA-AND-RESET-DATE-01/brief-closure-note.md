# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 — note for the closure

Recorded 2026-09-03 by the lead, at c2's request, so a later pass does not try to undo this.

## The rule lives inside the arbiter by necessity, not by convenience

The wait-vs-switch rule — *a provider that is over its ceiling but close to its own reset stays in
the chain instead of being forced to switch* — cannot be implemented outside
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`. The decision it changes is the arbiter's own
`capped()` / `util()` verdict; anything outside can only observe that verdict after it has been
made. A future attempt to "keep the arbiter untouched" by wrapping it will reproduce the original
defect: the caller still receives *switch away* and has nothing left to reconsider.

This rule is what the founder meant by asking for a **smart** arbiter. Before it, `capped()` and
`util()` scored only the raw used-pct of the binding window and never looked at when that window
resets, so "85% burned, resets in 20 minutes" and "85% burned, resets in 4 days" produced an
identical verdict.

## The threshold is derived, not picked

10% of the **window's own period**, argued from the two live window shapes rather than chosen
free-hand, and it reproduces both founder examples exactly:

- 20 min left on a 5h window → 0.1 × 5h = 30 min → 20 ≤ 30 → **wait**
- 4 days left on a 7d window → 0.1 × 168h = 16.8h → 96 > 16.8 → **switch**

A window whose reset cannot be read (absent or malformed `reset_iso`) degrades to that window's
**full period** as `hours_to_reset` — always greater than the threshold, so an unknown reset always
reads as "far" and can never fabricate an imminent wait. Never a silent zero.

No new fetcher: `leadv2-quota-read.py` already computes `hours_to_reset` per window and ships it in
the same JSON the arbiter already fetches.

## Ordering, for whoever lands SMART-ARBITER-01 D0–D7

This change goes in **first**, and the D0–D7 redesign lands on top of it — not two independent
redesigns of the same file. c2 asked to see this diff before the merge for exactly that reason.
