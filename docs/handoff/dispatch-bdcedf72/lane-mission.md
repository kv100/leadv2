RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01 — orphan recovery re-registers a lane every pass,
with a bystander pid and no write set, and that permanently blocks ALL dispatch in the repo.

THIS IS A LIVE BLOCKER, P0. As of 2026-09-04T10:22Z no lane can be dispatched in
persona-engine at all. Four consecutive dispatches were refused `writeset_conflict`.

THE MECHANISM, established exactly — file and line, not a hypothesis.
`plugins/leadv2/scripts/lib/leadv2-lane-state.sh`, the orphan-recovery block at ~160-183.

Two independent defects compose into a loop:

DEFECT 1 — `known` cannot see a lane worktree owned by a lead row.
  `known = {realpath(r['worktree']) for r in rows}` and a worktree is skipped only when
  `real in known`. But a LEAD-owner row carries the REPO ROOT in `worktree:`, not the lane
  worktree. Measured, both rows for the same task id:
    row A (live owner):  `worktree: /Users/…/Projects/persona-engine`   `pid_role: lead_durable`
    row B (recovered):   `worktree: /Users/…/persona-engine/.claude/worktrees/LIVE-LANES-…`
  So `known` = {repo root}. The lane worktree is never in it, is judged an orphan on EVERY
  reconciliation pass, and is re-registered forever. Deleting the row does not help: it was
  removed at 10:17Z under flock and returned at 10:22:41Z with the same pid.

DEFECT 2 — the pid is chosen by substring over the whole process table.
  `for line in ps: if worktree not in line: continue` — any process whose command line merely
  MENTIONS the worktree path is adopted as the lane's owner. Measured: pid 30132 is
  `/bin/zsh -c source ~/.claude/shell-snapshots/snapshot-zsh-….sh` — a tool shell, a passer-by,
  not a lane worker. `start == birth(pid)` only proves the pid was not recycled; it says nothing
  about whether the process owns the lane.

WHY IT BLOCKS EVERYTHING. The recovered row carries NO `writes:`. A row without a declared write
set falls into the pending window (`_lv2_ws_pending` in `leadv2-active-registry.sh`), which by
construction intersects ANY concurrent lane. So one mis-recovered row refuses every dispatch in
the repository, indefinitely.

Anti-false-lead, measured so you do not repeat them: narrowing `--writes` to a single existing
file did NOT change the refusal (so it is not about the write set's content); two OTHER
write-set-less rows were dead and were removed, and the refusal remained (so it is this row).

THE WORK. Three things, and the third is not optional.

1. Recovery must recognise a lane worktree that a live row already owns. Decide the correct
   identity for "already known" — the branch, the task id, the worktree path, or a combination —
   and say why the one you chose cannot be spoofed by a lead row pointing at the repo root.
2. Recovery must not adopt a bystander. A substring match over `ps` is not ownership. Establish
   ownership positively (process ancestry, the lane's own recorded handle, a pid file the lane
   writes — argue your choice). If you cannot establish ownership, register the row WITHOUT a
   pid rather than with a wrong one, and say what consumes that.
3. A row with no declared write set MUST NOT block the repository indefinitely. Give it a bound —
   a time window, or a condition that releases it. Name the bound and justify the number. This is
   the requirement that limits the blast radius of the next recovery bug, whatever it is, so it
   is required even if 1 and 2 are perfect.

ACCEPTANCE. The file already ships test seams — `LEADV2_LANE_STATE_TEST_WORKTREES_FILE` and
`LEADV2_LANE_STATE_TEST_PS_FILE`. Use them; do not orchestrate real processes.

1. Fixture: a lane worktree plus a live owner row whose `worktree:` is the REPO ROOT. Show no
   recovered row is created. This is the exact live case.
2. Fixture: a lane worktree with NO owner row, and a ps table whose only match is a shell that
   merely mentions the path. Show it is NOT adopted as owner. State what the row looks like
   instead.
3. Fixture: a genuine orphan with a real owning process. Show it IS recovered — the mechanism
   must still do its job. Without this case, a fix that recovers nothing would pass.
4. Show the write-set-less bound: a pending row past its bound no longer refuses a new lane.
5. NEGATIVE CONTROL, mandatory: revert your `known`-matching change INSIDE the function body,
   re-run case 1, show it goes red; restore, show green. Both outputs verbatim. A suite that
   never showed its own red proves nothing.
6. The suite carries a `# run-all-triggers:` header naming `leadv2-lane-state.sh`, and CI
   selection is proven with `tests/run-all.sh --scope changed`. `EXTRA_SUITE_MAP` was deleted
   2026-09-04 — a row added there now silently never runs.
7. Report the suite's final count line verbatim; if it prints none, say so.

CONSTRAINTS. This file is in the shared plugin tree feeding three repositories; the founder
authorised work in this tree this session. Never `git add -A`. Do not push to origin. Do not
widen `tests/known-red-suites.txt` — it may only shrink. If the close gate returns
`e2e_regression`, run the named suites on main WITHOUT your commit before believing it — a
verdict is not evidence.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-bdcedf72" "<question>" \
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