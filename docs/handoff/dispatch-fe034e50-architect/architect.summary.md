verdict: APPROVE
next_action: continue

Root cause is the fixture HOME, not the worktree: the guard test already overrides PROJECT_ROOT, so only `$HOME/.claude/leadv2-shared` kept it green.

- Fix sibling-first resolution in fanout.sh:49 **and** the unnamed twin at fanout-lane-launcher.sh:82; stage the helper into the test sandbox.
- Ladder (d) is red on main under real HOME too — not an env leak.

Full: architect.full.md
