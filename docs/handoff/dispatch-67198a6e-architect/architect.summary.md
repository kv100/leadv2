```yaml
verdict: APPROVE
next_action: continue
```

Design: replace section (c)'s rsync with a per-file link/convert/report pass — three write paths, not one.

- Mission miscounts: only 5 of persona-engine's 28 real `leadv2-*` files have a canonical counterpart; a `leadv2-*` filter would clobber 23 repo-native scripts.
- m3-market DOES have `.claude/scripts` (~/MythicalGames); the yaml path is wrong, so it never syncs.
- Shared tree (b) still re-materializes copies — follow-up.

Full: architect.full.md
