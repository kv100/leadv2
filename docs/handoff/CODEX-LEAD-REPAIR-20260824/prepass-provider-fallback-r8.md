# PREPASS-PROVIDER-FALLBACK-01-R8

Mechanical recovery only. Do not rediscover or redesign.

Source worktree:
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PREPASS-PROVIDER-FALLBACK-01-R6`

1. Recover the committed base and the uncommitted dispatcher diff from R6.
2. Keep only:
   - `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
   - `plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh`
3. Discard every `.ppf-debug*`, `.test-dispatch-ppf-*`, runtime, registry, and handoff artifact.
4. Replace the contaminated end-to-end test section with isolated structural/unit fixtures. Never call the real dispatcher, global registry, or any model launcher.
5. Cover the reviewed contracts: isolated fallback cwd, owner-safe unregister, cleanup trap for every no-spawn exit, and fixture-backed provider/output classification. Tag any remaining external assumption `UNVERIFIED`.
6. Run only `bash -n`, the focused test, and the bounded existing tests already named in R6's mission/history. Do not run a broad suite.
7. Commit the two files and finish clean.

Do not debug `dispatch-test0008`; it is unrelated global residue.

acceptance:
  surface: review_gate
  observable: The recovered fix and isolated no-spawn regression test are committed cleanly and bounded checks pass.
  authored_at: 2026-08-24T20:45:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
