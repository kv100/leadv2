# V3-STOP-GATE-FINISH-01 — close the 2 critic holes in pc_stop_gate_autocommit (~/Projects/leadv2)

Base: lane branch worktree, checkpoint 747f453 already contains the full STOP-GATE
implementation (pc_stop_gate_autocommit in leadv2-dispatch-product-close.sh:~1399, call at
:1837, kill-switch LEADV2_STOP_GATE, suite tests/test-stop-gate.sh, registered in
run-core-offline.sh). Critic verdict FAIL with exactly 2 holes — READ THE REPORT FIRST:
~/Projects/leadv2/docs/handoff/dispatch-e93d9162-review/critic.full.md (§1 and §2, with repro).

## Hole 1 (P0) — missing declared pathspec makes the gate a silent no-op
`git status --porcelain -- <declared paths>` tolerates a pathspec that matches nothing, but the
subsequent `git add -- <same paths>` exits 128 (`fatal: pathspec ... did not match any files`)
and stages NOTHING; the `|| return 0` swallows it. Since write-sets are declared BEFORE the work,
a dead worker almost always leaves some declared path uncreated — the gate fails silently in its
primary scenario.
FIX: derive the files to stage by PARSING the `git status --porcelain` output (the concrete
existing files), not by re-using the declared pathspec array. Handle the rename form
(`R  old -> new` — stage `new`), quoted paths with spaces, and the `??` untracked form. Stage
that concrete list; if `git add` still fails, journal a loud `stop_gate_autocommit_failed` line
instead of silent return.

## Hole 2 (HIGH) — timeout-reaped worker never reaches the gate
Both `worker_timeout` branches (product-close.sh ~1801–1808 and ~1820–1830) call
`_pc_reap_worker` then `exit 5` BEFORE the :1837 gate call. A reaped worker is the most likely
producer of uncommitted work. FIX: invoke pc_stop_gate_autocommit immediately after each
`_pc_reap_worker`, before the `exit 5` (respect the kill-switch there too).

## Tests (extend tests/test-stop-gate.sh, red-first)
(d) write-set declares an existing modified file + a never-created path → commit happens, the
    existing file is committed, journal line present [this leg must FAIL against 747f453 —
    show the red run in your output];
(e) rename inside write-set → new path committed;
(f) worker_timeout path → gate fires before exit 5 (simulate: fake worker pid that never exits,
    tiny wait ceiling) [red-first against 747f453];
(g) hole-1 fix must NOT commit junk outside the write-set (re-assert scoping).

## Acceptance
Suite green with red legs shown · run-core-offline FOREGROUND solo green in the lane (NEVER
background-and-idle-wait — that kills workers) · bash -n + shellcheck -S warning on
product-close.sh · COMMIT on the lane branch (do not leave the tree dirty — you are fixing the
commit-before-exit gate; an uncommitted exit here is maximal irony and an incident).

## Off_limits
leadv2-dispatch-code.sh routing block; supervise*; everything outside product-close.sh + the
test file + run-core-offline.sh registration.

## Terminal artifact
Commit sha + red-run + green-run raw output for legs (d)/(f) + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2704c96d" "<question>" \
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