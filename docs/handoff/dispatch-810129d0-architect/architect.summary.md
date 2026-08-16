verdict: APPROVE
next_action: continue

# architect — FORK-RUNS-A-SESSION-01

A fork can own Phases 0–8 via the existing bash lane path, not the tool path.

- Hinge: `leadv2-lane-worktree.sh` already replaces `EnterWorktree` for headless lanes — a fork never enters a tool worktree, so the `ExitWorktree` ban holds by disjointness.
- Three carve-outs to the lead: worktree lifecycle, Phase-8 reaping, daemon self-spawn.
- Gate 1 reuses `leadv2-ask.sh --no-block`; no new founder surface.

Full: architect.full.md
