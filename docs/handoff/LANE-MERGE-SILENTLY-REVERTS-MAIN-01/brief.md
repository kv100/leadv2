# LANE-MERGE-SILENTLY-REVERTS-MAIN-01

A lane cut before some other lane merged will, on its own merge, silently delete whatever landed on
`main` in between. Nothing warns. It happened **five times on 2026-09-03** and every one was caught
only because the lead ran `git diff --stat main..HEAD` by hand before merging.

## Measured, 2026-09-03

| lane | what its merge would have deleted |
|---|---|
| `SAFETY-PIN-SECOND-DOOR-01` | 48 lines of the session journal `SINCE-0450.md` |
| `HEAVY-TIER-VS-SAFETY-OPUS-01` | the same journal again |
| `WORKER-OUTLIVES-…` (round 2) | 304 lines of the architect's `CONTROL-PLANE-HAS-NO-OWNER-01` brief + 17 of `scheduled-decisions.md` |
| `E2E-TIMEOUT-…` and `LEAD-IS-OPUS-…` | the same 304-line brief, both of them |
| `WORKER-OUTLIVES-…` (round 3) | **221 lines of `test-e2e-timeout-classification.sh`** and 64 of `test-fable-think-tier.sh` — two lanes that had merged an hour earlier |

The last one is the shape that matters: it would have deleted a *production test suite* another lane
had just landed, and the merge itself is clean — no conflict, no warning, exit 0.

This is not a git bug. The lane branch legitimately does not contain those lines, so `main..HEAD`
records them as deletions. What is missing is anyone checking.

## What this task must deliver

1. **A refusal, not a warning.** The merge path (`leadv2-deploy-merge.sh`, and whatever else lands a
   lane) must refuse when the lane's diff against `main` deletes or reverts a file the lane never
   edited. Name the file:line. A warning a tired human can skip is not the deliverable.
2. **Say what to do about it in the refusal**, in one line: merge `main` into the lane, then retry.
   That is what worked all five times.
3. **Distinguish an intended deletion from an accidental one.** A lane that genuinely deletes a file
   as part of its work must still land. Propose the discriminator and argue it — the obvious
   candidate is "did this lane's own commits touch that path", but check it against the five cases
   above before trusting it.
4. **A negative control**: a fixture where lane B branches, lane A lands a file, lane B merges — show
   the guard red (refuses); merge `main` into B, show green. And the reverse: a lane that
   deliberately deletes its own file still lands.
5. Green on macOS and in a Linux container, exit codes pasted. Register the suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
6. Commit in this lane before you finish.

Related: `CONTROL-PLANE-HAS-NO-OWNER-01` — the same absence of an owner, one layer up.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, and solving it by telling
humans to check — the whole finding is that checking by hand worked five times only because someone
happened to look.
