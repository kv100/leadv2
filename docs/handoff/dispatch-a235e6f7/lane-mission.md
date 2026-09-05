T16 NARROW FINISHER (two prior workers each committed part and died at turn-cap; base branch lane-t16hyg @4170599 already has §1 codex-guard env-prefix, §6 promise-guard fast path, §9 plugin-sync syntax gate, §10 lane deregistration — do NOT redo those). Finish ONLY the remaining items, one commit each, smallest-first. Full original mission: docs/handoff/dispatch-c0d6245a/lane-mission.md (or the earlier lane-mission in the same worktree).

Remaining:
§8 Delete plugins/leadv2/scripts/tests/test-supervisor-fanout-guard.sh (supervisor retired; also remove any run-all/core-offline mapping row referencing it).
§2 Deregister the 2 supervisor-only hooks from hooks registration (find them: grep supervise plugins/leadv2/hooks/ + the plugin hooks manifest).
§3 engine-flag-row-inject: collapse duplicate registration to one.
§5 feature-liveness-inject -> summary form (one line instead of full dump).
§7 Merge drift-warn hook logic into the one-copy check (single hook, one report).
§4 docs-truth-inject: auto-refresh the last-verified stamp when content hash unchanged (stop failing the gate purely on stamp age; the gate failed live 2026-08-27 on open-threads-rules.md).
§11 WORKTREE-RESURRECTOR-02: find what re-creates anchor worktrees/branches after removal (candidate: SessionStart lane-recovery scanning stale journals/handoff dirs). Gate it: re-create only for lanes registered in active.yaml AND with a live PID. Probe/test required.
§12 Board-healer overreach: the open-threads head/tail regenerator must rewrite ONLY content between its BEGIN/END GENERATED markers, never restore archived content, never consume hand [x] rows without appending them to open-threads-archive.md in the same write (both misfires observed live 2026-08-27). Synthetic-board test required.

Constraints: bash -n everything; fail-open on missing infra; suites for §9/§10 from the prior commits must stay green (run them once at the end and show output).

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a235e6f7" "<question>" \
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