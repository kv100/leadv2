# PROMISE-GUARD-BIND-01 — round 3 (one item left, and it is the point of the task)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/tests/test-promise-guard.sh,tests/run-all.sh,docs/handoff/PROMISE-GUARD-BIND-01/

Full report: `docs/handoff/PROMISE-GUARD-BIND-01/review-r2.md`. HEAD is `4cc9eac`; resume from it.

**Six of seven items reproduce as WORKS, verified independently — do not touch any of them.** The
journal sandbox holds (size/inode/mtime identical before and after all three suites) and its escape
control goes red under a real mutation; the pre-image is byte-identical to `e994f07` and an
unresolvable pre-image now hard-fails in a non-git dir and with the fixture removed;
`2>/dev/null`, `2>&1` and `> /dev/null` all classify as `[]`; the scheduled-decision row parses as
`PROMISE-GUARD-BLOCK-FLIP-01:CONDITION_BOUND`; the rollout stays silent with `BLOCK` unset or 0. All
five mutations go red. bash 3.2.57 clean. That is good work.

## [Critical] the Russian extractor still misses the promises the lead actually writes

This is the whole reason the task exists: the lead writes in Russian, and a guard that does not
recognise the forms he uses will never fire on a real turn.

Still `rows=0 NO-ROW` through the real hook:

- `Сейчас напишу отчёт`
- `Сейчас исправлю биндинг`

The reviewer found the mechanism, so this is not a search problem. `COMMIT_RU_SHAPE`
(`leadv2-promise-guard.sh:195`) requires **verb-then-marker**. A leading «Сейчас» therefore disables
the shape rule entirely and the sentence falls through to the whitelist at `:132` — so
`допишу`, `перепишу`, `обновлю`, `смерджу`, `добавлю` are all dead the same way, while the
*identical* sentence with «сейчас» at the end fires correctly.

Fix the shape rule so the marker may precede the verb. Then verify the whole family above, in both
orders, through the real hook.

## [High] the fixtures were swapped for an easier set

`test-promise-guard-morphology.sh:153-171` replaced the twelve promises named in the review with a
self-selected twelve, of which **9 already passed pre-fix** — under a comment claiming the original
set "was not committed anywhere this task could find". It is at `review-r1.md:88-98`, in this lane's
own handoff directory.

Restore those twelve as the fixtures. A fixture chosen because it already passes measures nothing,
and this repo has now hit that exact failure three times today on three different lanes.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round3-red/`.
- Do not weaken or replace a fixture to make a fix pass. If a fixture is genuinely wrong, say why in
  the commit message and keep the original alongside.
- Keep the rollout log-only under `LEADV2_PROMISE_GUARD_BLOCK=0`.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

All twelve promises from `review-r1.md:88-98` produce journal rows through the real hook (paste the
run); the marker-before-verb order handled for the whole `допишу/перепишу/обновлю/смерджу/добавлю`
family; a control that goes RED when the shape rule is reverted; and the six WORKS items still
working — re-run all three suites and paste the counts.
