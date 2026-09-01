# LEADV2-HOOK-CACHE-DEPLOY-01 — report

Landing in the plugin repo now reaches the hook cache mechanically. Deploy on
this repo = refresh the plugin-cache copy that Claude Code actually loads.

## What was built

| File | Role |
|---|---|
| `plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh` | Finds the ACTIVE cache dir, `rsync -a --delete` the repo's `plugins/leadv2/` into it, writes `<cache>/.synced-from`, prints `synced=<n> cache=<path> repo_head=<sha>`; exits 1 (BLOCK) when no cache dir / no git HEAD; exits 3 on cache-invocation (CACHE-REFUSAL, mirrors leadv2-plugin-sync.sh). |
| `.claude/leadv2-overrides/deploy.sh` | New repo-local override — satisfies `leadv2-deploy-merge.sh:144-151` (the BLOCK every land here ended on). Calls the sync, then prints the next-session advisory. |
| `.claude/leadv2-overrides/stack.yaml` | `deploy_method: local` (+ lang/db/hosting identity). |
| `plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh` | Hermetic suite (13 asserts, ~1 s) via `LEADV2_PLUGIN_CACHE_ROOT` / `LEADV2_PLUGIN_SRC` / `LEADV2_PLUGIN_META`. |
| `tests/run-all.sh` | EXTRA_SUITE_MAP row `leadv2-plugin-cache-sync.sh → test-plugin-cache-sync.sh`. |

## Which cache dir is authoritative (asked explicitly in the mission)

**`~/.claude/plugins/installed_plugins.json` → `leadv2@leadv2-local` →
`installPath` is authoritative** — it is the path Claude Code actually loads.
Evidence (2026-09-02):

```
$ python3 -c "...installed_plugins.json, keys with leadv2..."
leadv2@leadv2-local [{ "installPath": ".../plugins/cache/leadv2-local/leadv2/0.3.0",
 "version": "0.3.0", "installedAt": "2026-05-12T10:29:28.990Z", "lastUpdated": "2026-08-13T11:44:27.931Z" }]
```

The cache also holds a stale `0.1.0` dir; when the meta json is absent the
script falls back to the highest **numeric** version dir (0.10.0 > 0.9.0 —
the fallback sorts version dirs numerically with `-t. -k1,1n -k2,2n -k3,3n`; suite d1
regresses exactly this).

## What the cache actually holds (enumerated, not assumed)

`0.3.0/` is a copy of the **whole** `plugins/leadv2/` tree — agents,
codex-skills, commands, config, contracts, data, docs, examples, hooks,
prompts, ref, scripts, skills, templates, tests, workflows, `.claude-plugin` —
plus three extras the repo does not have: `.mypy_cache`, `.pytest_cache`, and
a manual `hooks.bak-20260902/` backup. So the sync is one whole-tree
`rsync -a --delete`; per-subdir loops would silently miss whatever the cache
gains later. Exclusions protecting cache-only paths from `--delete`:
`hooks.bak-*` (never destroy a manual backup silently), `.synced-from`, `.git`.

## Live-cache diff at time of writing (what the lead's real run will do)

- `hooks/`: 2 files differ (leadv2-promise-guard.sh, leadv2-single-lead-beat.sh — cache stale, repo wins), 7 cache-only files. 6 of the 7 are confirmed
  deleted-upstream residue (`leadv2-supervisor-*.sh` etc. — deletions landed in
  517bc13 / c312ac8 / 2d6c9b4), so `--delete` removing them is correct.
- **Caveat for the lead:** `hooks/lib/leadv2-hook-session-kind.sh` is
  cache-only with NO commit history — it exists uncommitted in the main
  checkout (BEAT-LOOP-ORPHANS-01 in-flight). Run the real sync from a tree
  where that file is present (or after the lane lands); otherwise the sync
  removes it from the cache while the lane is mid-flight.
- Full tree: ~29 files drifted (mission evidence, 2026-09-01) — agents,
  commands, config, docs, scripts all differ; hermetic smoke sync moved
  **1025 files** into a seeded cache, i.e. that is the current repo-tree size.

## Related finding (out of lane scope, for the lead)

