# INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01

`leadv2-repo-install.sh` appends the 17-key leadv2 env block to `.claude/settings.json` without
checking whether that file is tracked by git. In a personal repo that is harmless. In a shared work
repo it is a leak.

## Measured, 2026-09-03

Adopting the eight MythicalGames repos, `~/MythicalGames/m3` was the one where
`.claude/settings.json` is a **tracked** file (`git ls-files --error-unmatch` succeeds; the other
seven are untracked). The installer left it as a staged-able modification:

    M .claude/settings.json      +21 lines

containing, among the 17 keys:

    "CLAUDE_PLUGIN_ROOT": "/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2"
    "LEADV2_PROJECT_ROOT": "/Users/kostiantyn.vlasenko/MythicalGames/m3"

So a routine `git add .claude` in that repo pushes one developer's absolute home paths and this
plugin's private routing knobs to the whole team. `m3/.gitignore:63` already ignores
`.claude/settings.local.json` — the correct destination was available and unused.

The lead worked around it by hand: moved the block to `.claude/settings.local.json`, restored
`settings.json`, verified `git status` clean and the ignore rule matching.

## What this task must deliver

1. **The installer detects a tracked `settings.json` and writes `settings.local.json` instead.**
   Name the file:line. Claude Code merges `settings.local.json` over `settings.json`, so behaviour
   is unchanged — only the destination moves.
2. **Never silently modify a tracked file.** If for some reason the local file cannot be used, the
   installer must say so in its report line rather than write anyway.
3. **Report the destination it chose** in the install output, so a reader can see which file got
   the env block.
4. **A negative control**: a fixture repo with a tracked `settings.json` — show the suite red
   before the fix (env lands in the tracked file), green after (env lands in the local file, the
   tracked file byte-identical). Then the untracked case, unchanged in both directions.
5. Green on macOS and in a Linux container, exit codes pasted. Register the suite in
   `tests/run-all.sh` and prove `--scope changed` selects it on a change to
   `leadv2-repo-install.sh`.
6. Commit in this lane before you finish.

Related: `MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01` (same adoption sweep).

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, and "just document it" —
the installer must not need a human to clean up after it.
