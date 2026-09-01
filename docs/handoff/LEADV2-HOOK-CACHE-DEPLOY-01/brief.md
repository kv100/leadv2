# LEADV2-HOOK-CACHE-DEPLOY-01 — landing in the plugin repo must reach the hook cache

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEADV2-HOOK-CACHE-DEPLOY-01`
LANE_WRITES: .claude/leadv2-overrides/deploy.sh,.claude/leadv2-overrides/stack.yaml,plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh,plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh,tests/run-all.sh,docs/handoff/LEADV2-HOOK-CACHE-DEPLOY-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Evidence (2026-09-01)
- `leadv2-deploy-merge.sh:145-151` requires `.claude/leadv2-overrides/deploy.sh` and prints
  `BLOCK: ... not found` otherwise. The plugin repo `~/Projects/leadv2` has NO
  `.claude/leadv2-overrides/` directory at all, so every land there ends on that BLOCK after the
  ff-merge (PLUGIN-PAPERCUTS-01 land, 2026-09-01).
- `~/.claude/plugins/local/leadv2/plugins/leadv2` is a symlink to the repo, but Claude Code loads
  hooks from `~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0/` — a real COPY. `diff -rq` between
  repo `plugins/leadv2/hooks` and that cache differs in 29 files today. `claude plugin update`
  no-ops for a directory-source marketplace when the version did not change (user CLAUDE.md).
  So a hook fix that lands on main is NOT live until someone copies it — the lying-green disease
  for every hook lane (BEAT-LOOP-ORPHANS-01 lands a hook fix next).

## Do
1. `plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh`: find the ACTIVE cache dir (highest
   version under `~/.claude/plugins/cache/leadv2-local/leadv2/`, or the one named in
   `~/.claude/plugins/installed_plugins.json` if that file exists — check which is authoritative and
   say so in report.md), `rsync -a --delete` the repo's `plugins/leadv2/hooks/` (and any other dir
   the cache holds as a copy — enumerate what the cache actually contains, do not assume) into it,
   print `synced=<n files> cache=<path> repo_head=<sha>`, and write the sha to
   `<cache>/.synced-from`. Idempotent; exits non-zero if the cache dir cannot be found.
2. `.claude/leadv2-overrides/deploy.sh` for the plugin repo: calls the sync script, then prints the
   one-line advisory that hooks load on the NEXT session. `stack.yaml` with `deploy_method: local`.
   Both are repo-local override files (allowed by the user-level shared-tree policy).
3. Suite `test-plugin-cache-sync.sh` (hermetic: `LEADV2_PLUGIN_CACHE_ROOT` pointed at a temp tree
   with a fake `0.3.0/hooks` copy that differs from a fake repo): (a) after sync, `diff -rq` is
   empty and `.synced-from` holds the sha; (b) a stale extra file in the cache is removed; (c) no
   cache dir → non-zero exit with the message. Under 15 s. `EXTRA_SUITE_MAP` row; prove with
   `--scope changed`.
4. Mutation negative control, RUN and paste red: drop `--delete` → (b) red. Revert.
5. `report.md`; commit in the lane. Do NOT run the real sync against the live cache from the lane —
   the lead runs it once after landing.
