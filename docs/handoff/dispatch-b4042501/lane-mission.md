# V3-DISPATCHER-ACCEPTANCE-01 — root-cause + regression-lock 3 live dispatcher faults (~/Projects/leadv2)

Tonight's dispatch path failed in 3 distinct, REPRODUCED ways. Each gets a root-cause with
evidence, a fix, and a red-first regression test.

## Fault 1 — PREPASS-RC1-RACE-01 (blocked every new product dispatch ~09:00-10:00)
claude-subsession.sh exits rc=1 «no DELIVERABLE_COMPLETE in architect.full.md (or missing
.summary.md)» while BOTH artifacts are complete on disk (live: dispatch-6632fad9-architect
09:26/09:27 and 09:46, dispatch-b9b04206). A grace-recheck (9a512a2, ≤10s) did NOT cure it —
so the checker is likely looking at a DIFFERENT HANDOFF_DIR than the dir the artifacts land
in (dispatch-<sig>-architect), or the worker's writes land via another path. Root-cause by
reading claude-subsession.sh's HANDOFF_DIR derivation vs leadv2-dispatch-code.sh's
architect_prepass adir (line ~2666), prove with a fixture run, fix, red-first test.
Secondary: after 2 failed attempts the task is parked and a retry goes straight to parked —
verify a park can be cleared by a successful prepass (or add a --clear-park path), test it.

## Fault 2 — mis-rooted lane worktree (ENV-GUARDS 6632fad9, 09:58)
Dispatched from `cd ~/Projects/leadv2` (bg bash from a persona-engine session), the worker
got a PERSONA-ENGINE worktree (~/Projects/persona-engine/.claude/worktrees/6632fad9 — no
plugins/ dir at all) and its stream/handoff landed in persona-engine/docs/handoff. The
worker then edited canonical ~/Projects/leadv2 main DIRECTLY (uncommitted, unprotected).
Suspect: PROJECT_ROOT / CLAUDE_PROJECT_DIR env leaking from the caller session overrides
cwd-derived root. Root-cause the resolution order, fix (explicit cwd-derived root must win
for repo selection, or refuse on mismatch with a loud journal line), red-first test:
dispatch with a foreign CLAUDE_PROJECT_DIR in env → worktree must be created in the CWD
repo, or the dispatch must refuse.

## Fault 3 — duplicate_task_signature after dead workers
A worker dies; redispatching the SAME mission is refused (duplicate_task_signature) until
the ledger row is hand-deleted by exact sig (done 4× tonight). Add a sanctioned path:
when the prior attempt's worker is provably dead (no live PID/handle) and no terminal
artifact exists, allow redispatch with journal `dispatch_retry_over_dead_attempt` (or ship
a `--retry-dead <sig8>` flag). Red-first test.

## Acceptance
All new/changed suites green with red-first legs shown · run-core-offline FOREGROUND solo
green in the lane (NEVER background-and-idle-wait) · bash -n + shellcheck -S warning ·
COMMIT on lane branch.

## Off_limits
leadv2-dispatch-product-close.sh (another live lane owns it — Fault 1-3 fixes live in
dispatch-code.sh / claude-subsession.sh / ledger helpers only); routing order/ceilings;
supervise*.

## Terminal artifact
Commit sha + per-fault root-cause note with raw probe + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b4042501" "<question>" \
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