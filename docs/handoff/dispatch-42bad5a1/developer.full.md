verdict: APPROVE
next_action: review_round_2

# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 3

Prior work (rounds 1-2, commits b63662a/33b981d/67f8b8d/0c1ef48) is unchanged and still
correct: the `LEADV2_LANES_ALL_REPOS=1` pin, the false-comment fix's honest bash-3.2 framing,
and the parse control (`tests/test-status-surface-bash32.sh` T2b) all stand. This round closes
the round-3 review's remaining findings, committed as `d651994` (autocommitted by lead when a
prior worker session went idle mid-task, capturing the S1/S3/S4 fix + the board-level case) and
`c2dfd0d` (root-cause evidence + regenerated mutation-red.log).

## [Critical 1] Root cause demonstrated, not restated

The review was right that a codebase grep finds nothing setting `LEADV2_LANES_ALL_REPOS=0`.
It isn't in the codebase — it's in this machine's global Claude Code settings:

```
$ grep -n -B2 -A2 LEADV2_LANES_ALL_REPOS ~/.claude/settings.json
    "CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION": "200",
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2",
    "LEADV2_LANES_ALL_REPOS": "0"
  },
$ env | grep LANES_ALL_REPOS
LEADV2_LANES_ALL_REPOS=0
```

That `env` block applies to every Claude Code session launched on this machine — every real
dispatch, every lead pulse, every worker. Fixture proof under that exact ambient default (no
override):

```
leadv2-lanes-snapshot.sh --json  (own repo: sessions: []; foreign repo: 1 live lane)
-> "table": []
```

Same fixture with `LEADV2_LANES_ALL_REPOS=1` forced (what `leadv2-status-collector.sh:125`
does today):

```
-> [{'task_id': 'dispatch-fee00001', ..., 'repo': 'foreignrepo', ...}]
```

So the collector's pin is a live, active override of a real machine-wide default — not
hardening against a condition nothing creates. Full transcript in
`docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/root-cause-evidence.log`.

Rewrote the comment at `leadv2-broad-status.sh:45-60` to state this, and to keep the
bash-3.2 parse failure (67f8b8d) as a second, independent, also-real cause — the round-3
continuation note's live incident showed both symptoms (a "render failed" beat, then beats
with only 3 rows while 7 lanes were live), at different beats of the same window
(2026-08-30T16:53-17:00Z), which matches two distinct bugs rather than one.

## [Critical 2] False control comment

Already fixed by the round-3-partial worker before this session started (commit 0c1ef48);
verified still correct — the comment at that location is honest about the bash-3.2 cause and
does not claim a suite locks a behavior it stubs.

## [Critical 3] test-broad-status-foreign-lanes.sh was RED (5/3)

Root cause: the suite's own `snap()` helper called `leadv2-lanes-snapshot.sh --json` directly
(not through the collector, which has the pin) and never set `LEADV2_LANES_ALL_REPOS`, so it
silently inherited this machine's ambient `=0` — S1/S3/S4 all depend on the all-repos scan
being on by default. Fix: `snap()` now sets `LEADV2_LANES_ALL_REPOS=1` explicitly (an env
default, not a hardcoded flag — an explicit `--no-all-repos` in `"$@"`, as S2 uses, still wins
since CLI parsing runs after the env-derived default inside the script). Result: 8/0.

```
[TEST] PASS: S1: foreign live lane in the table with repo=foreignrepo
[TEST] PASS: S4: own-repo mirror slug skipped by the -ef filter, foreign repo still read
[TEST] PASS: S2: single-repo output byte-identical with --all-repos on (consumer safety)
[TEST] PASS: S3: failed foreign repo -> one repo_read_error row, healthy repo's lane still in table
[TEST] PASS: R1/R1b/R2/R3 (renderer, stubbed collector) -- unchanged, already green
[broad-status-foreign-lanes] PASS=8 FAIL=0
```

## [High] 67f8b8d control

Already present (`T2b` in `tests/test-status-surface-bash32.sh`, added by the round-3-partial
worker). Mutation-proven this round (re-nested the heredoc back inside the `$(...)`
production file, in place, not a scratch copy):

