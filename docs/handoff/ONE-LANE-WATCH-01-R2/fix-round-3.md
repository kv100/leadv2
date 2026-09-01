# ONE-LANE-WATCH-01-R2 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01-R2`
LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-watch-v2.sh,plugins/leadv2/scripts/tests/test-lane-watch-v2.sh,docs/handoff/ONE-LANE-WATCH-01-R2/
Continue from the existing commits on this branch (`git log main..HEAD`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 2 (reviewer glm, `docs/handoff/ONE-LANE-WATCH-01-R2/review-findings.json`)
status=fail critical=1 high=3. Read `review-glm.md` in full before touching anything.

- **[Critical] `leadv2-lane-watch-v2.sh:143`** — `lane_dirs` drops `claude-runs` (and `kimi-runs`) from
  the arm enumeration, so Claude-arm lanes lose both the dispatch grace and provider-output suppression.
  The whole point of v2 was "provider-agnostic"; enumerate every `~/.claude/cache/*-runs` family plus
  codex `jobs/` from ONE list that the tests also read.
- **[High] `:193`** — `_lw_provider_output_age_min` ignores codex `jobs/` (where real output lives) and
  counts runner bookkeeping (`broker.json`, `state.json`) as worker output. Only worker-written files
  count (stream / journal / progress / the job's own output), never the runner's bookkeeping.
- **[High] `:164`** — the dispatch-age comment claims journal appends happen "whether or not the worker
  produces", contradicting the provider-output rule two functions below. Make the code true and the
  comment match it; one rule, stated once.
- **[High] `:166`** — "broker rotation every ~30 min" is an untagged claim driving the birth-based
  redesign and the live tree contradicts it (broker.json unmodified). Either measure it (paste the
  mtimes) or remove the claim and the code that depends on it.

## Do
1. Fix all four; each fix gets a case in `test-lane-watch-v2.sh` that is red before and green after
   (paste both runs in report.md). Case for the Critical: a fixture `claude-runs/<id>` lane inside
   grace must NOT be reported stalled.
2. Mutation negative control, RUN and paste red: remove `claude-runs` from the enumeration list again →
   the new case red.
3. Re-run the whole suite; append "## Round 3 evidence" to report.md; commit.
