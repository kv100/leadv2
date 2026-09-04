verdict: APPROVE
next_action: continue

Option (a) — pin the baseline via a `-S` pickaxe on the fix's introducing commit, promoted to one shared helper.

- Mission framing wrong: standalone also fails `pass=8 fail=1`; cause is floating `HEAD^`, not harness context.
- Census: 13 baseline sites — 2 armed (parked-worker red now; lane-root detonates on push to origin/main), 5 vacuous, 6 sound.
- Unresolvable baseline → SKIP with reason, never FAIL, never `exit 1`.

Full: architect.full.md
