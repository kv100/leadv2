# PULSE-HOOK-IS-A-FORKED-COPY-01 — round 2: finish the persona-engine half

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo ROOT.

## What round 1 delivered — keep it, do not redo it

Two commits on this lane already carry the canonical half: `leadv2-pulse-json.sh` rewritten (+66)
so dead registry rows are skipped and the live control plane is read, plus a new 176-line suite
`plugins/leadv2/scripts/tests/test-leadv2-pulse-json.sh`. Self-check was GREEN (`bash -n` clean on
both). **Do not rewrite that work.** Read it first and build on it.

## Why round 1 did not close, and what it means for you

The e2e gate reported `status: fail / reason: e2e_regression / scope: whole_tree_fallback` with one
blocking entry: `plugins/leadv2/scripts/tests/run-core-offline.sh`.

**That failure is not yours.** It is a pre-existing red suite, already catalogued by the parallel
CI lane in `tests/known-red-suites.txt` with this note: red inside the full 83-suite run at the
baseline commit, passes 3/3 standalone, "looks like a lock-contention timing flake under concurrent
machine load, not a logic bug". Several suite runs were executing concurrently on this machine at
that moment.

So: **do not chase it, and do not "fix" it here.** Instead —

1. Run it standalone and paste the result. If it passes standalone while failing in the full run,
   say so plainly in the report with both outputs; that is the evidence `FIFTEEN-RED-SUITES-01`
   needs and it costs you one command.
2. If it fails standalone too, then something changed — stop and report that, because it would mean
   the flake diagnosis is wrong.

## Deliver — the half that is still missing

1. **Diff the fork against canonical before touching it.**
   `diff persona-engine/.claude/hooks/leadv2-pulse-json.sh` (a real copy dated Jul 28) against
   `plugins/leadv2/hooks/leadv2-pulse-json.sh` at the commit BEFORE your round-1 change. List every
   difference in the report. **If the fork carries a fix canonical never received, port that fix up
   into canonical in this round.** Deleting the copy without reading it deletes the fix with it.
2. **Remove the fork.** Delete `persona-engine/.claude/hooks/leadv2-pulse-json.sh` and its wiring at
   `persona-engine/.claude/settings.json:336`, or replace the copy with a symlink to canonical.
   Choose, and justify the choice in one paragraph. Before removing the writer, check whether
   anything reads the `pulse.json` it produces — name what you checked.
3. **A guard against the next fork.** A check that fails while any real (non-symlink) copy of a
   plugin-owned hook exists under a consumer repo's `.claude/hooks/`. Small and mechanical.
4. **The report.** Which option you chose for the fork and why; the fork-vs-canonical diff; whether
   anything read the pulse file; the standalone result of `run-core-offline.sh`.

## Prove it
- The regression case from round 1 still passes (dead-rows-only fixture → no task id written).
- `run-core-offline.sh` standalone — pasted, pass or fail.
- The anti-fork guard: create a scratch real copy → guard fails; remove it → guard passes. Paste both.
- `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND, `timeout 1800`. Paste the real
  tail. A placeholder where run output belongs fails this round outright.

## Out of scope
Fixing `run-core-offline.sh` or any other known-red suite. Teaching the e2e gate to read the
allow-list (that is the CI lane's territory). The delegation-nudge volume.

## Constraints
LANE_WRITES only, plus the two persona-engine files named in item 2. Never commit `docs/leadv2/`,
`LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`, `critic.*`. Tree clean, `main`
merged.

## Done when
The fork is gone with the choice justified; any fork-only fix is carried up into canonical; the
anti-fork guard is proven both ways; round 1's regression case still passes; the standalone result
of the blocking suite is in the report.
