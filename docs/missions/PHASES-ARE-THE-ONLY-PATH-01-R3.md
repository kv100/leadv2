# PHASES-ARE-THE-ONLY-PATH-01 — fix round 3 (plugin repo ~/Projects/leadv2)

Round 2 (`e55c0ef` + `5ba7620` in worktree `d4d014e1`) **did not fix any of the three blocking
findings.** It rebased onto main and adjusted unrelated status-surface test expectations. The lead
verified each finding directly in the round-2 tree; do not claim they are fixed without showing the
code.

**Scope of this round: exactly F1, F2, F3. Nothing else. Do not touch tests unrelated to them, do
not refactor, do not rebase again.**

## F1 — still broken, verbatim in the round-2 tree
`leadv2-phase-record.sh`, `_verify_artifact`, case `review`:

```
local ledger_file="${ledger_dir}/${slug}.jsonl"
[[ -s "$ledger_file" ]] && return 0
```

That is repo-wide file non-emptiness. Once any review has ever run in this repo, every future
lane's review phase passes. Required: parse the ledger and require a row whose **diff-hash equals
this lane's current diff-hash** and whose verdict is PASS or PASS_WITH_NITS. No matching row ⇒
phase not proven. The lane's diff-hash must be computed the same way `record-review` computes it —
find that code and reuse it, do not invent a second hashing scheme.

## F2 — still broken for five phases
Same function, cases `build` and `test|deploy|live_verify|e2e`:

```
[[ -n "$artifact" && -f "$artifact" ]] && return 0
```

A bare existence check. `touch fake` satisfies it. `artifact_sha256` is written at :433 and read at
:565, but **that read is not on this path** — these five cases never compare it.

Required, per design §2:
- every phase: re-hash the artifact at assert time and compare with the recorded
  `artifact_sha256`; mismatch or missing file ⇒ fail. This alone closes the overwrite-after-record
  hole.
- `build` → the lane diff vs its own base is non-empty (the comment at the call site says this is
  checked "at the call site" — verify that claim or implement it here).
- `deploy` → the recorded commit is an ancestor of `origin/main`.
- `close` → keep the `phase8-passed.flag` check, it is already real.
- `test` / `live_verify` / `e2e` → if a real assertion is not available for a phase, say so
  explicitly in your report and record that phase as unprovable rather than passing it on existence.

## F3 — still broken, and this is the one that hides the other two
`test-phase-precondition.sh` contains **zero** occurrences of `REQUIRE_PHASES` and **zero** of
`cmd_resolve` (verified by grep in the round-2 tree). 22 tests pass and none of them touch the
guard. The warn / enforce / disabled behaviour has no coverage at all.

Required — test `cmd_resolve` end to end:
- `LEADV2_REQUIRE_PHASES` unset → journals `phase_precondition_warn` naming the missing phases AND
  proceeds to spawn.
- `=1` → the same call is REFUSED, distinct exit code, no worker spawned.
- `=0` → no warn line journalled; behaviour identical to pre-C4.
- `--phase-waiver review=x` refused in every class.
- forged review: a ledger row for a DIFFERENT diff-hash ⇒ review phase NOT proven (F1 regression).
- forged artifact: `touch fake`, record it, then overwrite it with garbage ⇒ phase NOT proven
  (F2 regression).

Every one of these must FAIL against commit `5ba7620` and pass after your fix. **Your report must
show both runs.** Three times today a green suite turned out not to touch the thing it named; a
test that passes in both directions is treated as absent.

## Base
Worktree `d4d014e1`, on top of `b29f9b2`. Already rebased — do NOT rebase again. Round 3 fixed R9 (setsid) and the two non-blocking items and committed them as b29f9b2; it did NOT touch F1/F2/F3, which are the entire scope of this round.

## Write set
`leadv2-phase-record.sh`, `leadv2-dispatch-code.sh`, `plugins/leadv2/scripts/tests/test-phase-precondition.sh`.
Nothing else.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of BOTH test runs (against `5ba7620`
and after the fix). If you cannot make a phase's proof real, return BLOCKED naming that phase —
do not leave an existence check behind and call it done.
