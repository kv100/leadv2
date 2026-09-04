---
verdict: APPROVE
next_action: continue
---

# WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01 — lead verification

Verified by running it, not from the worker's report. 2026-09-04.
`next_action: continue` = ready to merge; merging is the other lead's call.

## Result

Nine cases, **ten consecutive runs, `rc=0` every time**: `9 passed, 0 failed`.
`git diff --name-only main...HEAD` = `leadv2-lane-worktree.sh`, the suite, and this handoff dir.
Round 2 touched **only** the suite — the worker did not "improve" the product it was not asked to.

## Controls, under the strict criterion (every earlier assertion green, only the named one red)

| control | mutation | red lines | verdict |
|---|---|---|---|
| fresh-branch site | remove `degrade_frozen_registry_copy` call, line 288 | `2` + `2b` | named site only; case 4 stays green |
| attach-to-existing site | remove the call, line 295 | `4` — **exactly one** | clean |
| resolver-failure sentinel | no-op the sentinel write, line 341 | `2d` + `4b` — **and only those** | clean |

`restored_rc=0` after every one; every mutated line was read back before its run.

The third control's red line is the good kind — it names the surviving content, not just an absence:

```
FAIL: 2d: … frozen copy survived unneutralized: lanes: {}
FAIL: 4b: … frozen copy survived unneutralized: lanes: {}
mutated_rc=1   7 passed, 2 failed
```

**Two reds here is correct, not a shared-cause artifact.** One product line serves both creation
sites and each site has its own case. A single red would have meant one site never reaches the
sentinel at all.

## A control that did not bite, and why that was my error rather than a gap

My first attempt at the sentinel control mutated **line 350** — the sentinel for a failed `ln -s` —
and the suite stayed 9/0 green. That reads exactly like "cases 2d/4b pass for free". It is not:
there are **two** sentinel writes in `degrade_frozen_registry_copy`, line 341 for a failed
*resolver* and line 350 for a failed *symlink*, and the fixture forces the resolver failure. I had
anchored on a site the fixture never reaches.

Had I reported that run, a healthy branch would have gone back for a needless round — the second
time today that "the mutant did not bite" turned out to mean "the anchor was wrong", not "the branch
is naked". A mutant that fails to bite is a claim about the anchor until proven otherwise.

## Remaining gap, named and not fixed

The **symlink-failure** sentinel (line 350) is still unasserted: no case forces `ln -s` to fail.
Its consequence is identical to the resolver-failure branch and the code shape is the same, so this
is a smaller hole than the one round 2 closed — but it is a hole, and it should not be discovered
later as a surprise. Forcing it needs an unwritable parent directory in the fixture. Left for the
merge owner to schedule rather than spending a third round on it now.
