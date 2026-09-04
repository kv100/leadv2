verdict: REVISE
next_action: continue

Guard already exists (4b51d96) but is inert: the plugin cache the runtime loads has neither it nor the manifest row.

- `2>/dev/null` suppresses it entirely — `has_redirect` counts any `>`.
- Misses `git log -p`, `git stash show -p`, `head -c N`.
- No test file; warn is advisory, never a gate.

Full: full.md
