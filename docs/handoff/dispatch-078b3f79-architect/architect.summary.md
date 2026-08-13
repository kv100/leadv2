verdict: APPROVE
next_action: continue

Root cause is the test stub, not the detector: real `codex exec --json` emits `item.command_execution`, never `response_item/function_call`.

- Mechanism 1 disproved — :432 `wc -c <` noise, no functional effect.
- Fix stub to production shape; add missing FALSEKILL negative cases (none exist).
- Detector untouched.

Full: architect.full.md