```
=== RED (mutated) ===
leadv2-broad-status.sh: line 207: unexpected EOF while looking for matching `)'
bash-n-exit=2
FAIL - broad-status composer syntax error under bash 3.2: ... line 207: unexpected EOF ...
=== revert + GREEN ===
bash-n-exit=0
ok   - broad-status composer parses clean under bash 3.2
(git diff --stat after revert: empty)
```

Full 16-case suite: `test-status-surface-bash32: 16 passed, 0 failed, 0 skipped`.

## [High] No board-level case ran the real collector

Added to `test-collector-sees-registered-lane.sh` (which already had the right two-repo
fixture, previously only checked the collector's JSON one layer below the board): a new
`run_board()` case that runs the REAL `leadv2-status-collector.sh` (not stubbed) feeding the
REAL `leadv2-broad-status.sh`, and asserts the foreign lane appears on `founder-status.md`
itself — the artifact the founder actually reads. It carries its own mutation control:
removing `leadv2-status-collector.sh`'s `LEADV2_LANES_ALL_REPOS=1 \` line (production file, in
place, restored via `cp` from a pre-mutation backup + `bash -n` verified after revert)
reproduces the empty-of-foreign-lanes board (RED), then the revert restores it (GREEN).

```
[TEST] PASS: registered persona-engine lane survives collector despite ambient all-repos=0
[TEST] PASS: board-level: real collector + real renderer show the foreign lane on founder-status.md
[TEST] PASS: mutation control: removing the collector's all-repos pin reproduces the empty-of-foreign-lanes board (RED)
[TEST] PASS: mutation control: reverted collector.sh restores the foreign lane on the board (GREEN)
[collector-sees-registered-lane] PASS=4 FAIL=0
```

## [Medium] Two small ones

- `red/mutation-red.log` regenerated from two full runs this round (was previously
  half-recorded): the 67f8b8d control and the collector-pin control, both with their raw
  RED/GREEN output and a `git diff --stat` confirming a clean revert. Committed with
  `git add -f` (`docs/handoff/*/*` is gitignored per `.gitignore:40`).
- `</dev/null` on the `python3 "$RENDER_TMPDIR/render.py"` call at
  `leadv2-broad-status.sh:954` — already present (added by a prior round); verified in place,
  no change needed.

## Full-suite verification

```
bash -n <every changed .sh file>                                    all OK
plugins/leadv2/scripts/tests/test-pulse-empty-board.sh              10 passed, 0 failed
plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh  4 passed, 0 failed
plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh      8 passed, 0 failed
tests/test-status-surface-bash32.sh                                 16 passed, 0 failed, 0 skipped
```

`tests/run-all.sh --scope changed`: ran to completion under a 1200s background timeout (the
harness's own foreground-Bash timeout is 120s, hence backgrounding); every suite whose subject
file this lane's diff touches passed. The run surfaced pre-existing failures in
`leadv2-dispatch-code.sh`, `leadv2-review-run.sh`, glm-deferred/credits, and resume-lane-
placement suites (`run-core-offline.sh` shards). Proof these are pre-existing, not introduced
here: `git diff --stat main...HEAD` for this lane's branch touches exactly 6 files —
`leadv2-broad-status.sh`, `leadv2-status-collector.sh`, `test-broad-status-foreign-lanes.sh`,
`test-collector-sees-registered-lane.sh`, `tests/run-all.sh`, `tests/test-status-surface-bash32.sh`
— none of which are the files behind the failing suites, so their pass/fail state is identical
to `main` by construction (same file content -> same test outcome).

## Rule compliance

- Mutation performed INSIDE the production file body, in place, RED confirmed, reverted, GREEN
  confirmed, `git diff --stat` empty after revert — for both this round's controls (67f8b8d,
  collector pin) and re-verified for the pre-existing round-1 pin control.
- No `grep`-against-source assertions, no negated-command assertions, no scratch-copy mutation.
- Bash 3.2.57 targeted explicitly (`/bin/bash -n`, `/bin/bash` runtime for T2b/T3/T7/T8c).
- `git add -f docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/root-cause-evidence.log` and
  `.../red/mutation-red.log`, one file at a time; `.gitignore` untouched.

## What I deliberately left alone

- `leadv2-dispatch-code.sh`, `leadv2-review-run.sh`, glm-deferred/credits, resume-lane-
  placement — pre-existing failures outside this lane's write set (see proof above).
- The round-1/round-2 live-proof narrative in the prior `developer.full.md` (kept as history
  above this section is a fresh round-3 report, not an edit of that narrative).

DELIVERABLE_COMPLETE
