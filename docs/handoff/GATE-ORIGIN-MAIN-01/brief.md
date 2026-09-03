# GATE-ORIGIN-MAIN-01 — the worker output gate refuses unconditionally without `origin/main`

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-ORIGIN-MAIN-01`

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh,plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh,tests/run-all.sh,docs/handoff/GATE-ORIGIN-MAIN-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it.

## The defect

`lib/leadv2-worker-output-gate.sh:82-87` hard-fails when `origin/main` does not resolve. A
checkout with no remote, a differently-named default branch, or a fresh clone that has not
fetched yet all hit this — and the gate reports a refusal that looks like the worker's fault
rather than the gate's missing precondition.

Confirmed present on `main` at the time of writing.

## [Critical] fail with a diagnosis, and fall back to a real base

`origin/main` is one way to name the lane's base, not the only one. Resolve the base the way
the rest of the dispatcher does; when no base can be resolved at all, refuse — but the refusal
must say *which* resolution attempts were made and why each failed. A refusal a reader cannot
act on is how this row sat in the backlog.

Do not silently pass the gate when the base is unknown. Unknown base means the gate cannot do
its job, and the honest outcome is a named refusal, not a green.

## Acceptance

Build `test-worker-gate-no-origin.sh` against a fixture git repo — never a real repo, never a
real state dir — covering:

1. a repo with `origin/main` ⇒ gate behaves exactly as today;
2. a repo with no remote at all but a resolvable local base ⇒ gate runs and judges the output;
3. a repo where no base can be resolved ⇒ gate refuses, and stderr names each attempt;
4. the refusal in case 3 is distinguishable from a worker-produced failure.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never run the suite against the real repo; build fixture repos in a temp dir and remove them
  on every exit path, including failure.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

All four cases pass, and a mutation that restores the unconditional refusal turns the suite red
with the exit code following.
