# Wave 4 — shared constraints (binding on every lane)

REPO: all work happens in `~/Projects/leadv2` (the plugin repo). Never in persona-engine.

## Hard prohibitions
- NEVER touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (held by the lead session).
- NEVER touch `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` (held by session persona-engine-e1).
- NEVER commit inside any repository under `~/MythicalGames` — they belong to the founder's
  employer. leadv2 config there is local-only via `.git/info/exclude`.
- NEVER write into the git-tracked `.claude/settings.json` of the `m3` repo.
- NEVER commit to `main`. Work on the lane's own worktree branch.
- NEVER edit `tests/known-red-suites.txt`.
- NEVER weaken, delete, or loosen an existing assertion to make a suite green.

## Required on every fix
1. **Negative control, run for real.** Apply the mutation INSIDE the body of the function
   under claim (not at file top level — a top-level insert reddens every suite for the wrong
   reason and reads as a pass). Show the suite RED with the mutation, revert, show it GREEN.
   Record both exit codes verbatim in the report.
2. **Green on macOS AND in a linux container.** Report both exit codes.
3. The test must keep the production function under claim REAL and fake only one level lower.
   A test that stubs the function it claims to cover proves nothing.

## Before handing back
Run `git diff --diff-filter=D --name-only main...HEAD` — **THREE dots**. Anything it lists is a
file this lane actually deletes relative to the merge base; restore it from main unless the
deletion is deliberate and stated in your report.

Do NOT use two dots. `main..HEAD` compares against main's CURRENT tip, so every file added to
main after this lane branched shows up as if this lane deleted it. Measured 2026-09-03: two lanes
were reported as deleting a file neither had touched. Three dots compares against the merge base,
which is the question you actually mean to ask.

## Where suites live, and CI must SELECT yours

- Suites live in `plugins/leadv2/scripts/tests/test-<name>.sh` (a few older ones sit flat in
  `tests/`). New suites go in `plugins/leadv2/scripts/tests/`.
- `tests/run-all.sh` selects suites two ways: by STEM match (a changed `foo.sh` runs
  `test-foo*.sh`), and by explicit rows in `EXTRA_SUITE_MAP` (`tests/run-all.sh:134+`),
  one `"<changed-stem>:<suite-path>"` per line.
- **A green suite CI never runs is worth nothing.** If your suite's stem does not match the
  file you changed, you MUST add the `EXTRA_SUITE_MAP` row, and you MUST prove it with
  `tests/run-all.sh --scope changed` showing your suite in the selected set.
- `EXTRA_SUITE_MAP` is a SHARED file — every Wave-4 lane appends to it. APPEND your row at the
  end of the block, never reorder or reflow existing rows. A conflict there is expected and the
  lead resolves it at merge; a reflowed block is not resolvable and will be rejected.
