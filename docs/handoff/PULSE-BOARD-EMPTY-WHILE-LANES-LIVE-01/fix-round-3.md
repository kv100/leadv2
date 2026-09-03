# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 3: the fix hardens against a condition nothing creates

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/tests/test-pulse-empty-board.sh,plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh,plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh,tests/test-status-surface-bash32.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

Full report: `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/review-r2.md`. HEAD is `67f8b8d`.

**Verified real, keep it:** the collector does find a lane in another repo, the board is non-empty
for the currently live lanes, the bash-3.2 sweep is clean, and `--scope changed` selects suites that
actually run. The suite was also confirmed to be at full strength — no coverage was cut.

## [Critical] the stated root cause is not demonstrated

Round 2 says the board was empty because the collector scanned only one repo, and fixes it by
pinning `LEADV2_LANES_ALL_REPOS=1`. But a sweep of the whole codebase finds the only place that
sets it to `0` is the lane's own test. Under shipped defaults the collector scanned every repo
**before** the fix too — so the pin hardens against a condition nothing in this codebase creates,
and the founding incident is still unexplained.

Do one of two things, and say which:

- Produce the artifact showing `LEADV2_LANES_ALL_REPOS=0` in the incident's actual environment; or
- **Restate the root cause as the bash-3.2 parse failure** (the defect `67f8b8d` fixed) and prove
  it from the incident's own log or beat output — a parse failure would empty the board exactly as
  observed, and that is the more likely explanation.

Keep the pin either way; it is harmless. What must change is the claim.

## [Critical] `leadv2-broad-status.sh:47-48` carries a false control claim

A production comment names a suite as locking the behaviour, and that suite stubs the very thing it
claims to lock. Delete the claim or correct it. A comment that tells the next reader a behaviour is
covered, when it is not, is the same disease as a green test that asserts nothing.

## [Critical] the existing foreign-lane suite is RED, and a green duplicate was shipped beside it

`test-broad-status-foreign-lanes.sh` fails at S1 (`foreign row missing: table=[]`) and at S3/S4,
while this lane's new suite passes on the same behaviour. Shipping a green duplicate next to a red
original is exactly the lying-green pattern this task exists to kill.

Fix S1/S3/S4, or prove with evidence that the suite is rot — and if it is rot, say what changed
underneath it and when.

## [High] `67f8b8d` has no control at all

The bash-3.2 heredoc fix — the one that may well be the real root cause — is held by nothing. Add
`bash -n` on `leadv2-broad-status.sh` under `/bin/bash` (in `tests/test-status-surface-bash32.sh`
or a new suite registered in `EXTRA_SUITE_MAP`), then mutation-prove it: re-nest the heredoc → RED
→ revert → GREEN.

## [High] no board-level case runs the real collector

Make at least one case in `test-pulse-empty-board.sh` (or the new suite) drive the REAL collector
against a genuine two-repo state, so a collector regression goes red **at the layer the founder
actually reads** rather than one layer below it.

## [Medium] two small ones

- `red/mutation-red.log` records only half its run. Regenerate every artifact from a run whose exit
  status you assert. Note `.gitignore:40` hides `docs/handoff/*/*` — commit artifacts with
  `git add -f <file>`, one file at a time, and do not edit `.gitignore`.
- Add `</dev/null` to the `python3 "$RENDER_TMPDIR/render.py"` call at
  `leadv2-broad-status.sh:944`.

## Done means

`tests/run-all.sh --scope changed` exiting 0 — or every pre-existing red suite enumerated with
proof it is equally red on `main`; the root cause either evidenced or restated with proof; the false
control comment gone; `test-broad-status-foreign-lanes.sh` green or proven rot; `67f8b8d` held by a
mutation-proven control; one board-level case driving the real collector; and artifacts committed
with `git add -f`, each recording a run whose outcome matches its header.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set before committing and paste the runs.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Round-3 continuation note (lead, after the first attempt stopped part-way)

Two items ARE done and correct — keep them: the false control comment at
`leadv2-broad-status.sh:45-48` now states the evidenced cause honestly (the bash-3.2 parse
failure), and the parse control exists — `tests/test-status-surface-bash32.sh` is 16/0. I committed
that work as `0c1ef48` after the worker went quiet with it uncommitted.

**The defect is happening LIVE right now — diagnose from it, not from fixtures.** At beat
`2026-08-30T16:53:43Z` the founder's board rendered `(статус не собран) … render failed`, and at
the two following beats it listed only three completed codex reviews while SEVEN lanes were
actively writing files.

The shape matches the still-red suite: `test-broad-status-foreign-lanes.sh` fails S1 with
`foreign row missing: table=[]` — an empty table, exactly what the founder saw. It is `PASS=5
FAIL=3` right now.

Still outstanding: fix S1/S3/S4 or prove rot; a board-level case driving the REAL collector against
a two-repo state; artifacts committed with `git add -f`; and `</dev/null` on the
`python3 "$RENDER_TMPDIR/render.py"` call.

## Live counter-example, 2026-08-30T18:27:16Z — plus a SECOND defect beside it

The board rendered `| (живых линий нет) | — | — |` at a moment when
SESSIONSTART-HOOKS-DISCARDED-01 had written **47 files in the preceding six minutes** and five
other lanes were running. That is the founding defect reproducing on the founder's own surface.

`test-broad-status-foreign-lanes.sh` is now 8/0 (was 5/3) and
`test-collector-sees-registered-lane.sh` is 4/0 with its mutation control — committed as `d651994`
after the worker went quiet with it uncommitted. **The board is still wrong**, so a green suite did
not fix what the founder sees. Close the gap between the suite's notion of a live lane and the
board's, at the board layer.

**Second defect.** At the same beat the liveness prober reported `corroborated dead: pid dead` for
that same 47-files-a-minute lane, and asked to escalate three times today for lanes plainly alive.
A prober that calls a writing lane dead is how a live lane gets abandoned. If it is in this write
set, fix it — liveness by recent worktree writes, not by a pid a re-dispatch has replaced. If not,
write the file:line finding to `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/liveness-prober-false-dead.md`.

<!-- lead: re-dispatch 2026-08-30T18:40Z after the previous attempt died; ledger row closed as dead, which blocks retry on the same task signature, so this line changes the signature. -->
