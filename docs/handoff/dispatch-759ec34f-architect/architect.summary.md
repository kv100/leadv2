verdict: APPROVE
next_action: continue

# architect.summary — ARM-LADDER-KIMI-RESURRECTED-01 (fix r1)

Design scoped: kimi retired via `dispatch: false` (loader already honours it), unknown-arm ⇒ sonnet + journalled mismatch, quota lockout wired to `refusal_reason`, plus drift/degraded/spawn-fence tests.

- Two `_build_candidate_chain` call sites (`:2975`, `:3203`) — review missed `:3203`.
- `_candidate_chain_for_arm` not fully dead: `test-dispatch-arm-vocabulary.sh` extracts it; repoint then delete.
- Tenant-yaml resurrection guard (`DISPATCHABLE_BUILD_ARMS` runtime filter) required, not optional.

Full: architect.full.md
