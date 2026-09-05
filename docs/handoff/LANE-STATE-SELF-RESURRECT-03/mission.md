# LANE-STATE-SELF-RESURRECT-03 — orphan recovery must not resurrect its own dispatcher

REPO: ~/Projects/leadv2 (canonical plugin). File: `plugins/leadv2/scripts/lib/leadv2-lane-state.sh`,
`reconcile` branch only (the `for worktree in worktrees:` loop, ~lines 108-131).

## Bug (observed 4x on 2026-08-27)
Orphan recovery matches `if worktree not in line: continue` against every `ps -axo pid=,lstart=,command=`
line. That substring test registers as a "recovered lane" ANY process whose argv merely mentions the
worktree path — including `leadv2-dispatch-code.sh --worktree <path>` (which itself calls
`lane_reconcile` at leadv2-dispatch-code.sh:5609, so it is the reconciler's own ancestor), plus lead
grep/monitor/tail shells. Result: the dispatcher refuses its own placement (`lane_is_live`,
verdict=starting age=2) — a self-fulfilling loop. Current workaround in the field:
`LEADV2_LANE_STATE_TEST_PS_FILE=/dev/null` on dispatch. Remove the need for it.

## Required fix (all four)
1. **Ancestry exclusion.** Build the pid ancestry of `os.getpid()` (walk ppid to 1) and skip any
   candidate pid in that set. Add a test seam `LEADV2_LANE_STATE_TEST_PPID_FILE`
   (`<pid>\t<ppid>` per line), same shape/precedence convention as the existing
   `LEADV2_LANE_STATE_TEST_BIRTH_FILE` — an observation source only, never a liveness override.
2. **Worker-session marker, not substring.** A candidate qualifies only if its command looks like a
   worker session: `claude`, `leadv2-session-runner.sh`, `leadv2-codex-session-runner.sh`, `codex`,
   `glm-coder.sh`, `kimi-coder.sh`. Anything else is skipped.
3. **Explicit non-worker denylist**, applied even if 2 somehow matches: `leadv2-dispatch-code.sh`,
   `leadv2-lane-liveness.sh`, `grep`, `ps`, `tail`, `Monitor`, and any line containing the flag
   form `--worktree` / `--resume-lane` (those are dispatchers pointing AT a lane, never the lane).
4. **Token match, not substring.** The worktree path must appear as a whole argv token (or with a
   `/`-suffix), not as an arbitrary substring of a longer path.

Keep everything else in the function unchanged: the `birth(pid) == start` liveness check, the
`/.claude/worktrees/` scope filter, the `known` set, the `break` after one recovery per worktree.

## Tests (mandatory, real function + fixtures one level lower — E2E-KILLRATE-01)
Add `tests/test-lane-state-self-resurrect.sh` in ~/Projects/leadv2 driving the REAL
`lane_reconcile` via the existing `LEADV2_LANE_STATE_TEST_PS_FILE` /
`LEADV2_LANE_STATE_TEST_WORKTREES_FILE` / `LEADV2_LANE_STATE_TEST_BIRTH_FILE` seams plus your new
PPID seam. Cases:
  a) dispatcher line (`leadv2-dispatch-code.sh --worktree /.../.claude/worktrees/X`) whose pid is an
     ancestor → NOT recovered;
  b) same dispatcher line, non-ancestor pid → still NOT recovered (denylist/marker);
  c) `grep`/`tail` line mentioning the path → NOT recovered;
  d) a genuine `claude` worker session in that worktree → IS recovered exactly once;
  e) path-prefix collision (`/.claude/worktrees/X-old` vs `/.claude/worktrees/X`) → no cross-match.
**Declared negative control:** state it in the suite header, then prove it — revert the marker check
inside the function body in a scratch copy and show case (a)/(b) go red. Paste that run output in
your deliverable. A suite that passes both before and after the mutation is worthless.

## Deliverable
`docs/handoff/LANE-STATE-SELF-RESURRECT-03/report.md` in ~/Projects/leadv2: the diff summary, the
test run output, and the negative-control run output. End with `DELIVERABLE_COMPLETE`.
Do not commit to persona-engine. Do not touch any other function in the file.
