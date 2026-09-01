# CACHE-TRUTH-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-cache-truth.sh,plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/claude-subsession.sh,plugins/leadv2/scripts/tests/test-cache-truth.sh,tests/run-all.sh,docs/handoff/CACHE-TRUTH-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `f6b25c2`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Commit at the end.

## Review verdict on round 1 (reviewer glm) — FAIL, high=2
1. **`leadv2-cache-truth.sh:119`** — no de-duplication by `message.id`: a stream-json file carries
   the same assistant message several times (streaming deltas / final), so requests and token
   totals are inflated 1.81× (176 events vs 95 unique ids; 27.24M cache_read vs 15.07M on
   dispatch-c293c1d5). Every absolute number in the report table is wrong by that factor.
2. **`report.md:60`** — "freepool: cache keys PRESENT but always 0 across 137 requests, verified by
   direct JSON inspection" is false: 1 of 137 requests carries the keys (value 0), 136 do not
   report them at all. `saw_cache_key` is global per run, so a mixed stream is classified as a
   real 0.0000 instead of `unreported` — the opposite of the tool's own absent-vs-zero rule.

## Do
1. Count usage ONCE per unique `message.id` (take the last event for that id). Add a fixture stream
   with duplicated ids to `test-cache-truth.sh`; assert the totals equal the de-duplicated sum.
2. Classify per REQUEST, not per run: `reported` (keys present) vs `unreported` (absent); the run
   row shows `hit_ratio` only over reported requests and a `reported=N/M` column. A run with
   0 reported requests prints `unreported`, never `0.0000`. Fixture for the mixed case (1 of 3
   reported → `reported=1/3`).
3. Re-run the tool over today's runs and REPLACE the table in report.md with the corrected
   numbers; state the per-arm conclusion again from the new numbers (Claude native ratio; GLM /
   freepool / kimi reported-vs-unreported). If GLM never reports cache fields, say so and check
   the Z.AI docs / one raw HTTP response for a cache field name (paste the raw `usage` object of
   one GLM response from the stream) — that decides whether "GLM has no cache" or "our parser
   misses the field".
4. Mutation negative controls, RUN and paste red: (a) remove the id de-dup → fixture (1) red;
   (b) make `saw_cache_key` global again → fixture (2) red. Revert both.
5. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-cache-truth.sh`
   → paste FALSIFIABLE. "## Round 2 evidence" in report.md; commit.
