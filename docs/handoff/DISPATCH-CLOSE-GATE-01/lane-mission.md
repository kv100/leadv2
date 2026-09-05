# DISPATCH-CLOSE-GATE-01 — stop the two things that cost the most rounds (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh,plugins/leadv2/scripts/lib/leadv2-red-proof.sh,plugins/leadv2/scripts/tests/test-mission-writeset.sh,plugins/leadv2/scripts/tests/test-red-proof-gate.sh,tests/run-all.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

This lane is not a bug fix. It is two mechanisms that, measured across one working day
(2026-08-30, three lanes, fourteen dispatch rounds), were the two largest multipliers on how long
a task takes to close. Both are cheap. Neither exists.

## Mechanism 1 — refuse a dispatch whose mission demands a path it may not write

**Measured cost: two full rounds, on two different lanes, in one afternoon.**

Twice the lead wrote a mission whose "Done means" required artifacts under
`docs/handoff/<TASK>/` (RED logs, a render proof) while `LANE_WRITES` listed only source and test
files. Both times the worker did the right thing — it stopped and said so rather than writing out
of scope — and both times the round was wasted and had to be re-dispatched with a corrected write
set. Verbatim from one of them:

> This is not full task closure: I did not complete all six requested mutation-red artifacts,
> `round4-red/`, `render-proof.md`, or the main-checkout copy. Those artifact paths conflict with
> the listed lane writes.

Build `lib/leadv2-mission-writeset.sh`, called by the dispatcher **before it spawns**:

1. Parse the mission for paths it *requires the worker to produce or modify* — at minimum every
   backticked path in a `## Done means` section, every path in a "leave the logs in …" or
   "write … to …" instruction, and the `LANE_WRITES:` line itself.
2. Any required path not covered by `LANE_WRITES` is a **refusal before spawn**, printing the
   exact missing paths and a ready-to-paste corrected `LANE_WRITES:` line. Not a warning — the
   whole point is that the round must not start.
3. False positives are the risk: a path merely *mentioned* (a report to read, a file cited as
   evidence) is not a required write. Prefer under-detecting to blocking a good dispatch, and put
   the detected set in the refusal message so a human can see what it thought.

Control: a mission whose Done-means names `docs/handoff/X/round4-red/` while `LANE_WRITES` omits
it must refuse with exit non-zero and name that path. A mission that only *cites* a report path
must dispatch normally. Mutate the check out and show the suite RED.

## Mechanism 2 — a worker may not report a fix without a RED artifact for it

**Measured cost: the dominant one. Five review rounds on one lane, four on another, five on a
third — and the single most repeated finding across all fourteen rounds was "this assertion
survives its own mutation".**

Three examples from today, all confirmed by an independent reviewer running the code:
- The entire rank fix — the founding incident, a dead lane losing its slot on the founder's
  statusline — could be **fully reverted with the suite still passing**.
- A "control" was written as `grep -q 'marker_len=${#marker}'`: it asserts that the *source text
  contains a string*, while the runtime result is computed and discarded.
- `test-dirty-lane-never-lands.sh:89` asserts with `! grep -Fq …`, and `set -e` does not trip on a
  negated command, so the load-bearing control for "worker writes outside its lane" **cannot
  fail**.

Every one of these cost a full round: worker claims done → reviewer mutates → survives green →
new brief → new round. The reviewer is doing work the worker should not have been able to skip.

Build `lib/leadv2-red-proof.sh`, enforced at the close gate:

1. A mission that names fixes (any `## [Critical]` / `## [High]` heading, or a mutation table) is
   a mission that owes one RED artifact per named fix, in the handoff dir.
2. A RED artifact is a **suite run** whose output shows a non-zero failure count, together with
   the mutation applied. A file containing only prose, or a run with zero failures, does not
   count.
3. At close, the gate cross-checks: fixes claimed in the worker's report vs RED artifacts on disk.
   A claim without one is reported as `unproven`, by name, in the close verdict — and the close is
   downgraded, not passed silently.
4. **Do not block the close outright.** A worker that genuinely disputes a finding with evidence
   must still be able to finish; the gate's job is to make an unproven claim visible and named,
   not to trap the lane. The lying-green disease is a *reporting* failure — fix the reporting.

Control: a fixture handoff dir with two named fixes and one RED artifact must close with exactly
one `unproven` name. A RED artifact whose run shows `0 failed` must not satisfy its fix. Mutate
the cross-check out and show RED.

## Why these two and nothing else

Also measured today, and deliberately **out of scope** — do not fix them here, they are filed:
seven workers ended without committing (a lane fix is already in flight), the codex job log
freezes at `Turn started` while the worker keeps writing (so liveness needs both signals), and
three lane-registration defects. Keep this lane to the two mechanisms above.

## Rules

- Every fix keeps a control you RUN: mutation inside the function body, RED, revert, GREEN. Leave
  the RED logs in `docs/handoff/DISPATCH-CLOSE-GATE-01/red/`.
- A control is a behavioural assertion on real output. No `grep` against script source, and no
  negated command as the assertion (`set -e` ignores it — that is finding C3 above).
- Add `EXTRA_SUITE_MAP` rows for both new suites and prove selection with `--scope changed`.
- Bash 3.2 only (macOS `/bin/bash` is 3.2.57): no `read -N`, no 4.x array idioms, and never leave
  an array unbound under `set -u`.
- `git add <file> <file>`, never `git add <dir>` — that swept 15 control-plane files into a shared
  repo today.
- Commit before you stop.

## Done means

Both mechanisms built and wired into the dispatcher, both suites green with every assertion
mutation-proven (RED and GREEN pasted, logs in `red/`), `--scope changed` selecting both suites
(output pasted), the lane clean of source changes, and a short note in
`docs/handoff/DISPATCH-CLOSE-GATE-01/report.md` showing the refusal message a bad write set now
produces and the `unproven` line an unbacked claim now produces.

## Write set note (corrected, round 2)

The first dispatch of this lane stopped on a scope conflict, and it was right to: the only live
close gate is `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, and that file was missing
from `LANE_WRITES`. It is now in scope. This is the third time in one day that the lead's write
set was the error — which is exactly the failure Mechanism 1 above exists to catch before spawn,
so treat the incident as a live specimen for the refusal message you are building.
