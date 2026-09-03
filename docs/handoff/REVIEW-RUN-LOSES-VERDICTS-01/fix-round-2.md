# REVIEW-RUN-LOSES-VERDICTS-01 — round 2: the findings counter belongs to nobody

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-RUN-LOSES-VERDICTS-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-body-recovery.sh,tests/run-all.sh,docs/handoff/REVIEW-RUN-LOSES-VERDICTS-01/

**Round 1 is merged into main as `7927b0f` and stays — do not redo it.** I verified it myself:
disabling the store lookup (`store_out=""; return 1`) turns the suite red with
`FAIL: S1: unexpected review_body_lost -- the verdict was recoverable`; restored, 26/0; source
diff clean.

## [Critical] the printed counter is derived from no source at all

Fresh, from the V5 session's third round, observed live:

```
gate printed:            high=5
authoritative codex body: 2 high
review-findings.json:    {"findings": []}
hack detector:           empty
```

Three sources, three different numbers, and the one shown to the human matches none of them.
That is worse than losing the body: a reader who trusts `high=5` goes looking for three
findings that do not exist. The V5 lead nearly did.

**Fix, as an invariant rather than a patch:** the counter printed in the gate line must be
computed from the same `findings` array that is written to `review-findings.json`. One array,
one count, no independent tally anywhere in the file.

And make the impossible state explicit: an empty `findings` array together with a non-zero
count is not a `fail: high=N` — it is `blocked: findings_lost`. A blocked gate is honest; a
number nobody can match is the lying-green disease wearing a red hat.

Audit the file for every place a severity count is produced or printed, and say in `report.md`
how many independent tallies you found and collapsed.

## Acceptance

Extend `test-review-body-recovery.sh` — same fixture discipline, never a real codex job:

1. N findings in the array ⇒ the gate line prints exactly N, for at least two distinct N;
2. empty array + a non-zero count reachable from any path ⇒ `blocked: findings_lost`, never
   `fail`;
3. body recovered from the store ⇒ the count comes from the recovered array, not from the
   housekeeping body;
4. the count in the gate line and the length of `findings` in `review-findings.json` agree in
   every case above — assert on both artifacts, not on one.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Do not weaken round 1: a mutation disabling the store lookup must still turn the suite red.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The gate's number and `review-findings.json` can never disagree, an empty array with a non-zero
count blocks instead of failing, and a mutation reintroducing an independent tally turns the
suite red with the exit code following.
