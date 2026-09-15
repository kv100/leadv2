# ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01

## Boundary and verdict

Verdict: four independent causes, not one shared root resolver defect.
Measurements were run from detached main commit
142e50f39048c0b048b052d0ec35d633c93f46a7 on macOS Darwin 25.6.0. The
prior census boundary is 27 red of 93 selected suites at a 120-second
per-suite ceiling. This report covers four faces of that population. No
production script was changed; the only checkout changes are this report and
the sandboxed probe.

## Face 1: absolute @mission

Reproduced by a source-only fixture. The placement suite itself timed out at
240 seconds before this branch, so its timeout is not used as causal proof.

~~~
[leadv2-dispatch-code] REFUSE mission:
path=/tmp/root-path-f1.2o2E9e/repo/docs/handoff/X/mission.md
is absent from both lane worktree=/private/tmp/root-path-f1.2o2E9e/repo/.claude/worktrees/LANE
and main
FACE-1-RC=5
~~~

Wrong decision: plugins/leadv2/scripts/leadv2-dispatch-code.sh:1303. The
preflight sends the absolute filesystem path to git ls-tree, which requires a
repository-relative tree path. Lines 1313 and 1321 repeat that raw value in a
candidate path join and a main tree lookup.

Compared values:

~~~
raw=/tmp/.../repo/docs/handoff/X/mission.md
candidate=/private/tmp/.../repo/.claude/worktrees/LANE
required tree path=docs/handoff/X/mission.md
~~~

Authority: lane worktree/registry pin, followed by an incorrect conversion to
a Git tree path. This is not phase-store, journal, or event-log resolution.

Negative control: a scratch copy under /tmp converted an absolute path beneath
PROJECT_ROOT to docs/handoff/X/mission.md before the line-1303 lookup. The
same committed mission then returned:

~~~
RESUME=/private/tmp/root-path-f1-control.U98G1R/repo/.claude/worktrees/LANE
FACE-1-CONTROL-RC=0
~~~

The scratch mutation was removed. This is a Face-1-only mutation.

Suite baseline:

~~~
FACE-1 RED rc=124 case=lane-placement-pin
[TEST] PASS: P-a: dispatch exited 0
[TEST] PASS: P-a: worker cwd == RESUME-ME-01 worktree
[TEST] FAIL: P-h(a): prompt pin line MISSING with --resume-lane
~~~

## Face 2: journal pinned root

Reproduced as an inherited-environment precedence mismatch, not as a missing
LEADV2_PROJECT_ROOT rung.

~~~
== the journal writes where the caller pinned it
  FAIL — (b) pin ignored, resolved to '.../leadv2-state/leadv2/tasks/fixture-task/journal.md'
  FAIL — (a) NEG-CTL: the new rung overrode an explicit CLAUDE_* pin
  FAIL — (a2) NEG-CTL: rung overrode CLAUDE_PROJECT_DIR
passed=2 failed=4
SUITE_RC=1
~~~

Decision site: plugins/leadv2/scripts/leadv2-journal.sh:48. Its precedence is
CLAUDE_PROJECT_ROOT, then CLAUDE_PROJECT_DIR, then LEADV2_PROJECT_ROOT, then
cwd. Lines 81-90 pass the same precedence to state-path.

Compared values:

~~~
CLAUDE_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2
LEADV2_PROJECT_ROOT=/private/tmp/.../pinned
winner=CLAUDE_PROJECT_ROOT
~~~

Authority: journal. The suite does not clear inherited CLAUDE variables, so
its assertion that LEADV2_PROJECT_ROOT is alone is false in this session.

Negative control, from the delivered probe:

~~~
FACE-2 RED ... CLAUDE=.../claude LEADV2=.../pinned resolved=.../.ephemeral/claude-...
FACE-2 CONTROL GREEN unset_CLAUDE resolved=.../.ephemeral/pinned-...
~~~

Removing CLAUDE_PROJECT_ROOT and CLAUDE_PROJECT_DIR moves only this face. The
ephemeral key format is also why the suite's old bare-key expectation fails.

## Face 3: landed-at-spawn / target keying

Reproduced, but it fails before target-repository keying.

~~~
[leadv2-dispatch-code] premise_probe task=ff7cfeec verdict=refused reason=backlog_row_not_found
[leadv2-dispatch-code] ERROR: premise refused: reason=backlog_row_not_found ...
[TEST] FAIL: T-a: dispatch exited 8 (expected 0)
[TEST] FAIL: T-b: dispatch exited 8 (expected 4)
[LANDED-AT-SPAWN-01] passed=4 failed=8
~~~

Wrong decision for this suite invocation:
plugins/leadv2/scripts/leadv2-dispatch-code.sh:9098 invokes the premise gate;
its no-row branch is lines 8410-8412 and exits 8. The suite's ad-hoc mission
has no backlog row and no audited no-probe-yet declaration, so it cannot reach
the ledger assertions.

The target keying itself is correctly derived at lines 481-495:

~~~
target lane=/tmp/.../target-wt
PROJECT_ROOT=/tmp/.../decoy
WORK_ROOT=/tmp/.../target-wt
LEDGER_REPO_ROOT=/tmp/.../target
~~~

