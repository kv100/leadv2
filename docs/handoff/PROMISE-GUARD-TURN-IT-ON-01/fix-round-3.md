# PROMISE-GUARD-TURN-IT-ON-01 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01`
LANE_WRITES: plugins/leadv2/hooks/leadv2-promise-guard.sh,plugins/leadv2/scripts/tests/test-promise-action-binding.sh,plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh,plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh,tests/run-all.sh,docs/leadv2/scheduled-decisions.md,docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last is `5f657a4`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 2
`status=fail reason=suite_not_falsifiable suite=plugins/leadv2/scripts/tests/test-promise-action-binding.sh`
```
baseline: rc=0
probe[assertion_tools_broken]: rc=0 shim_invocations=0
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
```
Round 1's finding was the same disease on a different file (`test-lib.sh`). The gate injects three
failures (jq/grep/python shims that always fail, an empty cwd, a stripped env) and the suite still
exits 0 every time. `shim_invocations=0` says the suite never even called the shimmed tools: with a
stripped env / empty cwd its cases are being skipped or resolved as "could-not-run" in a branch
that does not raise `FAIL`, or the hook under test fails open to SILENT and every SILENT-expecting
case passes while the FIRED-expecting ones never run.

## Do
1. Reproduce the probe yourself first — run the suite with `PATH` pointing at a dir where `jq`,
   `grep`, `python3` are `exit 1` stubs, then from an empty temp cwd, then with `env -i bash …`. Paste
   all three exit codes in report.md BEFORE changing anything. Then find the branch that returns 0.
2. Make the suite honest: any case that cannot run (hook missing, pre-image unresolvable, tool
   missing, hook output unparseable) is `FAIL`, never `COULD_NOT_RUN`-and-continue; the `FIRED`
   cases must assert on the hook's real `decision:block` / exit-2 output, so a hook that fails open
   turns those cases red. Do the same audit on `test-promise-guard-morphology.sh` and
   `test-promise-guard-classified-block.sh` — the gate will probe them next.
3. Run `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh <suite>` on all three suites yourself
   and paste the verdict lines (must read FALSIFIABLE).
4. Mutation negative control, RUN and paste red: in the hook, force `verdict=suppressed_action`
   unconditionally → the classified-block suite exits non-zero. Revert.
5. Commit with the three verdict lines + control in "## Round 3 evidence" of report.md.
