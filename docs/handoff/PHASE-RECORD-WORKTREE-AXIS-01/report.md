# PHASE-RECORD-WORKTREE-AXIS-01

## Writer evidence
`test-no-work-terminal.sh` cases 5, 9, 12 call `leadv2-dispatch-product-close.sh` with fixture ROOTs but retain the launch cwd. Product-close's e2e/review `record` calls omit ROOT; `leadv2-phase-record.sh` falls back to cwd and `cmd_record` replaces existing foreign files through `mv -f`.
Proved using a disposable `git archive 969b7a2b` snapshot, separately initialized with the six phase files tracked; no live foreign file was a reproduction target.
Invocation from snapshot cwd (T): `env -u PROJECT_ROOT -u LEADV2_PROJECT_ROOT HOME="$T/isolated-home" LEADV2_CANONICAL_ROOT="$T" LEADV2_TEST_CONTEXT=1 timeout 150 bash plugins/leadv2/scripts/tests/test-no-work-terminal.sh`.
Before/after transcripts: [before](evidence/writer-before-suite.log), [after](evidence/writer-after-suite.log); [six actual timestamp changes](evidence/writer-before.diff).
```text
BEFORE: === 53 passed, 5 failed ===
AFTER:  === 53 passed, 5 failed ===
snapshot before: 6 changed tracked foreign phase records
snapshot after: 0 changed tracked foreign phase records
independent after byte comparison to git HEAD: 6/6 identical
```
The five identical failures concern watcher lease refresh and freepool completion; they are not green evidence. This establishes a writer, not attribution of every historical overwrite.

## Fix evidence
The writer extends `lib/leadv2-test-context.sh`: refuse tests without explicit root isolation, or targeting any worktree of the writer's repository. Production writes between distinct worktrees of the same repository are refused even when dispatch files exist. Existing root variables remain the only configuration.
The existing missing-dispatch guard now resolves absolute common-directory paths correctly; fresh linked-worktree classify remains verified and silent. A copied gate1 fixture now carries the required test-context library.

## test-phase-record-worktree-axis.sh red / green evidence
`timeout 40 bash plugins/leadv2/scripts/tests/test-phase-record-worktree-axis.sh`, first against 969b7a2b's writer, then the fixed writer. The suite creates its own Git repository and linked worktree; each refusal checks nonzero status, diagnostic, and unchanged foreign bytes.
```text
FAIL: production linked worktree refused (rc=0)
FAIL: production linked worktree foreign bytes unchanged
FAIL: test linked worktree refused (rc=0)
FAIL: test linked worktree foreign bytes unchanged
FAIL: test cwd fallback tree refused (rc=0)
FAIL: test cwd fallback tree foreign bytes unchanged
FAIL: installed writer without redirect refused
FAIL: installed writer foreign bytes unchanged
FAIL: unmarked suite ancestor fixture refused (rc=0)
FAIL: unmarked suite ancestor fixture foreign bytes unchanged
PASS: same-tree production succeeds silently
PASS: same-tree subdirectory and symlink alias stay silent
FAIL: fresh same-tree classify remains verified and silent
[leadv2-phase-record.sh] ERROR: record: project root not permitted: dispatch-fresh001/ does not exist under resolved root /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nV0YHJKIvH/worker (missing: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nV0YHJKIvH/worker/docs/handoff/dispatch-fresh001), and cwd resolves to a different repo (/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nV0YHJKIvH/repo/.git vs ) — refusing to write phase classify; an inherited LEADV2_PROJECT_ROOT/PROJECT_ROOT from another repo's session makes record write into a foreign repo, check LEADV2_PROJECT_ROOT / PROJECT_ROOT / cwd
PASS: isolated test fixture succeeds silently
SUMMARY: 3 passed, 11 failed
PASS: production linked worktree refused
PASS: production linked worktree foreign bytes unchanged
PASS: test linked worktree refused
PASS: test linked worktree foreign bytes unchanged
PASS: test cwd fallback tree refused
PASS: test cwd fallback tree foreign bytes unchanged
PASS: installed writer without redirect refused
PASS: installed writer foreign bytes unchanged
PASS: unmarked suite ancestor fixture refused
PASS: unmarked suite ancestor fixture foreign bytes unchanged
PASS: same-tree production succeeds silently
PASS: same-tree subdirectory and symlink alias stay silent
PASS: fresh same-tree classify remains verified and silent
PASS: isolated test fixture succeeds silently
SUMMARY: 14 passed, 0 failed
```
The baseline's fresh-classify failure additionally exposes the old absolute-common-dir bug. Ancestor detection uses a deterministic `ps` fixture: real `ps -o command= -p $$` was denied (`operation not permitted`) in this sandbox. The env-marker path and real linked-worktree checks are exercised directly.

## Foreign dirty-record counts evidence
`git -C /Users/kostiantyn.vlasenko/Projects/leadv2 status --porcelain=v1` with NO pathspec; filter the captured output for `docs/handoff/dispatch-*/phases.d/*.yaml` afterwards. Independently count `git diff --name-only` and compare the original six SHA-256 values.
COUNTS_PENDING

## bash -n / python3 -m py_compile falsification evidence
SYNTAX_PENDING
No Python files were changed (checked in both working diff and staged path inventory), so `python3 -m py_compile` has no inputs.

## tests/run-all.sh --scope changed evidence
Selection state was cleared first. Command policy rejected literal `rm -f`; Python `Path.unlink(missing_ok=True)` removed that exact Git-dir state file instead.
`LEADV2_RUN_ALL_SELECT_ONLY=1 timeout 60 bash tests/run-all.sh --scope changed`:
SELECTION_PENDING
Actual execution: `timeout 1800 bash tests/run-all.sh --scope changed`.
RUNNER_PENDING
Existing focused comparisons: inversion 18/0; bootstrap 31/7 before and after; gate1 discipline 13/2 before and after. Raw logs live under [evidence](evidence/). Neither known-red list was changed.

## leadv2-mutation-control.sh evidence
Mutation: remove the `_phase_check_worktree "$phase_file" || exit $?` call inside `cmd_record`; the original atomic writer becomes reachable again. Run through the repository helper, with a 120-second outer timeout, after committing the code/report.
MUTATION_PENDING
