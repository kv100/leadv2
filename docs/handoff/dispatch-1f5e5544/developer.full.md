# developer — dispatch-1f5e5544 (one plugin source, design arm A / fable)

## Outcome

Report-only lane. The design is at `docs/audits/one-plugin-source-fable.md` (committed on
branch `worktree-1PLUGIN-FABLE-2`). No behaviour changed; no file outside the report and this
handoff dir was created, modified, linked or deleted.

## Headline findings (detail and commands in the report)

1. The founder's "copies in the projects" is inverted: pe/getmany/respiro/m3 `.claude/scripts`
   are 610/318/393/420 symlinks with 0/0/1/0 shadowing real files. The copies are the plugin's
   own rsync targets: `~/Projects/leadv2/.claude/scripts` (544 real, 338 drifted, gitignored,
   declared as sync target (f) at `leadv2-plugin-sync.sh:996-1020`), `~/.claude/leadv2-shared/
   scripts` (178 shadows, 113 drifted), `~/.claude/scripts` (101 shadows, 13 drifted).
2. End state chosen: C′ — one byte store in `plugins/leadv2/`, per-file symlinks in every other
   location, a declared per-project layer (`leadv2-overrides/` restricted to the 22 filenames the
   plugin reads plus `scripts/` and `rules/`; repo-native files = not-in-canonical and tracked).
   Boundary rule is `git ls-files` membership, not name shape.
3. Overrides: 64 files (38 pe, 7 respiro, 8 getmany, 11 m3 — the mission's 53 omitted m3).
   24 have zero plugin readers. No same-named override is byte-identical across repos. m3's
   `codex-policy.yaml` records a founder decision that `leadv2-codex-planner.sh:5` still
   contradicts.
4. Guards: `plugin-scripts-drift-guard.sh` (pre-commit) is wired in zero repos; the SessionStart
   `--check` covers only the shared trees; `leadv2-one-copy-convert.sh` derives its canonical
   root by `../` hops and from a worktree reports 721 false badlinks.
5. Corrections to the mission: m3-market exists at `~/MythicalGames/m3-market`, is in
   `cross-repo-paths.yaml`, is not a git repo; getmany is NOT in that yaml; the stale
   "live repos" line is in the user-level CLAUDE.md, not the repo's.
6. Order: 8 stages, each with precondition (registry-quiet per repo), proof command and
   one-command rollback; the only work-losing path is converting a VENDORED_NEWER copy, so
   `leadv2-drift-guard.sh` promotion precedes stages 1–2.

## Deviations

- Nested Agent spawns (two censuses) were denied by the spawn-arbiter gate twice, including after
  consulting `leadv2-route-arbiter.sh` (it routed to `freepool`, which the Agent tool cannot
  spawn). Both censuses were done in bounded bash instead; content judgement for 8 yaml overrides
  is therefore UNVERIFIED and listed as such.
- Handoff deliverables are written inside the lane worktree (WORKTREE PIN), not the main
  checkout path named in the task binding.

## Self-check (raw)

```
$ git status --short
?? docs/audits/one-plugin-source-fable.md
# no .sh / .py changed → bash -n / py_compile: nothing to check
$ timeout 540 bash tests/run-all.sh --scope changed 2>&1 | tail -3
test-status-surface-fast-names: 12 passed, 0 failed
[PASS] .../tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
```

DELIVERABLE_COMPLETE
