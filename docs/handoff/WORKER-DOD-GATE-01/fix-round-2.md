# WORKER-DOD-GATE-01 — fix-round 2 (review FAIL: critical=1, high=3, opus arm)

## READ THIS FIRST — the rules that killed six rounds today
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** No Monitor, no `run_in_background`. Foreground
  with `timeout 900`.
- Nested agents are allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`, and
  you commit the child's output yourself.
- **Commit after every step.**

**Lane:** worktree-WORKER-DOD-GATE-01 (resume; merge `main` FIRST).

## The gate is currently WORSE than no gate — that is the frame for this round
Two of the four findings say the same thing from different ends: the gate hard-REFUSES rounds against a
contract that no worker has ever been given, using evidence no worker can ever produce. A gate that
cannot be satisfied does not raise quality; it converts good rounds into refusals and teaches everyone
to route around it. Fix that first, and do not add a single new check in this round.

## Findings (opus reviewer, live-probed, on the committed fix-round-1 diff)

1. **[Critical] `lib/leadv2-dod-gate.sh:277`** — check (b)'s mutation sub-check binds `diff_hash` to
   `review.diff`, which is produced only AFTER the worker exits. No worker can ever satisfy it, so any
   brief carrying a paste+mutation line is refused unconditionally.
2. **[High] `lib/leadv2-dod-gate.sh:455`** — the gate emits its cause ONLY by `cat`-ing `out_md`, and
   neither call site `mkdir -p`s the output dir. So `rc=1` with empty stdout becomes
   `review-gate.md reason=dod_unknown` — the same muteness as REVIEW-GATE-IS-MUTE-01, produced by our
   own new code.
3. **[High] `lib/leadv2-dod-gate.sh:44`** — fix-round-1 finding 1 is only HALF fixed. An empty-file
   creation, a 100% rename, and a mode-only change of a runtime-state path emit neither `--- a/` nor
   `+++ b/` lines, so they still pass check (d) with rc=0. Live-probed by the reviewer.
4. **[High] `leadv2-helpers.sh:77`** — `_LEADV2_DOD_GATE_CONTRACT_MISSION` has **zero consumers
   repo-wide**. The comment claiming it is consumed is false. So the contract the gate enforces is never
   injected into any worker's prompt.

## Do — one commit each
1. `## Review round 2 findings` in report.md: REAL/REFUTED per row with the evidence command. All four
   are live-probed by the reviewer; if you believe one is REFUTED, refute it with a run, not with prose.
2. **Finding 4 first** (it is the reason the others matter): either wire
   `_LEADV2_DOD_GATE_CONTRACT_MISSION` into the dispatcher so every worker actually receives the
   contract — one place, so it cannot drift — or delete the variable and the gate's dependence on it.
   Paste the contract text as it appears in a real dispatched worker's prompt, or state plainly that you
   removed it. Fix the false comment either way.
3. **Finding 1:** the mutation evidence must be something the worker CAN produce inside its own round —
   bind the hash to the worker's own committed diff (`git diff <merge-base> HEAD`), not to an artifact
   created after it exits. If no such artifact exists at gate time, the check must SKIP with a named
   reason, never refuse. Suite: a round with a legitimate mutation artifact passes; a round with a
   hand-written one-liner still fails.
4. **Finding 2:** `mkdir -p` the out dir at both call sites AND make the gate print its cause on stderr
   as well, so an empty `out_md` can never become `dod_unknown`. Suite case: force the out dir to be
   unwritable → the gate must still name its cause.
5. **Finding 3:** parse the diff by PATH, not by marker lines — cover empty-file creation, 100% rename
   (`rename from`/`rename to`), and mode-only changes of runtime-state paths. Suite: one case per shape.
6. Negative control for every case above: revert the fix in a mktemp FULL copy of the tree (including
   `lib/`) whose baseline is proven green → the case must go red. Paste baseline and mutant runs. Insert
   the mutation INSIDE the function body — a top-level insert makes everything red for the wrong reason
   and reads as a pass.
7. `tests/run-all.sh --scope changed` in the FOREGROUND with `timeout 900`; paste the tail. If it stalls,
   check `/tmp/leadv2-core-offline-*` for a lock whose holder pid is dead (`kill -0`), clear it, say so,
   re-run.
8. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main`
merged. **Do not add any new check this round.**

## Done when
All four findings REAL→fixed with pasted runtime output; the contract is either provably delivered to a
worker or gone; a legitimate round can now PASS the gate (show one); every new case carries a negative
control that goes red; run-all tail present.
