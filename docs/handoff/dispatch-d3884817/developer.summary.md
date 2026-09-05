verdict: APPROVE
next_action: review_round_2

Refusal now names the blocker: `_emit_writeset_refusal` parses registry stderr into `writeset_pending`/`writeset_overlap` with `blocked_by=`, both call sites wired, legacy fallback and both comments left truthful.
- Both call sites (`:7056`/`:7240` pre-edit) now capture stderr instead of discarding it.
- `test-writeset-refusal-names-blocker.sh`: 4/4 PASS (pending, overlap, distinguishability, negative control).
- No caller of the string `writeset_conflict` broke (grep-verified); one commit staged.

Full: full.md
