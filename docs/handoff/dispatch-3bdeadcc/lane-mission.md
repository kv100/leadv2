# SUPERVISOR-RESIDUE-SWEEP-01 — delete supervisor residue (critic nits after SUPERVISOR-DELETE-01)

Landed 82da344 retired the supervisor; the critic's PASS_WITH_NITS report
(~/Projects/leadv2/docs/handoff/dispatch-eacd0eb5-review/critic.full.md — READ FIRST) left:

H1 Retired mode still ENTERABLE: bare `leadv2-lanes-snapshot.sh` writes `.supervise-active`,
   which arms 4 still-registered hooks incl. a session-wide git-commit lockout. Delete the
   writer + the 4 hook arms (grep .supervise-active across hooks/ + scripts/; each hit:
   migrate-or-delete with cited grep). The founder's order: the supervisor NEVER returns.
H2 3 dead test files reference deleted/renamed scripts and cannot run:
   test-question-delivery-01.sh, test-supervise-sentinel-readonly.sh,
   test-supervise-stale-truth.sh. Per file: if the subject survives (question delivery
   presumably does), retarget to the live subject; if the subject died with the loop,
   delete file + any SUITE_DEFS row. Cite the subject check.
M1 `.supervise-loop.heartbeat` has ZERO writers → leadv2-status-surface.sh S3 block
   (~200 lines, :20,:258,:300-317,:2568) + the `supervisor: OFF` field are dead. Sweep them;
   status output must stay valid (run the status suite after).
L1 leadv2-lanes-resume.sh:52 prints `[supervise-resume]` — rename the tag.
L2 leadv2-lanes-snapshot.sh:2,35,78 self-identifies as leadv2-supervise.sh incl. --help. Fix.
L3 retirement date stated 3 ways (08-17/08-19/08-20) — normalize to 2026-08-17 (founder order date).
L4 `/leadv2 fanout` doc entry — founder ordered supervisor deleted; fanout is its dispatch
   arm: replace with the same refuse-stub pattern as `supervise`, cite the command file.

## Acceptance
grep proof: zero `.supervise-active` / `supervise-loop.heartbeat` references in hooks/ +
scripts/ (docs archive excluded) · affected suites green (lanes-snapshot, status-surface,
question-delivery if retargeted) · run-core-offline FOREGROUND solo green in lane (never
background-and-idle-wait) · bash -n + shellcheck -S warning · COMMIT on lane branch.

## Off_limits
leadv2-dispatch-product-close.sh; leadv2-dispatch-code.sh (two other live lanes own them);
lib/leadv2-builder-selfcheck.sh.

## Terminal artifact
Commit sha + per-finding classification + raw greps + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3bdeadcc" "<question>" \
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