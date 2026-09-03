# HANDOFF-ARTIFACTS-GITIGNORED-01 — no lane's RED proof is ever committed

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HANDOFF-ARTIFACTS-GITIGNORED-01`

LANE_WRITES: .gitignore,plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh,tests/run-all.sh,docs/handoff/HANDOFF-ARTIFACTS-GITIGNORED-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

## The defect

`.gitignore:40` ignores `docs/handoff/*/*`. Every mutation-control artifact a lane produces —
the `roundN-red/` output that is the *only* durable evidence a negative control ever went red —
is therefore invisible to git and never lands. Confirmed present on `main`.

Why it matters here specifically: this repo's whole review discipline is "a commit message is
not evidence; show the RED run". If the RED run cannot be committed, every future reader is
back to trusting prose. Last night four separate rounds died on fake controls precisely
because nobody could re-run the previous round's proof.

Note the second-order effect I hit myself: because the path is ignored, **deleting** a handoff
artifact is also invisible in `git status`, so a lane can destroy another lane's evidence and
nothing shows.

## [Critical] proof artifacts are tracked; scratch stays ignored

Un-ignore what is evidence, keep ignoring what is churn. At minimum `report.md`, the brief,
and the `roundN-red/` proof outputs must be committable without `-f`. Transient run logs,
diffs regenerated on every dispatch, and lane scratch should stay ignored.

Do not simply delete line 40 — say in `report.md` what you kept ignored and why, and confirm a
dispatch cycle does not now flood `git status` with churn.

## Acceptance

Build `test-handoff-artifacts-tracked.sh` against a fixture repo — never the real repo —
covering:

1. a `roundN-red/` artifact under `docs/handoff/<id>/` is added by a plain `git add <file>`
   with no `-f`;
2. `report.md` and the brief likewise;
3. a transient log written by a dispatch is still ignored;
4. deleting a tracked proof artifact SHOWS in `git status` (this is the second-order fix).

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the file under claim (here, the ignore rule), RED, revert, GREEN, clean
  `git diff --stat`. A suite that stays green with the fix removed is a failed control; a
  printed `RED control:` line that does not change the exit code is not an assertion, and
  neither is a `FAIL:` line that leaves `$?` at 0.
- No `grep` against `.gitignore` text as an assertion — assert on `git check-ignore` / `git add`
  behaviour in a fixture repo, which is the actual guarantee.
- Never run the suite against the real repo; build fixture repos in a temp dir and remove them
  on every exit path, including failure.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A lane's RED proof commits without `-f`, its deletion is visible, churn is still ignored, and a
mutation restoring the blanket ignore turns the suite red with the exit code following.
