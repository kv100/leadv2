# WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-worktree.sh, plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh, docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/

## 0. The defect

The live lane registry now lives OUTSIDE the repository, at
`~/.claude/leadv2-state/leadv2/active.yaml` (975 lines, 36 tasks, measured 2026-09-04). On `main`
the in-repo path `docs/leadv2/active.yaml` is untracked. **But on the branches it is still in the
index**, so every `git worktree add` checks out a frozen copy at the in-repo path and that copy
answers questions instead of the live store.

Measured 2026-09-04 in `~/Projects/leadv2`, count these yourself before you start:

| fact | number |
|---|---|
| branches `worktree-*` carrying `docs/leadv2/active.yaml` in the index | **376 of 382** |
| `main` | untracked |
| live worktrees holding a real (non-symlink) file at that path right now | **12 of 229** |

The consequence is already paid: a lane running with 13 live processes was reported by every
registry-reading surface as absent, and the lead nearly declared the worker dead — which in this
codebase means a re-dispatch, and a re-dispatch used to destroy the first attempt's stream. Of the
twelve frozen copies, seven answer zero and five answer a plausible stale number; **the five are
worse**, because a zero invites a second look and a plausible number does not.

## 1. Scope — read this before you plan

**Your part is the moment a worktree is created, and only that.** Removing the path from the index
on 376 branches is the other lead's work on the merge queue and is explicitly NOT yours; do not
touch branch indexes, do not rewrite history, do not `git rm` anything on another branch. Your fix
must be correct even while all 376 branches still carry the file, because they will carry it for a
while yet.

**Do NOT edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh`** — another session holds it. It is
not needed: worktree creation lives in `leadv2-lane-worktree.sh`.

## 2. Where the fix goes

`plugins/leadv2/scripts/leadv2-lane-worktree.sh` has exactly two creation sites, and both already
run a post-create step (`codex_trust_worktree`), so the shape of the change is established:

- `:286` — `git worktree add -b "$branch" "$lane_path" "$base"` (fresh branch)
- `:293` — `git worktree add "$lane_path" "$branch"` (attach to an existing branch)

Both paths must get the same treatment. A fix on one of them is the "a case named for a branch that
is never reached" defect in advance: whichever site your test does not exercise is the one that will
be taken in production.

The live store's path must come from the existing resolver, not from a string you write:
`plugins/leadv2/scripts/leadv2-state-path.sh` is the canonical control-plane resolver
(`~/.claude/leadv2-state/<repo-slug>/`). Hardcoding `$HOME/.claude/leadv2-state/leadv2/...` creates
a second definition of the path, which is the disease one level up from this one.

## 3. What "points at the live store" must mean

After a lane worktree is created, a reader opening `docs/leadv2/active.yaml` inside it must see the
live registry, and the worktree must not be left dirty. Two candidate shapes; pick one, measure it,
and say why:

- **symlink to the live store** plus `git update-index --skip-worktree` on that path in the new
  worktree, so git stops comparing it (the same idiom the voice files already use in this repo);
- **no file at all** plus something that makes the absence speak — a reader that finds nothing must
  not silently conclude "no lanes".

Whichever you choose, the failure mode to design against is **the silent one**: if the pointer
cannot be created, the worktree must not be left holding a frozen copy that looks authoritative.
Say so on stderr AND make the state visibly not-a-registry. Note that
`_lv2_repoint_newest_pointer` in `claude-subsession.sh:463` does the first half and then returns 0 —
do not copy that shape.

## 4. Acceptance — it bites

- **The reproduction, before and after.** Take the first branch that carries
  `docs/leadv2/active.yaml` in its index, create a temporary worktree from it, and show: BEFORE —
  the path is a plain file with stale content; AFTER — it resolves to the live store. Remove the
  temporary worktree yourself; leave nothing behind. **Never `git worktree prune`** — live lanes
  stand next to yours and a prune has already killed two of them.
- **Both creation sites are exercised by the suite**, separately: fresh-branch and attach-to-existing.
- **A negative control per changed function body**, via `plugins/leadv2/scripts/leadv2-mutation-control.sh`,
  mutation INSIDE the body. Report the `baseline_rc` / `mutated_rc` / `restored_rc` triple.
- **Under each mutation exactly ONE assertion may go red, and it must be the one the control's name
  claims.** If an earlier assertion is the red, the mutation removed a precondition and your named
  branch is still undefended — that is a finding, report it rather than accepting the red.
- **Read the mutated line back before trusting the run.** A mutation can change the file's sha256
  and still be inert: this cost a verification round on 2026-09-04, when a `perl` replacement
  interpolated `$link_name` as its own undefined variable and the inserted guard read
  `[[ -L "" ]] && return 0`. Byte changed, meaning did not. Print the mutated line.
- **Before believing any zero, show the same probe returning non-zero.** If your check reports "no
  worktree carries a frozen copy", it must first find one of the twelve that do.
- **Ten consecutive runs**, all exit codes pasted. A disagreement between runs IS the finding.
- A mutant that reddens by crashing the suite is not a control.

## 5. Bounds

- Do not touch `tests/run-all.sh` (use a `# run-all-triggers:` declaration in the suite),
  `tests/known-red-suites.txt`, `main`, or `docs/leadv2/` — that last one is live runtime state a
  pulse reads while you work.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` in this shared tree.
- Commit incrementally. The e2e gate times out at 900s and parks lanes on the threshold between
  finished and committed — it did exactly that to the previous lane, whose work survived only
  because it had been committed as it went.
- If any instruction here rests on a false premise, stop and say so with the measurement. That is a
  complete and welcome answer.
- Do not merge to main. Leave the branch green with a report.
