# ANTI-SILENCE-STATUSLINE-01 — round 7: one of six was real

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

Full report: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r6.md`. HEAD is `6ad3b97`.

**Item 1 is real and verified independently — keep it exactly as it is.** MUT-Z and MUT-V are now
genuinely distinct controls: mutating each production line separately drives its own assertion red
(MUT-Z 43/2 with MUT-V still green; MUT-V 42/3). That was the round-6 headline and it landed.

**The locale FIX is also real** — the render is identical under `LC_ALL=C` at six widths, and
removing the export visibly breaks it. Keep the fix. Its control is what is broken.

Five things remain.

## [Critical] every `roundN-red/` artifact in this lane is invisible to git, and none was regenerated

`.gitignore:40` ignores `docs/handoff/*/*`, so nothing in `round5-red/` or `round6-red/` was ever
committed. On top of that, no file in `round5-red/` was touched in round 6 — all mtimes predate
HEAD by about two hours — and `MUT-Z.log` still records `pass=43 fail=0` under a RED header. There
is no `round6-red/` at all.

Two things to do, and the first is what makes the rest checkable:

1. **Commit artifacts with `git add -f <file>`**, one file at a time. Do not edit `.gitignore` —
   several lanes share it and this lane does not own it.
2. **Regenerate every artifact from a run whose exit status you assert**, and make the writing step
   fail loudly when the run it records did not go red. An artifact that misreports its own outcome
   is worse than a missing one — it is what the next reviewer trusts.

## [Critical] the F5 control mutates a copy and asserts the copy

It mutates a scratch copy and then asserts the mutation behaves as mutated — which is always true.
The reviewer reverted `_surf_clip_plain` to a raw byte slice **in production** and the suite output
was byte-identical to baseline, both F5 assertions green.

Write a behavioural assertion on the real render, apply the revert to the production function body,
and show it RED.

## [Critical] the `LC_ALL=C` control can never pass

It greps for `ки`, a string prefix-shortening never emits, so it is red at baseline **and** red with
the fix removed — 44/1 either way. A control that fails identically in both states measures nothing.

Assert on something the render actually produces under `LC_ALL=C`, and prove it: red with the
locale fix removed, green with it in place.

## [High] the suite regressed, and the surface baseline is still red

`test-statusline-readable.sh` went 43/0 → 44/1 in round 6. And `test-status-surface.sh` still exits
1 at baseline: 89/1, `OUTCOME-3` expects 🔴 1 and gets 🔴 3 — the exact assertion round 6 set out to
repair. Get both green at baseline and paste the runs.

## [High] F9 is unmoved after three rounds

Measured twice by the reviewer: 85.1 ms and 103.5 ms per tail render against a 4.8–5.6 ms floor.
The 8 + 6 `$(…visible_len)` subshell forks are untouched — that is where the time goes. This runs on
every render of the founder's statusline. Remove the forks (compute width without a subshell per
field) and paste a before/after measurement taken the same way twice.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the PRODUCTION file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); **no control that mutates a scratch copy** — that is the F5 defect above.
- One distinct assertion per mutation; never copy an assertion between controls.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set before committing and paste the runs.
- `git add <file> <file>` (with `-f` for the artifacts), never `git add <dir>`. Commit before you stop.

## Done means

`round7-red/` committed and holding a RED/GREEN pair per fix, each artifact's recorded outcome
matching its run; F5 and the `LC_ALL=C` fix each held by a control that goes RED against production;
`test-statusline-readable.sh` back to 0 failures and `test-status-surface.sh` green at baseline;
and tail render time near the 5 ms floor with the measurement pasted.

## Round-7 continuation (lead, second attempt stopped after the suite repair)

Two things are DONE — keep them. `test-statusline-readable.sh` is back to 45/0 and
`test-status-surface.sh` is green at baseline, 90/0. I committed that work as `560a464` and
`75b6a04` after the workers went quiet with it uncommitted.

Still outstanding, in order: the F5 control (it mutates a scratch copy, so it can never fail — the
reviewer reverted `_surf_clip_plain` in PRODUCTION and the suite stayed green); the `LC_ALL=C`
control (it greps for `ки`, which prefix-shortening never emits, so it is red in both states);
`round7-red/` artifacts regenerated from asserted runs and committed with `git add -f`; and F9,
where the tail render is still ~85-100 ms against a ~5 ms floor because of the 8 + 6
`$(…visible_len)` subshell forks.
