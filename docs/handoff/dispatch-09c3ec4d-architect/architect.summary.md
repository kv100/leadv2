verdict: APPROVE
next_action: continue

# architect — dispatch-09c3ec4d

Reproduced Codex's table: `exec`, `env -i`, `if` are genuinely fail-open; `bash <launcher>` already trips — Codex's 4th row is wrong.

- Fix: 3 strip-loop extensions in `eval_tokens` — `exec`/`env` routed through existing `_next_operand`, plus `CONTROL_WORDS` skip. `LAUNCHER_RE` untouched.
- Tests: 4 new STUB_MODE positives + 2 negatives in `mention`; passed 17→21.

Full: architect.full.md
