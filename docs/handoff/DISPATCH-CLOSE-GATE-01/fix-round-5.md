# DISPATCH-CLOSE-GATE-01 — round 5: the round-4 suite is red at HEAD, and the C1 fix was partial

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,plugins/leadv2/scripts/tests/fixtures/,plugins/leadv2/scripts/tests/test-lib-source-guarded.sh,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

Full report: `docs/handoff/DISPATCH-CLOSE-GATE-01/review-r4.md`. HEAD is `bfec45a`.

**C2 and C4 pass — leave them alone.** The gate reads real worker claims, and
`LEADV2_REQUIRE_MISSION_WRITESET` defaults to `0` with the 3/5 precision stated plainly. Those two
are done.

## [Critical] the suite you shipped is RED at HEAD with no mutation applied

`test-mission-writeset.sh` at `bfec45a` reports `FAIL: C1: consumer symlink startup failed`,
`SUMMARY: pass=16 fail=1`. A round that commits a failing suite has not finished; nothing
downstream of it can be trusted, and this is the fifth time today a worker committed a suite it had
not run.

Run every suite in your write set before you commit, and paste the runs.

## [Critical] the C1 fix covered two `source` lines and missed two more in the same file

Round 4 guarded `lib/leadv2-mission-writeset.sh` and `lib/leadv2-red-proof.sh` correctly — I
confirmed the dispatcher starts from `persona-engine` with rc=0. But
`leadv2-dispatch-code.sh:449` and `:455` still source `leadv2-lane-child-suffixes.sh` and
`leadv2-portable-lock.sh` **unguarded**, with no canonical fallback. Your own new test catches
exactly this and is why the suite is red.

**This is now the third lane today to ship an unguarded `source` of a plugin lib.** So the fix is
not another one-off. Do all three of these:

1. Guard `:449` and `:455` the same way `:462-467` are guarded: resolve next to the script, fall
   back to `${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/…`, and
   wrap the `source` in `[[ -f … ]] &&`.
2. **Census every `source` of a `lib/` file across `plugins/leadv2/scripts/` and
   `plugins/leadv2/hooks/`.** List each one in `report.md` with its file:line and whether it is
   guarded. Fix every unguarded one that lies in this lane's write set; for any that lies outside
   it, write the list to `docs/handoff/DISPATCH-CLOSE-GATE-01/unguarded-sources.md` and say so —
   do not edit files outside LANE_WRITES.
3. Add `tests/test-lib-source-guarded.sh`: a suite that FAILS when any script under
   `plugins/leadv2/scripts/` sources a lib without a fallback, so the fourth lane cannot repeat
   this. Prove it by removing one guard and showing RED.

## [Critical] C3 is still unprotected — fourth round running

I am told the reviewer unwrapped all five `_pc_evidence_with_unproven` production call sites and
the suite stayed `pass=17 fail=0`, then reverted clean. The downgrade is the only thing the founder
would actually see, and nothing tests it.

Assert on the **rendered close note** itself: build a close note through the production render path
with an unproven claim in it, and assert the rendered text carries the downgrade. Then unwrap the
call sites and show the suite RED.

## [High] both suites lost real mutation coverage without replacement

`test-mission-writeset.sh` lost 3 controls; `test-red-proof-gate.sh` lost 4, including the
`_pc_evidence_with_unproven` integration control — the very thing C3 needs. Removing a fake
assertion is right; removing a real one is how a suite becomes decorative.

Restore each removed control, or replace it with a stronger one and name the replacement in the
commit message. For every control you keep, show the mutation going RED.

## [High] `round4-red/changed-scope-green.log` is a timeout filed as green

A 124-timeout recorded under a green header. Regenerate every artifact from a run whose exit status
you assert, and make the artifact writer fail loudly when the run it records did not do what the
header says.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set before committing, and paste the runs.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

Both suites green at HEAD with the runs pasted; `:449` and `:455` guarded and the full source
census in `report.md`; `test-lib-source-guarded.sh` catching a removed guard; a control on the
rendered `unproven` note that goes RED when the five call sites are unwrapped; every removed control
restored or replaced by name; and every artifact regenerated from an asserted run.

## Round-5 note (added by the lead after the first attempt stopped early)

The first worker on this round produced a 646-byte diff and stopped at the close gate with
`selfcheck_failed: falsification:test-mission-writeset.sh:test_failed`. That failure is **expected
and is the work**, not a reason to stop. Reproduced by the lead at HEAD:

```
FAIL: C1: consumer symlink startup failed rc=1
  out=.claude/scripts/leadv2-dispatch-code.sh: line 449:
      .../consumer/.claude/scripts/leadv2-lane-child-suffixes.sh: No such file or directory
SUMMARY: pass=16 fail=1
```

That is precisely the unguarded `source` at `:449` this round exists to fix. Fix it first, get the
suite to `fail=0`, and then do the rest. The same worker also wrote that the unguarded sourcing was
"out of this round's explicit scope" — it is the round's first Critical item; that reading was wrong.
