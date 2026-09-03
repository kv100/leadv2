# DISPATCH-PIN-CLUSTER-01 — fix round 2 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`
Your 3 commits are there. `docs/handoff/DISPATCH-PIN-CLUSTER-01/context.yaml` is still BINDING.
Round 1 tests are now real — that part is accepted. This round is the review findings.

Verdict: `status: fail`, `reviewer_says: do_not_merge`, 1 Critical + 4 High + 6 Medium + 3 Low.
Full report: `docs/handoff/dispatch-DISPATCH-PIN-CLUSTER-01/review-opus.md`. Read it for the
Mediums and Lows; the four below are quoted verbatim from the gate and are non-negotiable.

## [Critical] leadv2-dispatch-code.sh:6024 — the D3 fix never fires

> `_deliver_plan_into_lane` is called before the ensure block assigns `WORK_ROOT`, so it no-ops
> on every ensure-created lane and the feature never fires.

This is the whole task's own disease: a fix that is present in the source, passes its test, and
does nothing at runtime. Move the call after `WORK_ROOT` is bound, and make the no-op branch
distinguishable from the success branch — an unset `WORK_ROOT` at that point must be a loud
failure, never a silent `return 0`. Your test must exercise the ENSURE-created path, not only a
`--worktree`-pinned one; that is the gap that let this through.

## [High] lib/leadv2-lane-guard.sh:6 — the exclude regex cannot match

> `_PC_BOOTSTRAP_PREFIX_RE` double-escaped (`'\\\\.claude'`) never matches, so the ledger grades
> bootstrap-symlink-only lanes dirty and downgrades `landed` to `pass_unlanded`/`refused`.

This is the total-outage failure mode named in `context.yaml` D1-EXCLUDES: a broken exclude set
means nothing ever lands. Fix the escaping and add the case that would have caught it — a lane
dirty ONLY with bootstrap symlinks must land.

## [High] lib/leadv2-lane-guard.sh:61 — containment blames the wrong writer

> `lv2_lane_containment_violation` attributes any new main-checkout path to this lane; concurrent
> lanes, the lead session and hooks write there (`.claude/settings.json`, `docs/tasks.yaml`, …).

With two lanes running — the normal case — lane A gets refused for lane B's writes. Attribution
must be to THIS lane or it must not accuse: narrow the verdict to paths inside this lane's
declared write set, or drop the accusation and report it as unattributed. Do not ship a guard
that fires on a second concurrent lane.

## [High] lib/leadv2-admission-class.sh:333 — the class floor is not a floor

> `task-class.yaml` is written last-writer-wins, so a later Light dispatch of the same founder
> task overwrites a Heavy record and the "floor" is not monotonic.

`context.yaml` D4-SHAPE says FLOOR, never demotion. Make the write monotonic: a lower class can
never overwrite a higher one for the same founder task. Test both orders (Heavy-then-Light and
Light-then-Heavy) — one order passing is not evidence.

## [High] leadv2-dispatch-code.sh:26

Truncated in the gate file. Read it in `review-opus.md` and fix it with the rest.

## Live evidence from this session, for the D4 work

An explicit `--task-class standard` was passed on FOUR separate dispatches today and the
dispatcher resolved `class=light` every time, routing plugin-core work to `freepool`, which
produced only an anchor commit twice. The only thing that kept the work off the cheapest arm was
`--protected` — a flag about the PATH, not about the class. So the first-dispatch case (no prior
receipt) is the live hole: an explicit `--task-class` must bind there.

## Rules for this round

- Every fix keeps its negative control, and you RUN it: mutation inside the function body, RED,
  revert, GREEN. Paste the runs.
- Add a control for the Critical specifically: an ENSURE-created lane (no `--worktree`) must
  receive the plan.
- Do not weaken any existing test to make a fix pass.
- Note: this review ran with a single arm (`verified: 0/5 reason=single_arm_pool` — codex was
  excluded as author, glm at 81% quota). The findings are therefore UNVERIFIED by a second arm.
  If you believe one is wrong, say so with evidence and do not silently ignore it.

## Done means

`git -C <lane root> status --porcelain` shows only control-plane residue. Commit shas reported,
every mutation run pasted red-then-green, and one line per finding saying fixed or disputed-with-
evidence.
