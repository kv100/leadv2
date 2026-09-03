# ANTI-SILENCE-STATUSLINE-01 — round 10: the suite reads live state, that is the whole bug

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

HEAD is `da059b1`. Main is `6b5d651` — rebase onto it first.

**Round 8 passed review and stays.** The `read` here-string repair, byte-identical output, the
fallback-path coverage with 9 named `FB-*` assertions, the ~41% perf gain — all independently
re-verified. Nothing there is in question.

## The `❓` dispute is settled — it is not a regression, and not PULSE's bug

I traced it myself. `❓N` is **not** an unknown-lane count. It is the pending-questions counter
`Q_N` (`leadv2-status-surface.5s.sh:454` and `:522`). Right now `~/Projects/leadv2/docs/leadv2/questions/`
holds **139 rows with `status: pending`**, and `test-status-surface.sh` renders against that live
directory instead of a fixture.

That is why its count moves with the world and not with the code:

```
inside the lane          90 passed,  0 failed
on main after 42d3232    85 passed,  5 failed
on main after 6b5d651    62 passed, 21 failed
```

Nothing in `leadv2-broad-status.sh` caused this. A suite whose result depends on how many questions
happen to be open is not a control.

## [Critical] make the suite hermetic

Point every render in `test-status-surface.sh` at a fixture questions directory it creates and
controls — the same way it already sandboxes `LEADV2_STATE_ROOT` / `LEADV2_STATE_BASE` at
`:297-299` and `:1283`. Nothing may read the real
`docs/leadv2/questions/`, the real registry, or the real founder-status file.

Prove it three ways, pasted:

1. green on merged main with its count;
2. green again **with a question added** to the real questions directory and then removed — the
   count must not move;
3. a control: point one render back at the live directory and show that assertion RED, then restore.

Audit the rest of the suite for the same shape while you are in there — any other live-state read is
the same defect and must be sandboxed too. Say in `report.md` how many you found.

## [Medium] `tests/run-all.sh`

Reconcile with main: keep main's state-file bounding, the widened
`scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob and the `freepool-arm.yaml` case; re-apply this
lane's `test-*.sh` self-selection case and its two `leadv2-lane-status-line*.sh` map rows on top.
Do not take either side wholesale.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production file, RED, revert, GREEN, clean
  `git diff --stat`. A suite that stays green with the fix removed is a failed control; a printed
  `RED control:` line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

`test-status-surface.sh` green on merged main with a count that does not move when the real
questions directory changes, and a reconciled `tests/run-all.sh`. Then this lane is merge-ready.
