# critic — review of /tmp/fork.diff (dispatch-dispatch-ff526ba5-review)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=1 medium=2 low=2

FINDING: severity=Critical file=plugins/leadv2/scripts/tests/test-fork-session.sh line=69 dimension=correctness desc=Test change alone turns 11 failures green without any production change — the fix has zero regression coverage and the harness now masks the very bug it tests
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-fork-session.sh line=284 dimension=correctness desc=Comment claims "every control-plane call" is threaded but the fix is empirically incomplete — 4 tests still fail on the answered path with the fix applied

---

## Scope

Diff touches two real files (the other three paths are handoff artifacts —
`docs/handoff/dispatch-2f22f5c8/review.diff` etc., 1039 lines of committed
review noise; see Low-2):

- `plugins/leadv2/scripts/leadv2-fork-session.sh` (+13/-3)
- `plugins/leadv2/scripts/tests/test-fork-session.sh` (+4/-4)

The file does not exist on `main`; both blobs were resolved directly
(`git cat-file -p 9e10593` / `1e6db83`) and the suite was run against a staged
copy of the `810129d0` worktree tree.

## The premise is sound

`leadv2-state-path.sh:75` reads `PROJECT_ROOT`, not `LEADV2_PROJECT_ROOT`:

```
LINK_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
```

and `LINK_ROOT` feeds `STATE_ROOT` via git-common-dir (`:81-113`) even for
`--no-link` calls. So threading `PROJECT_ROOT` through `cmd_ask`'s three
state-path calls and the delegated `leadv2-ask.sh` is the correct direction.
The delegation at `:404` is also correct: `leadv2-ask.sh:193` resolves
`LEGACY_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT:-$(pwd)}}"`, so the
threaded value is honoured and agrees with `ask_project_root`.

The execution is what fails.

---

## Critical

### C1 — The test change is a masking change, not coverage
`plugins/leadv2/scripts/tests/test-fork-session.sh:69,97,183,209`
category: test-coverage

Each of the four test hunks adds `PROJECT_ROOT="${root}"` to the harness
`export` line. I ran the 2×2 matrix (base/new script × base/new tests) on a
staged tree. Raw results:

```
### script=base.sh tests=base-test.sh
=== 17 passed, 11 failed ===

### script=new.sh  tests=new-test.sh
=== 30 passed, 0 failed ===

### script=base.sh tests=new-test.sh      <-- decisive
=== 30 passed, 0 failed ===

### script=new.sh  tests=base-test.sh
[TEST] FAIL: fork question could not be answered / answer not recorded
[TEST] FAIL: answered ask rc=3 out= (expected rc=0 label=d)
[TEST] FAIL: answered-retry rc=3 out=
[TEST] FAIL: record still present after answer
=== 26 passed, 4 failed ===
```

**`base script + new tests` = 30 passed, 0 failed.** Delete the entire
`leadv2-fork-session.sh` half of this diff and the suite is still green. The
production fix is neither necessary nor sufficient for the suite to pass; the
four `export PROJECT_ROOT` lines are doing 100% of the work.

That is not a coverage gap by accident — it is an inversion. `PROJECT_ROOT` is
precisely the value `cmd_ask` is now responsible for computing and passing.
Exporting it from the harness supplies it from the outside, so the production
code path can never be observed failing to supply it. The B1 guard in
`leadv2-state-path.sh:185-188` exists to shout exactly this, and it was
shouting in the pre-diff run:

```
[TEST] FAIL: refusal does not quote the pending question: [leadv2-state-path] ABORT:
LEADV2_STATE_ROOT is set (a sandbox-only signal — production never sets this) but the
resolved LINK_ROOT (/Users/.../Projects/leadv2/.claude/worktrees/810129d0) is a real repo
checkout ... This means PROJECT_ROOT/LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR was not
threaded to THIS specific call, so LINK_ROOT fell back to cwd.
```

`leadv2-state-path.sh:167-168` warns about this in so many words:

> Twice before, a test that sandboxes the control plane via `LEADV2_STATE_ROOT`
> still forgot to ALSO thread `PROJECT_ROOT`/`LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR`

The diff resolves that warning in the wrong direction — it silences the
detector instead of leaving it armed over the fixed code.

**Required fix.** Revert all four `PROJECT_ROOT="${root}"` harness exports. The
production fix must be what makes those cases pass. Then add one case that
asserts the threading directly and would fail if `cmd_ask` regressed — e.g.
sandbox with `LEADV2_STATE_ROOT` set, `LEADV2_PROJECT_ROOT` set, cwd
deliberately outside the sandbox repo, assert `fork-ask/<tid>.yaml` lands under
`$LEADV2_STATE_ROOT` and that no `[leadv2-state-path] ABORT` appears on stderr.
If the harness must set `PROJECT_ROOT` for unrelated cases, set it only in
those cases, never in the four `cmd_ask` cases under test.

---

## High

### H1 — The fix is incomplete; the diff's own comment is false
`plugins/leadv2/scripts/leadv2-fork-session.sh:283-287`
category: correctness

The added comment states:

```
# Thread it through every control-plane call, including the delegated ask.sh
```

It is not threaded through every control-plane call. With the production fix
applied and the harness change reverted, four cases still fail — all on the
answer-consumption path:

```
[TEST] FAIL: fork question could not be answered / answer not recorded
[TEST] FAIL: answered ask rc=3 out= (expected rc=0 label=d)
[TEST] FAIL: answered-retry rc=3 out=
[TEST] FAIL: record still present after answer
```

