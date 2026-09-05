# GUARD-CENSUS-IS-WRONG-01 — fix-round 4 (one High, mechanical)

**Class:** Light fix-round. **Lane:** worktree-GUARD-CENSUS-IS-WRONG-01 (resume; merge `main` first).

## The finding (codex R3 review, diff d821e95a)
`docs/handoff/GUARD-CENSUS-IS-WRONG-01/report.md:51` — the report claims the live founder-facing
census was regenerated, but the shipped census artifact is still PRE-fix: it keeps the 13 stale
missing/not-wired DEFAULT cells and the old false `always` values. R3 fixed the script, not the artifact.

## Do
1. Find the founder-facing census artifact the script writes (the file the brief calls the delete
   list; check `leadv2-guard-census.sh` for its output path and `git log -- <path>` on the lane).
2. Regenerate it on the lane tip with the FIXED script, against the live tree. Commit the regenerated
   artifact.
3. In `report.md` replace the claim at :51 with evidence: the exact regenerate command, then
   `git diff --stat <prev>..HEAD -- <artifact>` and a before/after count of (a) rows whose DEFAULT
   changed, (b) rows still printing `always` for a flag-gated guard — (b) must be 0, shown by a grep
   whose output is pasted.
4. Re-run the suite and `leadv2-suite-falsifiable.sh` on it; paste both verdict lines.

## Constraints
- Only the artifact, `report.md`, and (if needed) the script's output-path handling. No other scope.
- Do not commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`. Commit on the lane, tree clean.

## Done when
- artifact regenerated and committed; report :51 replaced by the pasted evidence; (b) = 0

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b5e35200" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.