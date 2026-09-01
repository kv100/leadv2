# LEADV2-HOOK-CACHE-DEPLOY-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEADV2-HOOK-CACHE-DEPLOY-01`
LANE_WRITES: .claude/leadv2-overrides/deploy.sh,.claude/leadv2-overrides/stack.yaml,plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh,plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh,tests/run-all.sh,docs/handoff/LEADV2-HOOK-CACHE-DEPLOY-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last: the lead's salvage
commit of your round-1 work); run with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST
(`git merge main`). An uncommitted exit is a failed round (the epilogue now auto-commits, but
commit yourself anyway).

## Review verdict on round 1 (reviewer glm) — FAIL, high=2
Both Highs are the same defect: the design rests on the claim "`claude plugin update` no-ops for a
directory-source marketplace when the version string did not change" (deploy.sh:5, sync script
header:6) with no probe and no UNVERIFIED tag. Under the evidence contract a design-cornerstone
external claim must be measured.

## Facts the lead established (2026-09-02) — build on them, verify them, do not re-assume
- `~/.claude/plugins/installed_plugins.json`: leadv2 `installPath` =
  `~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0` (a real COPY).
- `~/.claude/settings.json` (and persona-engine's `.claude/settings.json`) override
  `CLAUDE_PLUGIN_ROOT` to `~/.claude/plugins/local/leadv2/plugins/leadv2`, a SYMLINK to the repo.
  A deny-floor error tonight printed the hook's own path under `plugins/local/…`, so hook COMMANDS
  execute from the repo.
- Hypothesis to prove: Claude Code reads the hook LIST (`hooks/hooks.json`: which events, which
  matchers, which command strings) from the cache copy, while each command string resolves
  `${CLAUDE_PLUGIN_ROOT}` to the repo. Consequence: editing an EXISTING hook script is live at once
  (repo), but ADDING a hook / changing a matcher in `hooks.json` is dead until the cache copy is
  refreshed. The 29-file drift the lead measured earlier is mostly hook scripts (irrelevant if the
  hypothesis holds) plus `hooks.json` itself (the part that matters).

## Do
1. PROBE, paste artifacts: (a) `diff` cache `hooks/hooks.json` vs repo — list entries present in
   the repo but not in the cache; (b) prove where a hook command executes: add a temporary
   `echo "$0" >> /tmp/lv2-hook-origin.txt` line to one existing hook in the REPO only, run one
   `claude -p 'ok'` (any arm), read the file, remove the line; (c) prove the claim in the finding:
   `claude plugin update leadv2@leadv2-local` (or the exact CLI form; read `claude plugin --help`)
   with version unchanged → does the cache `hooks.json` mtime/content change? Paste before/after.
2. Rewrite `deploy.sh` and the sync script header from the measurements: the sync must copy what
   is actually read from the cache (at minimum `hooks/hooks.json`, `plugin.json`; whatever (a)
   and (c) show) and say in one comment line what is live-from-repo and needs no sync. Every
   external claim carries `evidence:` with the probe line, or `UNVERIFIED`.
3. Suite cases: (d) repo `hooks.json` has an entry the cache lacks → after sync the cache has it;
   (e) `.synced-from` holds the repo sha; keep the round-1 cases that still apply. Mutation control,
   RUN and paste red: skip `hooks.json` in the sync → (d) red. Revert.
4. Do NOT run the sync against the live cache from the lane; the lead runs it after landing.
5. "## Round 2 evidence" in report.md; commit.
