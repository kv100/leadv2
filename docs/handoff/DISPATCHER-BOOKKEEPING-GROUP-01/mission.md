# DISPATCHER-BOOKKEEPING-GROUP-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**Two filed rows, one lane**, because both edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh` and
cannot run in parallel. Report on them separately; a half-fix closes one row and leaves the other
open with its cause named.

- `DISPATCHER-DOES-NOT-DECLARE-ITS-OWN-HANDOFF-DIR-01` (`701565625ee1`)
- `DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01` (`e0a3caf252c8`)

They share a theme worth stating once: **the dispatcher does things it does not record, and the
write-set gate then judges it for them.** Both failures land on innocent third-party lanes, which is
why they were expensive to diagnose — the refusal always names someone who did nothing wrong.

## Row one — the dispatcher's own scratch is an undeclared write

The dispatcher creates `docs/handoff/dispatch-<sig>/` for a lane (`developer.full.md`,
`developer.summary.md`, `mcp-cache`) and never adds that directory to the lane's `--writes`. The
write-set gate therefore sees the plugin's own scratch as an undeclared write **by that lane**, and
refuses every later dispatch board-wide.

Two candidate fixes, and they are not equivalent — choose and justify:

- the dispatcher **declares** the handoff dir it creates (keeps the artifacts in the tracked tree,
  where reviews and post-mortems can read them);
- the scratch moves **outside the tracked tree** (control plane, per `REGISTRY-MUST-LEAVE-GIT-01`),
  so there is nothing to declare.

Note before you pick: a directory in a write set serialises the whole board by prefix comparison —
this repo has already paid for that (four refusals in one evening). If you declare the dir, declare
it as narrowly as the artifacts allow.

## Row two — `--writes` does not reach the registry row

Measured 2026-09-17: **five of six** lanes dispatched that night carried `writes: None` in
`active.yaml` despite an explicit `--writes` on every command line. The one that recorded it was
dispatched **alone**; the six staggered 20s apart did not. That shape smells like a last-writer-wins
race on `active.yaml` — but *smells like* is not a diagnosis. Establish the mechanism before fixing
it: reproduce with N concurrent registrations, and show the lost write.

Consequence, for context on why this matters more than it reads: a row with no recorded write set is
refused **before any path comparison** (`leadv2-active-registry.sh:564`,
`reason=pending_resolution`), so one such row blocks every new dispatch board-wide regardless of
overlap. The data was repaired by hand under the registry's own lock that night; **the writer is
still broken**, and this row is the writer.

The gate's *scope* on an unknown write set is a separate row (`fe674d7918f3`) held by another lane.
Do not fix it here, and do not assume it will be fixed — the two fixes must each stand alone, or the
board seizes again the first time a row fails to record for some new reason.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do **not** touch `plugins/leadv2/scripts/leadv2-active-registry.sh` — another lane holds it. If
  your fix seems to require it, stop and say so in the report rather than reaching across.
- No existing refusal may become permissive for a real dispatch. This file is the dispatcher every
  lane on the board runs through.

## Controls

Two independent claims → **two** negative controls minimum, each RUN, both outputs pasted:

1. the handoff dir no longer reads as an undeclared write by the lane → revert and confirm the
   board-wide refusal returns;
2. a concurrently-dispatched lane records its `--writes` → mutate the persistence you added and
   confirm the suite goes red. A control that only exercises a *single* dispatch does not test this
   claim at all — the single case already worked.

Apply each mutation inside the function body **in the lane worktree**, never a scratch copy. Assert
the mutation target string is present before running.

## Deliverable

`docs/handoff/DISPATCHER-BOOKKEEPING-GROUP-01/report.md` — per-row verdict, the concurrency
reproduction with its numbers, the chosen fix for each with the rejected alternative named, both
controls with pasted output, and the suites that now guard `leadv2-dispatch-code.sh` for these two
behaviours with how CI selects them on a change to that file.