`plugins/leadv2/scripts/leadv2-plugin-sync.sh:130` hardcodes
`CACHE_TARGET="${HOME}/.claude/plugins/cache/leadv2-local/leadv2/0.1.0"` — the
stale version dir. That script's bash -n-gated, direction-safety sync has been
refreshing 0.1.0 while the active install is 0.3.0. LANE_WRITES for this lane
do not include that file, so it is reported, not touched.

## Test results (honest)

1. Suite green, 13/13 (`LEADV2_SUITE_LOCK_DISABLE=1 bash
   plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh`):
   a1-a5 sync/diff-empty/marker/output-line, b1 stale-file deletion, b2
   backup protection, b3-b4 idempotent second run (synced=0), c1-c2 missing
   cache fail-closed, d1-d2 numeric fallback. First run was red 11× on
   rc=127 (suite resolved the sync script's path as `tests/…` instead of
   `tests/../…`) — fixed, then green.
2. Mutation negative control (drop `--delete`), RUN, red pasted:

```
[TEST] FAIL: a4: diff -rq repo vs cache is empty after sync
  got: diff-empty:Only in /var/folders/.../0.3.0/hooks: leadv2-dead.sh
[TEST] FAIL: b1: stale cache-only hook survived --delete: /var/folders/.../hooks/leadv2-dead.sh
[TEST] 11 passed, 2 failed
MUTATION_SUITE_RC=1
```

   Reverted from backup (`grep -c 'rsync -a --delete'` = 1), suite green again.
3. `deploy.sh` end-to-end, hermetic sandbox (CLAUDE_PROJECT_ROOT=$tmp,
   seeded cache + meta):

```
synced=1025 cache=/var/folders/.../plugins/cache/leadv2-local/leadv2/0.3.0 repo_head=a6a4de8eeb75...
NOTE: plugin hooks/commands/agents load from the cache on the NEXT session — restart claude to pick up this deploy.
DEPLOY_RC=0
```

   Empty sandbox cache → `BLOCK: no leadv2 plugin cache dir found`, rc=1
   (fail-closed path through the override also proven).
4. `bash -n` green on all four changed shell files.
5. `--scope changed` proof: see the run log appended below (the map row
   selects the suite from the salvage commit's diff).

## NOT done

- The real sync against the live cache — deliberately not run from the lane;
  the lead runs it once after landing (mission instruction).
- `leadv2-plugin-sync.sh` 0.1.0 fix — see finding above.

## Commit state

Work code was committed by the lead's salvage commit `a6a4de8` (this worker
was still running when the salvage swept the worktree; `git status` confirms
on-disk bytes == committed bytes for all five files). This report is committed
separately on the lane branch.

## Round 2 evidence (2026-09-02)

Reviewer verdict on round 1: FAIL, high=2 — the "`claude plugin update` no-ops
for a directory-source marketplace when the version string did not change"
cornerstone had no probe artifact. All probes below were run this round;
probe edits to the canonical repo were made via a /tmp python patcher,
verified by `git status` after each revert (canonical clean).

### Fact-base correction vs the round-1 brief

The brief's "leadv2 installPath = .../0.3.0" was STALE by the time this round
ran. `installed_plugins.json` now records:

    installPath: /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.5.7
    lastUpdated: 2026-09-01T23:00:10.973Z
    cache root holds: 0.1.0  0.3.0  0.5.7

All probes below target 0.5.7 (the authoritative dir).

### Probe (a): cache hooks.json vs repo

    diff plugins/leadv2/hooks/hooks.json <cache 0.5.7>/hooks/hooks.json → rc=0 (byte-identical)
    python entry-level compare over d["hooks"] → repo-only: 0, cache-only: 0, repo total: 75
    diff -rq plugins/leadv2/hooks <cache 0.5.7>/hooks → EMPTY (zero drift)

