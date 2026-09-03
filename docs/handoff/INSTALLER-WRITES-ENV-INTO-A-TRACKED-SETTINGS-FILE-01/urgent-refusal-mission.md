# URGENT — minimal, single-purpose commit: installer must refuse a tracked settings.json

Repo: `~/Projects/leadv2`.

Another lane (TWO-ACCOUNTS-EVERYWHERE / D5) is about to run the installer inside the founder's
EMPLOYER's repo `~/MythicalGames/m3`. Only a code-level refusal prevents the founder's absolute
home path from being committed into that employer's tree. A written instruction does not protect;
a worker who simply runs the installer will do it without knowing. The refusal does protect.

## Scope — exactly one behaviour change, nothing else
- Do NOT refactor `env_py()`.
- Do NOT migrate or clean up anything already on disk.
- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-claude-profile-select.sh`.
- The rest of task INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 arrives on its own lane.

## The defect
`plugins/leadv2/scripts/leadv2-repo-install.sh`, function `env_py()` (~lines 343-390):
it builds `p = pathlib.Path(repo)/".claude/settings.json"` (~line 375) and unconditionally calls
`p.write_text(...)` (~line 385) when `mode == "write"`. Nothing checks whether that file is
tracked by git. The env block contains `"LEADV2_PROJECT_ROOT": repo` and `CLAUDE_PLUGIN_ROOT`
with an absolute `/Users/<name>/...` path, so in a work repo it ships to the whole team.

Measured 2026-09-03: `~/MythicalGames/m3`, `m3-promo` and `m3-trait` all have a git-TRACKED
`.claude/settings.json` (the latter two are worktrees of the same repo). All three currently
carry ZERO `LEADV2_` keys — nothing has leaked yet. `~/Projects/persona-engine` has already
leaked: 25 `LEADV2_*` lines plus the absolute home path sit in its tracked file.

## The change
Before writing, choose the target file:
1. If `.claude/settings.json` is TRACKED in that repo — `git -C <repo> ls-files --error-unmatch
   .claude/settings.json`, exit 0 means tracked — the installer MUST NOT write to it. Write the
   env block to `.claude/settings.local.json` instead and print a clear stdout line saying the
   tracked file was left untouched and where the block went.
2. If untracked, absent, or the path is not a git repo at all: behaviour unchanged from today.
3. Merge, never clobber, in both cases — preserve every existing key, add only the missing ones,
   exactly as the current `missing` logic already does.
4. `check` mode must report against the SAME file `write` mode would target. Otherwise `--check`
   reports "MISSING — N key(s)" forever after a correct write. This is part of the minimal fix,
   not scope creep.

Read the whole `env_py()` and its callers first (`grep -n "env_py"
plugins/leadv2/scripts/leadv2-repo-install.sh`). The tracked-check must run against the actual
`repo` path being installed into, never the cwd.

## Acceptance — run it, do not describe it
In a scratch git repo under `/tmp`:
- commit a `.claude/settings.json`; run the env write; assert the tracked file is byte-identical
  afterwards (`shasum -a 256` before vs after) and the block landed in `.claude/settings.local.json`;
- `git rm --cached .claude/settings.json`; run again; assert the block goes to `settings.json`;
- run the installer twice in each case; assert no duplicated keys.

## Negative control — mandatory
Apply a mutation INSIDE THE BODY of the tracked-check function — force it to always report
"untracked" — and show the suite goes RED. Revert; show GREEN. An insert at file top level is
NOT acceptable: it reddens everything for the wrong reason and reads as a pass. Report the RED
and GREEN exit codes verbatim. Run the suite on macOS AND in a linux container; report both
exit codes.

## Suite + CI selection
New suite: `plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh`.
`tests/run-all.sh` selects by stem match plus explicit `EXTRA_SUITE_MAP` rows (`tests/run-all.sh:134+`).
Append exactly ONE row at the END of that block:
`leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh`
Never reorder or reflow existing rows — other Wave-4 lanes are appending there too.
Prove selection with `tests/run-all.sh --scope changed` and paste the line showing your suite selected.

## Git
Branch off current `main`, named `wave4-installer-refusal`. Do NOT commit on `main`.
One commit, message starting `fix(install):`.
Before finishing run `git diff --stat main..HEAD` and confirm the branch DELETES no file that
main still has; restore any it does from main. Report the branch name and commit sha — the lead merges.

## Report back
Diff stat; both scratch-repo assertions with their sha256 values; negative-control RED and GREEN
exit codes; macOS and linux exit codes; the `--scope changed` selection line. If a step could not
be run, name it and say why — never report a step as done that you did not run.

Shared constraints: `docs/handoff/WAVE4/shared-constraints.md`.
