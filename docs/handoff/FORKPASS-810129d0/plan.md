# Plan — FORKPASS-810129d0 (Phase 2, Light: single-file, no triad required)

Goal: bump `plugins/leadv2/.claude-plugin/plugin.json` version for the
fork-owned-session capability added by FORK-RUNS-A-SESSION-01 (leadv2-fork-session.sh).

Steps:
1. Gate 1 (Phase 3): founder picks 0.4.0 (minor — new capability) vs 0.3.1 (patch). Default: 0.4.0.
2. Build (Phase 4): edit `"version"` in plugin.json only. No other file.
3. Review (Phase 5): cross-provider review gate (leadv2-review-run.sh) on the one-file diff.
4. Deploy (Phase 6): commit in lane; land via leadv2-deploy-merge.sh from the main
   checkout in a subshell (session CWD never moves).
5. Verify (Phase 7): probe origin/main shows the new version string (live signal = the
   pushed ref, not local files).
6. Close (Phase 8): e2e gate → phase8-close → phase8-passed.flag. Reaping = lead postflight.

Risk: version string consumers (marketplace cache) — out of scope; plugin cache refresh
is documented separately (hooks exception in global CLAUDE.md).
