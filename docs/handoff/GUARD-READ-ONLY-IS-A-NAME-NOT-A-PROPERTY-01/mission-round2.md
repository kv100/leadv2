# GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01 — round 2

Round 1's change is **correct and stays**: `general-purpose` is now in `_is_write_role`, `Explore`
and `recon` remain read-only, and the messages were updated to match. Continue in this worktree;
do not restart and do not revert.

The e2e gate failed the round. The lead ran the paired measurement before writing this, so you do
not have to re-derive which failures are yours:

| suite | on `main` | in this lane | verdict |
|---|---|---|---|
| `plugins/leadv2/scripts/tests/test-nested-depth.sh` | **7/0 green** | **6/1 red** | **yours — a real regression** |
| `plugins/leadv2/scripts/tests/test-nested-count-fix.sh` | 6/1 red | 6/1 red | pre-existing on main, not yours |
| `tests/test-status-surface-bash32.sh` | ran on main with no FAIL lines — re-measure and state its real count | red | classify it with the paired run |

## The one real finding — `test-nested-depth.sh`
It was green on main and is red here. **The failing case is already named for you** — the lead ran it:

```
[TEST] FAIL: T1: audit log missing route.subrun.depth_exceeded reason
[TEST SUMMARY] PASS=6 FAIL=1
```

Read that before deciding anything. The assertion is **not** "general-purpose may be spawned". It
is that a nested spawn exceeding the depth limit writes `route.subrun.depth_exceeded` into the
audit log. The case evidently uses `general-purpose` as its vehicle to reach the depth check — and
round 1 made that role refuse *earlier*, for a different reason, so the depth refusal never happens
and its cause never reaches the log.

That reframes the question. Two orderings are possible and you must say which is right:

- **(a) The vehicle is incidental.** Any read-only role reaches the depth check. Switch the case to
  `Explore`; the assertion — depth-exceeded is audited — survives untouched, and the write-role
  refusal legitimately wins for `general-purpose`.
- **(b) The ordering is the defect.** A role refusal now masks a depth refusal, so one cause hides
  another and the audit log can no longer say why a spawn died. Then the fix belongs in the guard:
  evaluate depth before role, or record both. This repo has paid repeatedly for exactly this shape
  — one refusal wearing another's name.

Decide from the code, not from which is less work. State the ordering you chose and why. If (b),
keep the change minimal and touch nothing else in the guard.

**Find the case with `file:line` and read it before deciding anything.** Name it with `file:line`. Then one
of exactly two things is true, and you must say which:

1. **The test encodes the defect.** It asserts that a nested caller may spawn `general-purpose`,
   which is the very classification this row corrects. Then update that case to assert the new
   behaviour — refused, with the cause named — and say in the report that you changed an assertion
   and why it was asserting the wrong thing. Do not delete the case; convert it.
2. **The test is right and the change is too wide.** Nested sub-runs genuinely needed
   `general-purpose` for read/plan/probe work and `Explore` does not cover it. Then say what
   `Explore` cannot do that is actually needed, with an example — and stop. Do not paper over it.

The lead's decision, so you are not guessing at intent: a role carrying `tools: *` is write-capable
on **both** paths, and `Explore` remains the nested read-only route so the guard does not become an
outage. Reading (1) is expected. Reading (2) needs evidence, and if you have it, it wins.

Changing a test to match new behaviour is legitimate exactly once — when the old assertion was
wrong. It is the most dangerous edit in this repo, so it carries the heaviest burden of
explanation, and the negative control below is what keeps it honest.

## The other two suites
`test-nested-count-fix.sh` is red on main at the same 6/1 — pre-existing, **do not fix it here**
and do not let it block you. Name it in the report as pre-existing with both numbers.

`tests/test-status-surface-bash32.sh` — run it on unmodified main and in this lane, at the same
bound, and classify it the same way. If it is red in both, it is not yours. If it is green on main
and red here, it is a second regression and it gets the same treatment as `test-nested-depth.sh`.

Every number you report carries its boundary: how many checks, how many ran, how many red, at what
bound, on which platform.

## Round 1's controls stay
Keep all three. Add one for this round:

**Negative control for the converted assertion — RUN it.** Remove `general-purpose` from
`_is_write_role` and show the converted `test-nested-depth.sh` case go RED. That is what proves the
case now tests the new behaviour instead of merely having been edited until it passed. Paste the
red/green pair. An unmatched mutation anchor is a test failure, never a silent skip.

## Do not
- Do not delete an assertion, loosen a grep, or add `|| true` anywhere.
- Do not touch `test-nested-count-fix.sh` — pre-existing red, another row's problem.
- Do not revert round 1, and do not weaken `LEADV2_LEAD_WRITE_SPAWN_ALLOW=1`.
- Do not `git stash`, `git reset --hard` or `git clean` — this checkout is shared with live
  sessions in three other repos.

## Report
Append `## Round 2` to `docs/handoff/GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01/report.md`: the
failing case with `file:line`, which of the two readings is true and why, the converted assertion,
the paired numbers for all three suites with their boundary, and the new control's red/green pair.
End with `DELIVERABLE_COMPLETE`.
