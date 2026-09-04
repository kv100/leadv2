verdict: APPROVE
next_action: continue

Choose (a) pinned baseline via a shared `tests/lib/red-first-baseline.sh`; SKIP only when the pin is unusable.

- Mission wrong on one measured point: standalone is also 8/1 on `7de23af`. `HEAD^`=`b680643` *is* the fix merge — arithmetic, not harness context.
- Census: 9 self-invalidating sites — 2 blocking, 1 latent hole, 6 silently vacuous.
- Counterexample: pinning makes the assertion evaluable, not behavioural — S1 greps source text, never runs the path.

Full: architect.full.md