The 0.5.7 cache is a fresh full mirror (installed at the 2026-09-01T23:00
version bump). Whole-plugin `diff -rq repo <cache 0.5.7>` → 39 lines, all of
three classes: `__pycache__`/`.mypy_cache`/pyc, repo-side runtime state
(docs/leadv2/*), and this lane's two not-yet-synced new files. No meaningful
drift remains against 0.5.7.

Zombie finding (strengthens the --delete design): the DEAD 0.3.0 dir still
contains 6 hook scripts deleted from the repo at 2d6c9b4
(leadv2-supervise-fanout-guard.sh, leadv2-supervise-sentinel-cleanup.sh,
leadv2-supervisor-guard.sh, leadv2-supervisor-mode-reinject.sh,
leadv2-supervisor-pump-caller.sh, leadv2-plugin-sync-drift-warn.sh) — the
repo has 93 hook scripts, the 0.3.0 cache copy had 99. Copy-over syncs would
preserve such zombies; `--delete` removes them.

### Probe (b): where a hook command executes

Probe line `echo "PROBE origin=$0" >> /tmp/lv2-hook-origin.txt` inserted after
the shebang of the REPO's hooks/leadv2-user-prompt-context.sh (canonical, via
patcher); one `claude -p 'ok'` run; output:

    PROBE origin=/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2/hooks/leadv2-user-prompt-context.sh

Supporting: settings.json line 12 sets CLAUDE_PLUGIN_ROOT to
`~/.claude/plugins/local/leadv2/plugins/leadv2`; `readlink` on that path →
`/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2`. Hook command
BODIES therefore execute from the repo (live at once). Probe line removed;
canonical `git status` clean (one stray blank line from the revert was caught
by `git diff` and fixed before commit).

### Probe (c): `claude plugin update` with version unchanged

`claude plugin update leadv2@leadv2-local` (both runs this round) →

    Checking for updates for plugin "leadv2@leadv2-local" at user scope…
    ✔ leadv2 is already at the latest version (0.5.7).

Decisive run: repo hooks/hooks.json marked "PROBE-UPDATE" (description string),
version left at 0.5.7:

    BEFORE: cache hooks.json sha256 9b9abf5c27c727e0…923, mtime 1788303608
    update → "already at the latest version (0.5.7)", rc=0
    AFTER:  sha256 9b9abf5c27c727e0…923, mtime 1788303608 (identical)
    grep -c PROBE-UPDATE <cache>/hooks/hooks.json → 0 (never copied)

The reviewer-demanded claim is MEASURED: no version bump → no cache refresh,
even with changed repo content. (Note the no-op also reported 0.5.7 while the
first probe comparison was against the dead 0.3.0 dir — the no-op heals
nothing.) Refresh-on-bump is evidenced by the three full version dirs +
installPath repoint + lastUpdated stamps (end-state artifact; the bump act
itself was the lead's 2026-09-01 action).

### UNVERIFIED (tagged, as required)

That Claude Code parses the hook LIST only from the cache hooks.json (not the
repo's) — a direct probe requires mutating the live cache's hooks.json, which
the task forbids from the lane. All artifacts above are consistent with it and
it is the only reading that explains the round-1 defect; both rewritten
headers carry the UNVERIFIED tag on exactly this point.

### Code changes this round

- deploy.sh + sync script header: rewritten from the measurements above; every
  external claim carries its evidence line or UNVERIFIED. One comment line
  names what is live-from-repo and needs no sync (script bodies via the
  CLAUDE_PLUGIN_ROOT symlink); the minimum sync set is named (hooks/hooks.json,
  .claude-plugin/plugin.json). Script BODIES unchanged (round-1 design held:
  installPath resolution + whole-tree --delete rsync validated by the 0.5.7
  mirror).
- test-plugin-cache-sync.sh: added d0 (cache lacks hooks.json pre-sync — the
  defect state). (d) hooks.json entry synced and (e) .synced-from = repo sha
  already covered as a5/d1/d2; kept all round-1 cases.
- tests/run-all.sh: merge conflict with main resolved (kept both sides; the
  lane's suite-map row retained, main's four new rows appended).

### Mutation control (skip hooks.json in the sync)

Mutant: added `--exclude='hooks/hooks.json'` to the rsync →

    [TEST] FAIL: a4: diff -rq repo vs cache is empty after sync
    [TEST] FAIL: d1: hooks.json present in cache after sync
    [TEST] FAIL: d2: hooks.json content matches repo (new hook entry synced)
    [TEST] 13 passed, 3 failed   (rc=1)

Mutation reverted; re-run → `[TEST] 16 passed, 0 failed` (rc=0).

### Live cache

NOT synced from the lane (per instruction 4). The lead should run
`deploy.sh` (or the sync script) after landing — it will be a large
synced=<n> because the cache has not seen this branch's content.