`rc=3` is "still pending" — the ask never observes the answer. The answer is
written by a separate control-plane writer (`$ANSWER` → `leadv2-reply.sh`,
invoked at `test-fork-session.sh:112`) which resolves its own control plane and
is not covered by this diff. Whatever the exact resolution mismatch, the
empirical fact stands: **with this diff's production change and without the
harness masking, the ask/answer round-trip is still broken in a sandboxed
control plane.**

Because C1's harness change hides these four failures, the diff ships looking
green while the answered path remains unfixed.

**Required fix.** Either (a) extend the threading to the reply/answer writer so
the round-trip closes on the production path, or (b) if the reply side is
out of scope, say so in the commit message, leave the four cases failing or
explicitly skipped with a linked follow-up, and do not paper over them with a
harness export. Do not claim "every control-plane call" in a comment that four
red tests contradict.

---

## Medium

### M1 — `cmd_preflight`'s control-plane call is left unthreaded
`plugins/leadv2/scripts/leadv2-fork-session.sh:213`
category: correctness

```
control_plane="$(bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root)"
```

Same class as the bug being fixed, 70 lines above it, untouched. `:169` exports
`LEADV2_PROJECT_ROOT` — which `leadv2-state-path.sh` does not read — so this
call falls back to the ambient cwd toplevel. The value is then persisted into
`fork-lane.env` as `CONTROL_PLANE=` and consumed by the forked session, so a
wrong resolution propagates into the lane rather than failing loudly.

In the common case it converges (state-path does its own git-common-dir
resolution, so a lane worktree still lands on the main root). It diverges when
`LEADV2_PROJECT_ROOT` names a tree that is not cwd's repo — exactly the sandbox
shape. `case_preflight` sets `LEADV2_STATE_ROOT`, which short-circuits
`STATE_ROOT` before `LINK_ROOT` matters, so the suite cannot see this.

Pre-existing, not a regression from this diff — but the diff's comment claims
to have covered it. Fix: `PROJECT_ROOT="$project_root"` on the `:213` call, or
hoist `ask_project_root` into a script-level resolution used by both commands.

### M2 — `legacy_answered` uses a different resolution chain than `qdir`
`plugins/leadv2/scripts/leadv2-fork-session.sh:422`
category: correctness

```
legacy_answered="${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/docs/handoff/..."
```

`ask_project_root` (`:289`) falls back to `resolve_project_root`, which walks
**git-common-dir** to the main checkout (`:101-116`). This line falls back to
**`git rev-parse --show-toplevel`**, the worktree itself. Invoked from a linked
lane worktree with `LEADV2_PROJECT_ROOT` unset, `qdir` resolves against the
main root while `legacy_answered` resolves against the lane — the two halves of
the same poll loop look at different trees. The legacy branch only fires when
the control-plane write degraded, which is why nothing catches it.

Fix: reuse `ask_project_root` here.

---

## Low

### L1 — Dead `${LEADV2_PROJECT_ROOT:-}` branch
`plugins/leadv2/scripts/leadv2-fork-session.sh:289`

```
ask_project_root="${LEADV2_PROJECT_ROOT:-$(resolve_project_root 2>/dev/null || pwd)}"
```

`resolve_project_root` already returns `$LEADV2_PROJECT_ROOT` first thing
(`:102-105`). The `${LEADV2_PROJECT_ROOT:-...}` wrapper is unreachable
duplication. Shrink to `ask_project_root="$(resolve_project_root 2>/dev/null || pwd)"`.

Note the behavioural edge this introduces: a caller that exports `PROJECT_ROOT`
but not `LEADV2_PROJECT_ROOT` previously had its `PROJECT_ROOT` flow through to
`leadv2-state-path.sh` untouched; now `cmd_ask` overwrites it with a cwd-derived
value. In practice this converges (git-common-dir maps a lane worktree back to
the main root), so it is Low — but it is a silent override of an explicit
caller signal and deserves a line of comment if kept.

### L2 — 1039 lines of review artifacts committed with the code change
`docs/handoff/dispatch-2f22f5c8/review.diff` (+1039),
`docs/handoff/dispatch-2f22f5c8/review-codex.err` (+1),
`docs/handoff/dispatch-2f22f5c8/review-codex.md` (empty file)

A committed empty `.md` and a 1039-line vendored diff are transient reviewer
output belonging to a different dispatch (`2f22f5c8`), bundled into a fix for
`ff526ba5`. Split them out or gitignore the artifact paths — they make the real
16-line change impossible to see in `git log -p` and will conflict on every
parallel lane that writes the same handoff dir.

---

## Type / lint evidence

Pure Bash — `mypy`/`tsc` do not apply. `shellcheck` is not installed on this
host (`shellcheck: NOT INSTALLED`), so no lint evidence is available; syntax
checks only:

```
$ bash -n plugins/leadv2/scripts/leadv2-fork-session.sh
bash -n: clean
$ bash -n plugins/leadv2/scripts/tests/test-fork-session.sh
bash -n tests: clean
```

Both files parse. That is the limit of what was verifiable statically; the
behavioural evidence in C1/H1 is the load-bearing part of this review.

## Verdict

**BLOCK.** The production change is directionally right and does fix 7 of the
11 pre-existing failures — but it is shipped alongside a harness change that
makes the suite green regardless of whether the production change exists, and
that same harness change conceals 4 remaining real failures on the answered
path. Reverting the four `export PROJECT_ROOT` lines is the minimum condition
for re-review.

DELIVERABLE_COMPLETE
