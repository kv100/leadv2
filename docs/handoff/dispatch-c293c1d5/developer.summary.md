verdict: APPROVE
next_action: review_round_2

Effort routing knob now resolved by the arbiter and forwarded to each arm's own launch parameter.

- config/leadv2-routing.yaml: data-driven `effort_matrix` (low/medium/high), no arm/kind hardcoded.
- route-arbiter.sh resolves+prints effort; dispatch-code.sh forwards it (codex `--effort`, sonnet `--effort`) or journals `effort_dropped` for glm/freepool/kimi.
- test-effort-routing.sh: 9/9 green, mutation-killed twice (arbiter + dispatch pass-through), `--scope changed` selection proven.
- Committed: 3ff1c07.

Full: full.md
