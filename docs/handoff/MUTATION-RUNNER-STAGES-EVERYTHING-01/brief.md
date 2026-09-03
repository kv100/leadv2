# MUTATION-RUNNER-STAGES-EVERYTHING-01 — the mutation runner commits the whole tree, with hooks disabled

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/worktrees/MUTATION-RUNNER-STAGES-EVERYTHING-01`

LANE_WRITES: scripts/v5-mutation-kill-rate.sh,scripts/mutation-kill-rate.sh,tests/v5/test-v5-mutation-kill-rate.sh,tests/run-all.sh,docs/handoff/MUTATION-RUNNER-STAGES-EVERYTHING-01/

This is `persona-engine`, not the plugin repo. Branch from current main.

## What was seen, and what it actually is

The founder's Source Control panel showed a scratch worktree `v5mkr-wt-FbIC8M` under `$TMPDIR`
with **6006 staged files**, including `.gitignore`, `.mcp.json`, `.env.example` and `.gitattributes`
struck through as deletions.

Verified in source, do not re-derive:

- `scripts/v5-mutation-kill-rate.sh:190` — `git worktree add --detach "$candidate" "$BASE_SHA"`,
  where `$candidate` is under `$TMPDIR`;
- `:312` — `git -C "$WT" add -A`;
- `:208` — `git -C "$WT" commit --no-verify -q -m "mutation: $1"`;
- `scripts/mutation-kill-rate.sh:352` — the same `add -A`.

So the runner stakes the entire working tree, including deletions of repository configuration, and
commits it with **every hook disabled**.

## Why this is not cosmetic

1. **`--no-verify` bypasses every guard we have** — `guard-worktree-scope`,
   `plugin-scripts-drift-guard`, the heredoc guard, all of them. A path that can commit anything
   with no checks is exactly the path that should have the most.
2. **`add -A` is a snapshot, not a mutation.** A negative control is supposed to change one line
   inside one function body. Staging 6006 files means the suite can go red for any reason at all
   and we score it as "the mutation was killed". That is the broadest fake-control shape we have
   catalogued — a control that catches its own debris. Every kill-rate number produced through
   this path is suspect until it is re-derived.
3. **The worktree lives in `$TMPDIR`**, which macOS reclaims on its own schedule. The directory
   can vanish mid-run, under a detached HEAD, while the runner is mutating in it.

The in-worktree commit itself is **justified and must stay** — `:12-15` and `:201-202` explain it:
`tests/run-all.sh:427` selects suites from `origin/main...HEAD` and sees committed history only, so
an uncommitted mutation is invisible to the selector. That reasoning is correct. What does not
follow from it is committing the whole tree, or skipping hooks.

## [Critical] stage only what the mutation touched

Replace `add -A` with an explicit add of the paths the mutation actually wrote. The runner knows
them — it applied the patch. If it does not track them today, make it track them; do not infer
them from `git status`, which is what conflated the mutation with unrelated tree state in the
first place.

After the change, a mutation run's commit must contain **only** the mutated file(s). Assert that,
do not eyeball it.

## [Critical] a run that would stage anything unexpected must abort, not proceed

If the set of changed paths is not exactly the set the mutation intended, the entry is
`unscored` and the run says why. Silently widening is how a kill gets recorded for a change nobody
made. Reuse the `unscored` outcome if the control-prover already defines one; if not, define it
here and say so in `report.md`.

## [Critical] drop `--no-verify`, or justify it in writing

Run the hooks. If a specific hook genuinely cannot run inside a scratch worktree, disable **that
hook by name** and record which one and why in `report.md`. A blanket bypass is not acceptable on
a path that commits.

## [Medium] move the scratch worktree out of `$TMPDIR`

Put it somewhere the OS does not reclaim — a repo-local ignored directory is fine. Clean it up on
exit, including on failure, and never remove a worktree the runner did not create.

## Acceptance

Extend `tests/v5/test-v5-mutation-kill-rate.sh` against fixture repositories — never the real
checkout, never the real `$TMPDIR` worktree:

1. a mutation touching one file => the commit contains exactly that one path;
2. an unrelated dirty file present before the run => it is NOT staged, and the run still scores;
3. the changed-path set differing from the intended set => `unscored`, with a reason;
4. hooks are invoked on the mutation commit (or the named exemption is the only one skipped);
5. the scratch worktree is created outside `$TMPDIR` and removed on both success and failure;
6. a run whose worktree disappears mid-flight => `unscored`, not a kill.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Mutate the **path-narrowing**, i.e. restoring `add -A` must turn the suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence. A printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never run against the real repository or the real kill-rate catalog.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A mutation run commits only the file it mutated, with hooks running, from a worktree the OS does
not reclaim — and restoring `add -A` turns the suite red with the exit code following.
