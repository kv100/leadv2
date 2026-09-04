verdict: APPROVE
next_action: review_round_2

Shellcheck exclusion widening reverted to main's baseline; the real findings fixed at source (2 SC2016 backtick-copy printf lines, 1 SC2004 array index — mission cited 3/2, actual measured was 2/1).

- `shellcheck -x -e SC1091,SC2034,SC2094 leadv2-review-run.sh` exits 0.
- 30/30 runs green (exhaustive 24/0, roundcap 14/0, codex-dead-reroute 11/0, x10 each).
- T12 negative control done manually (not via leadv2-mutation-control.sh — see full.md for why); revert reddened exactly T12, baseline_rc=0/mutated_rc=1.

Full: full.md
