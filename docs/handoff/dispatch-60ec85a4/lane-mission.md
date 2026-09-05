# MON-PULSE-01 fix-round 2 — review round-2 FAIL: 4 High (Heavy)

FIRST STEP, mandatory: in your lane worktree run `git merge worktree-21a4f402` —
that branch carries build+fix-round-1 (817699b). Fix on top of it.

Full review (fix ALL four High findings EXACTLY as written there — read it first):
.claude/worktrees/21a4f402/docs/handoff/dispatch-21a4f402/review-opus.md
Also fix M3 (worker_died matches nothing ever emitted — align the terminal pattern
with the strings the journal actually writes; grep the emitters, do not guess).

Headlines (details in the review):
- H1: --timeout 3900 silently abandons ~11% of real lanes — the watcher must outlive
  the real lane timeout distribution (derive from the dispatcher's own timeout env,
  not a constant) and write a final `watch_timeout` pulse instead of dying silently.
- H2: W4 negative control cannot fail (probe-confirmed). Rebuild W4 so the mutation
  genuinely flips the assertion; PROVE by running the mutated copy red in the suite
  output. A control that cannot fail is the lying-green disease.
- H3: the beat loop can only ever serve one worktree — key its pidfile + lane scan by
  project root so parallel repos each get a beat (or one loop scans all roots; pick
  the smaller change, justify in report).
- H4: the lane pulse has no demonstrated route to the founder. Wire the beat writer so
  BROAD_STATUS founder-status.md includes the lane pulse lines (the founder-facing
  surface), and prove it in a test: fake lane journal -> watcher pulses -> beat tick ->
  founder-status.md contains the lane line.

Re-run both suites green, bash -n all touched scripts, negative controls RUN red.
Commit: fix(leadv2): MON-PULSE-01 fix-round 2 — H1..H4 + M3.
Report: docs/handoff/MON-PULSE-01/fix-round-2-report.md (max 200 words, raw tails),
end DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-60ec85a4" "<question>" \
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