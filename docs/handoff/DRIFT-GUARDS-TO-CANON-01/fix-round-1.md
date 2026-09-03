# DRIFT-GUARDS-TO-CANON-01 — fix-round 1 (review FAIL high=1, plus the round-1 proof that was never run)

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 900`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.** Round 1 committed its work and then died; that is why it survived.

**Lane:** worktree-DRIFT-GUARDS-TO-CANON-01 (resume; merge `main` FIRST).

Round 1 landed the lift itself (both hooks into `plugins/leadv2/hooks/`, wired in BOTH places,
`repo-install --check`, `link-tree-heal` reporting — 228 lines). Do not redo that.

## The finding — the guard misses the exact case it exists for
`plugins/leadv2/hooks/plugin-scripts-drift-guard.sh:51` uses `git diff --cached --diff-filter=ACMR`.
**`T` (typechange) is not in that set.** Replacing a tracked symlink with a real file and staging it is
recorded by git as `T`, not `M`. The reviewer probed it end-to-end in an isolated repo:

```
$ git diff --cached --name-only --diff-filter=ACMR -- '.claude/scripts/*.sh'
(empty)
$ git diff --cached --name-status -- '.claude/scripts/*.sh'
T  .claude/scripts/foo.sh
$ git ls-files -s -- .claude/scripts/foo.sh
100644 5d1bb36... 0  .claude/scripts/foo.sh
```

and the guard returned **rc=0, no output, no block**. The internal classifier (`ls-files -s`,
mode ≠ 120000 → REGRESSION/DRIFT) is correct — it is simply never reached. The guard fires only for `A`
(a file that was never a tracked symlink) or `M` (an already-converted copy being edited). The primary
scenario — symlink becomes a real file — walks straight through.

The fix is one character: `--diff-filter=ACMRT`. The test that proves it is the whole point of this
round.

## Do — one commit each
1. `## Review round 1 findings` in report.md: REAL/REFUTED with the evidence command. The reviewer's
   probe is pasted above; reproduce it before you agree with it.
2. The `ACMRT` fix.
3. **The typechange test**, which is also the round-1 acceptance that was never delivered: in a scratch
   repo (mktemp, not this one), create a tracked symlink under `.claude/scripts/` pointing at a
   canonical script, replace it with a real file, `git add` it, run the guard, and show it REFUSES,
   naming the file. Paste the full session.
   **Negative control:** revert `ACMRT` to `ACMR` in a mktemp FULL copy (including `lib/`) whose
   baseline is proven green → the case must go red. Paste both runs.
4. Cover the other shapes while you are there, each with its own case: a brand-new real file (`A`), an
   edit to an already-converted copy (`M`), and a rename. State plainly in the report which git status
   letters the guard now covers and which it deliberately does not.
5. `leadv2-repo-install.sh --check` against the same planted copy: exits non-zero and names the file.
   Paste it.
6. `tests/run-all.sh --scope changed` from the LANE ROOT — the path is `tests/run-all.sh` at the repo
   root, **not** `plugins/leadv2/scripts/tests/run-all.sh` (that path does not exist). FOREGROUND,
   `timeout 1800`. Paste the real tail; if it does not finish, say so and paste what it produced. A
   placeholder token in place of run output fails this round outright — that defect was found in two
   other lanes today.
7. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Also state, in the report, in one paragraph
What a session must do for these hooks to actually LOAD: the plugin cache is a separate copy and
`claude plugin update` no-ops when content changed but the version did not. A hook sitting in canon and
never loading is the lying-green disease this task exists to kill, so the next reader must not assume
canon is enough.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Fixtures and mutants in mktemp only. Tree clean, `main` merged.

## Done when
The typechange case is REFUSED by the guard with the session pasted; the negative control is red against
a green baseline; the covered git status letters are stated explicitly; `--check` exits non-zero; the
run-all tail is real; the cache-load caveat is written down.
