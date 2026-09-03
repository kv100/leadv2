# CI-RUNS-THE-SUITES-01 — round 3: the allow-list is invisible to the gate that blocks lanes

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.** Round 2 ran for three hours on this lane and committed **nothing**.
  Commit the moment a step works, even partially.
- Suite path is `tests/run-all.sh` at the repo **ROOT**.

## Do this FIRST, before anything else in this round

**Do not run `tests/run-all.sh --scope changed` at the start.** That is what consumed round 2
entirely. This round's proof is granular and cheap; the full run comes last, if at all.

## The finding — measured by the lead 2026-09-02, this is why every lane is stuck

Round 1's allow-list is good and it is correctly populated: 15 entries, each naming a **nested**
suite that runs inside `plugins/leadv2/scripts/tests/run-core-offline.sh` — `test-review-roundcap.sh`,
`test-phase-precondition.sh`, `test-core-offline-lock-01.sh` and so on.

But the e2e gate that blocks a lane reports its failure at the level of the **wrapper**:

```
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 3 passed, 1 failed, scope=changed
```

`grep -v '^#' tests/known-red-suites.txt | grep -c 'run-core-offline'` → **0**. The wrapper is not
in the list and cannot sensibly be, because putting it there would allow-list all 83 of its nested
suites at once.

**Consequence: no allow-list entry can ever unblock a lane.** The gate only ever sees one name, and
that name is never allow-listed. Measured today: `PULSE-HOOK-IS-A-FORKED-COPY-01` and
`CI-RUNS-THE-SUITES-01` both died at this exact wall, hours apart, with correct work committed and
nothing wrong with their own changes.

## Deliver

1. **Make the allow-list reach the decision.** Two obvious shapes — pick one and justify it:
   (a) `run-core-offline.sh` applies the allow-list itself and exits 0 when every one of its
   failures is allow-listed, reporting them as skipped-known-red; or
   (b) it emits granular failing suite names upward so `run-all.sh` / the e2e gate can apply the
   list. Whichever you pick, a **non**-allow-listed nested failure must still turn the wrapper red.
   That is the property that matters; state how you preserved it.
2. **Say plainly what this changes about risk.** A gate that can be silenced by a list is only safe
   while the list is honest. Name what stops the list from being used as a mute button — round 1
   already built `known-red-guard.sh` (fails if the list grows); say whether it is sufficient here
   and what it does not cover.
3. **The 15 entries are dated and provisional.** Do NOT fix them (that is `FIFTEEN-RED-SUITES-01`).
   But do check one thing cheaply and report it: run `test-core-offline-lock-01.sh` standalone and
   paste the result. Round 1 claims it passes 3/3 standalone and only fails under concurrent load.
   Two lanes were running suites simultaneously today; if that claim holds, say so — it is the
   evidence that the flake diagnosis is right and that several of the 15 may be the same story.

## Prove it — granular, not a full run
- All failures allow-listed → wrapper exits 0 and names them as known-red. Paste it.
- One non-allow-listed failure injected → wrapper red and names that suite. Paste it.
- **Negative control:** remove the allow-list application in a mktemp FULL copy whose baseline is
  proven green → the first case must go red. Paste baseline and mutant runs. Insert the mutation
  INSIDE the function body; a top-level insert makes everything red for the wrong reason and reads
  as a pass.
- `test-core-offline-lock-01.sh` standalone — pasted.
- Only then, if time allows, `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND,
  `timeout 1800`. If you run it, paste the real tail; a placeholder token fails this round outright.
  If you do not run it, say so explicitly — an honest omission is fine here, a fabricated tail is not.

## Still owed from round 2 (not yet done — nothing was committed)
The cost work: macOS confined to what genuinely needs Apple's `/bin/bash` 3.2; a `concurrency`
block with `cancel-in-progress: true` on the PR job; timeouts derived from a measurement; a
per-run and per-month minutes paragraph for a public **and** a private repo, because this workflow
is a template adopters copy into private repos where macOS bills at 10×. Do this AFTER item 1 — item
1 is what unblocks every other lane in the repo.

## Constraints
LANE_WRITES: `.github/workflows/`, `tests/`, `plugins/leadv2/scripts/tests/run-core-offline.sh`,
and this task's handoff dir. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.

## Done when
An all-allow-listed run exits 0 with the names reported; a non-allow-listed failure still turns it
red; the negative control is red against a green baseline; the standalone lock-suite result is
pasted; and the round-2 cost items are either done or explicitly listed as still owed.