Authority: lane worktree/registry pin, but no erroneous path comparison fires
for this face. Its red is a distinct premise-gate precondition.

Negative control: source-only initialization with the same decoy and target
values yields LEDGER_REPO_ROOT=target. A real backlog row or the audited
no-probe-yet route is required before this suite can test the ledger.

## Face 4: foreign repository stop-gate journal

Reproduced.

~~~
[TEST] FAIL: foreign-repo-journaled -- post-fix rc=1, expected 0
Results: 10 passed(red->green), 3 failed, 0 green-pre-fix, 0 could-not-run
SUITE_RC=1

FACE-4 RED rc=1 case=foreign-repo-journaled
Results: 12 passed(red->green), 1 failed, 0 green-pre-fix, 0 could-not-run
FAILURES:
 - foreign-repo-journaled: post-fix did not pass (rc=1)
~~~

The initial suspicion was product-close.sh:2750, which only classifies an
absolute declared path as foreign. A scratch physical-resolution mutation at
that line did not move the case. The path does resolve to the other repository;
the failed control instead proves that this capture function is not invoked on
the normal no-worker path used by the test.

The actual wrong decision is the call ordering in
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3756. It calls
pc_stop_gate_autocommit without the only pre-scan that populates
PC_STOP_GATE_FOREIGN_REPOS. That pre-scan, pc_stop_gate_capture_diff, runs
only in the timeout branches at lines 3673 and 3702. The normal path therefore
sees the initialized empty array from line 2931 and cannot emit the journal
row at line 2818.

The test fixture at plugins/leadv2/scripts/tests/test-stop-gate.sh:316 builds:

~~~
lane=/private/tmp/leadv2-sg.A/root/.claude/worktrees/TASK
other=/private/tmp/leadv2-sg.B
declared path=../../../../leadv2-sg.B/agent/foreign.py
resolved declared path=/private/tmp/leadv2-sg.B/agent/foreign.py
actual other path=/private/tmp/leadv2-sg.B
~~~

The declaration does resolve to the actual other root. The missing journal is
caused by the normal-path omission of the foreign pre-scan, not the spelling.

Authority: product-close lifecycle ordering, not journal, phase-store, event
log, or lane registry.

Negative control output, with a scratch-only physical-resolution mutation:

~~~
[TEST] FAIL: foreign-repo-journaled -- post-fix rc=1, expected 0
FACE-4-CONTROL-RC=1
~~~

It does not move this case, ruling out line 2750 as the causal line. The
double-ended ordering control adds the existing pre-scan immediately before
line 3756 in a scratch copy:

~~~
[TEST] RED-then-GREEN: foreign-repo-journaled (pre_rc=1 -> post_rc=0)
Results: 13 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
FACE-4-ORDER-CONTROL-RC=0
~~~

That single Face-4 mutation moves this face without affecting Faces 1-3.

## macOS spelling control

The /var versus /private/var alias does not fire in the four decision sites.
Face 1 is a Git tree-path error; Face 4 is a relative-path predicate. The
dispatcher root guard already normalizes ordinary root comparisons at
leadv2-dispatch-code.sh:386 and :393.

~~~
MACOS-VAR-PRIVATE CONTROL GREEN
raw=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/root-path-var-control.O3W3PA
physical=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/root-path-var-control.O3W3PA
same_directory=1
~~~

This host TMPDIR did not hand out a /var spelling, so the control proves the
physical comparison used by the probe but does not claim a /var alias fired.

## Double-ended separation

| Face | Decision site | Mechanism |
| --- | --- | --- |
| 1 | dispatch-code:1303 | absolute filesystem path used as Git tree path |
| 2 | journal:48 | inherited CLAUDE root outranks LEADV2 root |
| 3 | dispatch-code:9098 and 8410-8412 | premise gate exits before ledger |
| 4 | product-close:3756 | normal path skips foreign-repository pre-scan |

The Face-4 physical-resolution mutation does not move Face 4, falsifying its
first proposed line; the line-3756 ordering mutation does move Face 4.
Clearing inherited CLAUDE variables moves Face 2 only. Supplying the missing
premise declaration is required before Face 3 reaches target keying. No single
line or authority moves two faces.

## Falsification set

~~~
$ bash -n plugins/leadv2/scripts/tests/probe-root-path-resolution-census.sh
rc=0

$ timeout 720 bash plugins/leadv2/scripts/tests/probe-root-path-resolution-census.sh
FACE-1 RED rc=124 case=lane-placement-pin ...
FACE-2 RED rc=1 case=journal-pinned-root ...
FACE-3 RED rc=1 case=landed-at-spawn ...
FACE-4 RED rc=1 case=foreign-repo-journaled ...
MACOS-VAR-PRIVATE CONTROL GREEN ... same_directory=1
~~~

No Python file changed. The changed-scope runner is the probe above; its red
lines are the intentional before measurements and its process exit is zero.
No production fix was made, so there is no green-after-fix claim.

VERDICT: N DEFECTS (n=4)
