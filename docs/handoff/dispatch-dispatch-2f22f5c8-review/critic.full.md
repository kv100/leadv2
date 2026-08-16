# Verification — placement-test ordering inversion

## Finding under test
High / correctness — phases.md:471 summary inverts the canonical test order.

## Evidence

Diff hunk (plugins/leadv2/docs/phases.md, §Spawn-hygiene, after line 468):

```
**Placement before spawn — three tests, first match wins** (canonical rule + edge cases: `docs/work-placement.md`):
1. Diff test — work ends in a committed diff or a citable deliverable file? -> dispatch lane.
2. Only-this-session-knows test — answer requires a decision/text from this conversation, not on disk? -> fork.
3. Otherwise — bounded question answerable from repo/prod/logs alone? -> fresh agent (...).
```

Canonical source (`.claude/worktrees/e7d05157/plugins/leadv2/docs/work-placement.md`):

- L3-5: "One **precondition asked first**, then **one yes/no branch test** — the precondition gates entry to the branch test; it is not a branch and cannot be routed around."
- L16: "## Step 0 — precondition (asked first, always; not a branch)"
- L22-33: on yes, must materialize (default) or fork BEFORE dispatching anywhere; "Never dispatch context-dependent work without discharging this step — that is the exact failure this rule exists to prevent."
- L35: "## The branch test (after Step 0; exactly one outcome matches)"

## Analysis

The canonical structure is one precondition plus one binary branch, not three peer tests. The summary demotes the precondition to branch #2 and promotes the branch test's diff clause to #1, then declares "first match wins". Under that reading, work that (a) depends on a decision living only in this session and (b) will end in a committed diff matches test 1 and routes straight to a lane — Step 0 is never asked, so the decision is neither materialized into `context.yaml decisions[]` nor forked. That is precisely the failure work-placement.md L31-32 exists to prevent.

The pointer back to `docs/work-placement.md` does not cure it: the summary does not present itself as lossy, it asserts a concrete checkable ordering that contradicts the canonical one. A lead reading only §Spawn-hygiene — which is where the spawn-time rule is expected to live — gets the wrong routing.

The same wording appears in the `commands/leadv2.md` hunk (post-patch lines ~19-21): "(diff test → lane; only-this-session-knows test → fork; otherwise → fresh agent)" — same inversion, same reading.

Refutation attempted and failed: nothing elsewhere in the diff restores Step 0's precedence at either call site.

## Required fix
Reorder to precondition-then-branch in both places, e.g.:

> Step 0 (always first, not a branch): does this need something only this conversation has? → materialize into mission/`context.yaml` (default), or fork when the dependency is the whole reasoning trail. Then the branch test: durable artifact (diff or citable file)? → lane; else → fresh agent.

Drop the "three tests, first match wins" framing.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
