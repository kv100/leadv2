# CI-RUNS-THE-SUITES-01 — fix round 1: the workflow must not be able to burn a quota

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo ROOT.

The workflow you wrote is good work — the allow-list, its guard, and `ci-gate.sh` all stand. This
round constrains **when and where it runs**. Founder raised it directly: a past project had
workflows that failed, fired too often, and crossed the free quota. That must be structurally
impossible here, not merely unlikely.

## The measured situation

`kv100/leadv2` is **PUBLIC** (`gh repo view --json visibility` → `PUBLIC`), so standard-runner
minutes are free and the billing fear does not apply *to this repo today*. Three real risks remain,
and one of them is about everyone who adopts this plugin.

1. **`runs-on: macos-latest`, twice.** Your own comment justifies it: `test-status-surface-bash32.sh`
   needs Apple's frozen `/bin/bash` 3.2, meaningless on `ubuntu-latest`. Accepted — but macOS is
   **10× the minute multiplier on private repos**, and public repos are capped at **5 concurrent
   macOS jobs**. This plugin's CI file is a template adopters copy into repos that are private.
   `120` timeout-minutes × 10 = 1,200 billable minutes for ONE nightly run, against a 2,000/month
   free allowance. Two nightlies would exhaust an adopter's month.
2. **No `concurrency:` group.** Every push to a PR branch starts a fresh run while the superseded
   one keeps going. With several lanes pushing, runs pile onto the 5-macOS-slot limit and queue.
3. **`pull_request:` with no filter** fires on `opened`, `synchronize` and `reopened`, including for
   changes that touch no code the suites cover (docs-only commits).

## Deliver

1. **Split the runner by need, do not pay macOS for everything.** Put the bash-3.2 check — and only
   what genuinely needs Apple's `/bin/bash` — in a small macOS job. Everything else runs on
   `ubuntu-latest`. State in the report how many suites actually require macOS; if it turns out to
   be one, say so plainly, because then the 10× applies to one short job instead of the whole run.
2. **A `concurrency` block on both jobs**, keyed by workflow + ref, with
   `cancel-in-progress: true` for the PR/push job and `false` for the nightly. A superseded run must
   die, not finish.
3. **A `paths-ignore` (or `paths`) filter** so a docs-only change does not spend a runner. Derive the
   list from what `--scope changed` can actually select — do not guess. If the mapping makes a filter
   unsafe (a docs change that CAN break a suite), say so and skip this item with the reason; a wrong
   filter that hides a real failure is worse than an extra run.
4. **Timeouts sized from the measurement, not from a round number.** You were asked for the measured
   wall time of `--scope changed`; put that number in the report and derive both timeouts from it.
   `120` for the nightly needs justification or reduction.
5. **The nightly must be cheap to disable.** One line, named in the report — for an adopter whose
   quota is tight, or for us if the macOS queue backs up.
6. **A cost paragraph in the report, in minutes:** per-run billable minutes for a public repo and
   for a private one, per PR and per month at a realistic push rate. Numbers, not adjectives. This
   is the paragraph the founder will read.

## Prove it
- Push twice in quick succession on a scratch branch → the first run is **cancelled**, not
  completed. Paste both run states.
- A docs-only commit → no runner spends time (or the report explains why the filter was skipped).
- The broken-suite detection from round 1 still works after the split — re-run that proof; a runner
  change that silently stops detecting failures is the one regression that matters here.
- `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND, `timeout 1800`. Paste the real
  tail.

## Out of scope
Fixing the 37 known-red suites (`FIFTEEN-RED-SUITES-01`). Changing what the suites assert.

## Constraints
LANE_WRITES: `.github/workflows/`, `tests/`, this task's handoff dir. Never commit `docs/leadv2/`,
`LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`, `critic.*`. Tree clean, `main` merged.

## Done when
Superseded runs are proven to cancel; macOS is confined to what needs it with the suite count named;
timeouts are derived from a pasted measurement; the report carries the per-run and per-month minute
figures for both public and private repos; round 1's broken-suite proof still passes.
