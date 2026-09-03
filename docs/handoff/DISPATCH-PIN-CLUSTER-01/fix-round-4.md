# DISPATCH-PIN-CLUSTER-01 — round 4 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/lib/leadv2-admission-class.sh,plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh,plugins/leadv2/scripts/tests/test-plan-in-lane.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh

Seven commits, HEAD `e9e22d3`. Full report: `docs/handoff/DISPATCH-PIN-CLUSTER-01/review-r3.md`
— read it; the Mediums and Lows are yours too. Verdict: 1 Critical + 6 High + 7 Medium + 5 Low,
and **all four original defects graded PARTIAL, none FIXED**.

**Accepted, do not redo:** the suites are real and the reviewer re-ran them independently —
placement-pin 27/0 (3m50s), plan-in-lane PASS, containment PASS, dirty-lane PASS,
admission-class 24/0, class-floor PASS. The reviewer also produced its own three RED→GREEN
mutation pairs. `plugins/` in the lane is byte-unchanged by the review.

**C1 is already fixed** — `e9e22d3` untracked the 15 control-plane files (nine of them symlinks
with absolute `/Users/…` targets) that the lead's `git add plugins/` swept into `ef90ce2`. Do not
redo it; do not re-add them. Learn the shape: stage explicit paths, never a directory.

The six Highs below are one disease in six places — **a fix that is present, tested, and inert on
the live path.** That is the same disease as the round-2 Critical, and it is why every original
defect is still only PARTIAL.

## [High] H1 — `_deliver_plan_into_lane` still fails open on an empty `founder_task_id`

Probe on a real ensure-created lane: `rc=0 status=not_required journal=''`. It returns 0 silently,
and `LANE_PLAN_DELIVERY_STATUS` is read **only by the test** — nothing in production consumes it.
The round-2 brief said an unset binding at that point must be a loud failure, never a silent
`return 0`. Make the no-op branch distinguishable in production: journal it and refuse, or bind
the id the placement step already resolved (see the `--resume-lane` finding in
`live-evidence-20260830-0820.md`, same root).

## [High] H2 — the plan glob runs against the wrong directory

`for f in … plan-*.md` globs against the **dispatcher's cwd**, not the handoff dir, so
`plan-architect.md` is never delivered — while the injected mission line tells the worker to read
it. Reproduced by the reviewer. A worker is therefore instructed to open a file that was never
copied. Anchor the glob to the handoff directory and add the control: an ensure-created lane whose
handoff dir contains `plan-architect.md` must receive it.

## [High] H3 — the lane-guard fix is inert in production

`leadv2-dispatch-product-close.sh` re-defines `_PC_BOOTSTRAP_PREFIX_RE` and
`_pc_drop_bootstrap_dirt` **after** sourcing the new lib, so the close gate runs the pre-fix
regex. Demonstrated on one fixture: `LIB: CLEAN` vs `CLOSE: DIRTY`. The round-2 High is fixed in
the library and has no effect on the path that actually grades a lane. Delete the shadowing
re-definitions and add a control that exercises the CLOSE gate, not the lib.

## [High] H4 — `lane-guard.sh:45` fails OPEN on bash 3.2

`task_lines[@]: unbound variable` under `set -u` on macOS `/bin/bash` 3.2.57. Inside `$( )` that
makes the dirty-lane guard fail open — the worst direction for a guard whose whole job is to
refuse. Bash 3.2 is the live interpreter here; treat 4.x-only array syntax as unavailable
throughout.

## [High] H5 — the class floor is skipped by the digest-match early return

`:3546` returns before the floor is consulted, and `test-class-floor-survives-resume.sh` never
calls `_admission_classify` — so the suite passes while the floor is bypassed in production. This
is the third round the class floor has been reported fixed. Make the test call the real function.

## [High] H6 — `_PC_LANE_TOPLEVEL` was orphaned by the refactor

The `lane_root_not_a_worktree` evidence line always prints `<unresolved>`, so the guard's own
diagnostic is uninformative exactly when it fires.

## Rules

- **Stage explicit paths.** `git add <file> <file>`, never `git add plugins/`. C1 happened that way.
- Every fix keeps its negative control and you RUN it: mutation inside the function body, RED,
  revert, GREEN. Paste the runs and leave the RED output in the handoff dir.
- A control must exercise the PRODUCTION path. H3 and H5 are both suites that test a function
  production does not call — do not add a seventh.
- Bash 3.2 only. No `read -N`, no 4.x array idioms.
- Commit before you stop. Four workers died mid-round today leaving work uncommitted; the lead
  picked it up by hand each time.

## Done means

`git -C <lane root> status --porcelain` shows only control-plane residue and **nothing under
`plugins/leadv2/scripts/docs/` or `plugins/leadv2/scripts/.claude/` is tracked**, commit shas
reported, one line per finding saying fixed or disputed-with-evidence, and for H1/H2/H3/H5 a
paste of the production-path probe proving the fix now fires where it did not.
