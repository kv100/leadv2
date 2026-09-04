verdict: APPROVE
next_action: review_round_2

Worker output gate no longer hard-fails just because `origin/main` is missing — it now tries a chain of base refs, judges output when any resolves, and refuses (rc=2, distinct message) only when none do.

- `lib/leadv2-worker-output-gate.sh`: new `worker_output_gate_resolve_base` tries `origin/<remote-default>`, `origin/main`, `origin/master`, local `main`/`master`, `@{upstream}` in order; logs each failed attempt to stderr; total failure still refuses (rc=2, `worker_output_gate_error`), distinguishable from a worker parse reject (rc=1, `worker_output_gate_reject`).
- New fixture-only suite `test-worker-gate-no-origin.sh`: 9/9 pass, covers all 4 acceptance cases + mutation control (RED reproduces old unconditional refusal, GREEN restores fix).
- `tests/run-all.sh`: added `EXTRA_SUITE_MAP` row + fixed the `--scope changed` stem filter (was `plugins/leadv2/scripts/*.sh` only, missed `scripts/lib/*.sh` entirely) — selection proven against the exact production matching logic.

Full: full.md
