verdict: APPROVE
next_action: continue

Pool was empty because the resolver never parsed any routing yaml — `.claude/ref/leadv2-routing.yaml` does not exist, so `_emit_fallback(no_routing_yaml)` returned before the `--review-pool` block printed. Reproduced.

- D1 ordered yaml lookup; D2 pool lines on every resolver exit
- D3 floor derived from `review_rank:` data, non-emptiness proved
- D4 resolver reads lockout store (0 refs today); D5 pool/tried never blank

Full: architect.full.md
