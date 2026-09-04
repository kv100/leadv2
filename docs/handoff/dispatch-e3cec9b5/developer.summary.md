verdict: APPROVE
next_action: review_round_2

Replaced the name-based handoff-doc allowlist with a scoped `!docs/handoff/*/*.md` rule and added mirror-proving tests.

- `.gitignore`: one `!docs/handoff/*/*.md` line replaces 8 per-name negations; context.yaml/.gate1-passed/round*-red keep separate exceptions.
- New checks 5 (never-enumerated names stage) and 6 (non-doc siblings stay ignored) in test-handoff-artifacts-tracked.sh; both mutation controls fire (rc=1) as designed.
- Committed as `da64ac0e`.

Full: full.md
