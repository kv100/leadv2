# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 5: the suite passes with the fix removed

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-active-registry.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

Full review: `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/review-r4.md`. HEAD is `2945eef`.
Main is `42d3232`; rebase onto it before anything else.

**One thing genuinely landed and it is the founder-visible half: a foreign-repo row now renders.**
`LEADV2_PROJECT_ROOT=~/Projects/leadv2 LEADV2_LANES_ALL_REPOS=1 bash leadv2-broad-status.sh` puts
`| persona-engine/dispatch-154054d6 | — | foreign repo persona-engine; pid=alive; no stream |` into
`founder-status.md`. Round 3's repo-scope fix is real and proven. Keep it.

The other suites hold: `test-pulse-empty-board.sh` 10/0, `test-collector-sees-registered-lane.sh`
4/0, `test-broad-status-foreign-lanes.sh` 8/0.

## [Critical] the new suite cannot tell fixed from broken

`test-lane-registry-outlives-dispatcher.sh` scores 5/0 — and it scores 5/0 with the round-4 block
neutralized in place, and 5/0 against the file at `c2dfd0d` where the fix does not exist at all.
The reviewer ran all three and restored the file with a clean `git diff --stat`.

Root cause he found: row liveness in the harness is carried by `_lv2_durable_pid`
(`leadv2-active-registry.sh:669`), which walks the `$PPID` chain to a durable claude process — in
the test that resolves to the test script's own long-lived process, alive no matter what round 4
did. The suite never isolates from that pre-existing mechanism, so it measures the harness, not the
change.

I committed this suite myself and wrote "verified, not taken on trust: 5/0" in the commit message.
Running a suite and seeing it green is not verification — that is the exact error this lane exists
to stamp out, and I made it. The commit message is wrong and `report.md` must say so.

Fix the suite so it isolates from `_lv2_durable_pid`: the registered pid under test must be a real
process the test controls and can kill, not an ancestor of the test itself. Then prove it three
ways, all pasted:
- with the fix present: GREEN;
- with the round-4 block neutralized in place: RED, naming the assertion;
- against the file at `c2dfd0d`: RED.

Also correct the framing while you are there. The reviewer found the code re-pins non-sonnet arms'
`active.yaml` pid to the lane-pulse-watch pid (`leadv2-dispatch-code.sh:4971-4980`); the exit-trap
disarm at `:7102` predates round 4. `report.md` should describe what the change actually does.

## [Critical] three own-repo lanes are invisible — state-root fragmentation

The board renders the foreign row but not `DISPATCH-CLOSE-GATE-01`, `DISPATCH-PIN-CLUSTER-01` or
`ANTI-SILENCE-STATUSLINE-01`. `~/Projects/leadv2/docs/leadv2/active.yaml` has **zero** `task_id`
rows; those three are registered under isolated `.ephemeral/leadv2-lwt.*` state roots that are never
consolidated into the root the board reads.

Same disease as the original defect, one layer down: the registry is written somewhere the reader
never looks. Either consolidate the ephemeral roots into the project root, or make the board read
every root a lane can register under. Then paste a board render listing all live lanes — own-repo
AND foreign — and hold it with a suite that fails when an ephemeral-root lane is dropped.

## [High] the liveness prober — third round, still nothing

Round 3 allowed a fix or a writeup; round 4 delivered neither and the diff touched only two files.
Tonight it escalated `SESSIONSTART-HOOKS-DISCARDED-01` as `corroborated dead` three times — once
`pid dead`, once `pid birth mismatch` — while that lane was actively writing. It compounds too: a
dispatch refused with `lane_is_live` still registers an arm row, so the next retry is refused as
well.

Fix it here, or write `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/liveness-prober-false-dead.md`
with the file:line of the pid check and of the refusal-registration, and say so in `report.md`.
Silently dropping it a third time is a FAIL.

## [Medium] CI does not select the new suite, and `run-all.sh` has diverged

No `EXTRA_SUITE_MAP` row exists for `test-lane-registry-outlives-dispatcher.sh`, so CI never runs
it. Add the row and prove it with `--scope changed`.

`tests/run-all.sh` is 107 lines from main. Main carries HOOK-OUTPUT-CAP's state-file-bounded
last-checked-SHA selection, DISPATCH-CLOSE-GATE's widened
`scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob, the `freepool-arm.yaml` stem case and several map
rows. Keep main's block and re-apply this lane's rows on top; do not take either side wholesale.

## [Medium] the `❓` leak, carried from round 4 item 5

On merged main, `test-status-surface.sh` scores 85/5 with an unknown-lane count leaking into the
rendered surface (`❓7`, `❓8`); the same suite is 90/0 inside the ANTI-SILENCE-STATUSLINE-01 lane,
and `leadv2-broad-status.sh` differs by 383 lines between them — much of that difference is this
lane's. Determine whether live lanes are being classified as unknown by this lane's changes. If
they are, it is this lane's bug.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. **A suite that stays green with the fix removed is a failed
  control, not a passing test.**
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

A registry suite that goes RED against `c2dfd0d`, a board render listing every live lane including
own-repo ones, the liveness prober fixed or written up with file:line, and the new suite selected by
CI.
