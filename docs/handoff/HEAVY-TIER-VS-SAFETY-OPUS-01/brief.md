# HEAVY-TIER-VS-SAFETY-OPUS-01

`main` currently carries an unresolved contradiction about which model takes a high-risk session,
introduced by the `FABLE-THINK-TIER-01` merge (`06ed55fb`) and caught by CI, not by the lane.

## Measured

CI run `33707302403` (ubuntu-latest, `06ed55fb`): `passed=56 failed=28`, and **13** suites print
`[NOT-KNOWN-RED]` where the previous run on `815627a7` had 12. The one that appeared is
`core:provider/model router` -> `plugins/leadv2/scripts/tests/test-session-route.sh`.

**It is not a platform bug.** The lead ran the suite standalone on macOS on `main`:
`PASS=6 FAIL=2`. Both platforms agree it is red. The two failures:

    Heavy -> Claude Opus                  missing 'model=opus' in: provider=claude model=fable
    high-risk tag blocks explicit Codex   missing 'model=opus' in: provider=claude model=fable

## The contradiction

The merge is deliberate and documented — `git diff 815627a7..06ed55fb -- plugins/leadv2/scripts/leadv2-session-route.sh`
replaces `CLAUDE_HEAVY_MODEL="opus"` with a resolver call defaulting to `fable`, and states in a
comment that a config `heavy: model: opus` is "dead by design". The lane changed live routing and
did **not** update the suite that asserts the old rule. So one of these two is now wrong on `main`:

- **(A) the suite is stale doctrine.** `PLANNER-MODELS-DECISION-01` does pin Heavy *planning* to
  Fable, so "Heavy -> fable" may simply be correct now and the assertion should be updated.
- **(B) the suite is right about the safety path specifically.** The repo's standing rules say
  arch/design/safety verdicts go to Opus always, and the leadv2 routing table gives the critic
  "Opus (Heavy or safety verdict)". The second failing assertion is literally the **high-risk tag**
  path — that is a safety route, not a planning route.

These are not the same question and must not be answered with one edit. It is entirely possible
that (A) is right for Heavy-as-a-think-tier AND (B) is right for the high-risk/safety branch — in
which case the fix is to split the two paths, not to pick a winner.

## Definition of done

1. State which of (A)/(B) holds for EACH of the two failing assertions, citing the standing rule
   you relied on by file and line — not by memory.
2. Fix whichever side is actually wrong. If the routing is wrong, fix the routing; if the
   assertion is stale, fix the assertion and say in the commit message which decision record makes
   it stale. Do not "fix" a red test by deleting or weakening the assertion.
3. `test-session-route.sh` green, exit code pasted, on macOS **and** proven on Linux (a container
   run is acceptable — `TWELVE-LINUX-ONLY-SUITES-01` demonstrated the pattern).
4. A negative control: mutate the routing back to the losing side, show the suite goes red, revert,
   show green.
5. If the answer is (B) or a split, check whether any OTHER caller of the Heavy tier now sends a
   safety decision to a non-Opus model. One instance of a routing mistake is a bug; two is a
   pattern and the census belongs in the report.
6. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, and reverting `FABLE-THINK-TIER-01` wholesale —
the think-tier work was reviewed and landed on purpose; this task is about the boundary it drew,
not about undoing it.
