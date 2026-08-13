verdict: APPROVE
next_action: continue

Keep `5e69c0b` — sound; all four touched suites pass at lane HEAD. Remaining work is evidence, not code.

- `.claude/worktrees/baseline-check` claims a1afed9 but its tree differs (md5 mismatch, no `DISPATCHABLE_BUILD_ARMS`) — it fabricates red. Use a fresh `git worktree add --detach a1afed9`.
- Item 3 cannot fail-against-HEAD; prove via labelled negative-control.
- Add drift `case5`: the `"glm codex sonnet"` fail-open literal ⊆ DISPATCHABLE_BUILD_ARMS.

Full: architect.full.md
