verdict: APPROVE
next_action: continue

Design report written to `docs/audits/seamless-account-switching-fable.md`; resume is bound to the config root, not the account, and works cross-account by absolute path (measured).

- `/switch` (ccswitch.sh) rotates a Keychain record neither live root reads; token stale since 2026-08-25.
- Team max_5x usage endpoint answered 200 today; burn history 94 ok / 17 unauth — "401 by design" refuted.
- Ranked fixes: cross-root resume wrapper, retire /switch, lane re-raise by path, balancer signal layering.

Full: full.md
