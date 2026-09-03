# ANTI-SILENCE-STATUSLINE-01 — round 9: green in the lane, 85/5 on merged main

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-status-surface.sh,plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

Full review: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r8.md`. HEAD is `da059b1`.

**Round 8 PASSED review and the reviewer re-derived every Critical by running code — keep all of
it.** The `read` here-string split is genuinely repaired with bash-3.2-safe parameter expansion and
no `mapfile`; output is byte-identical pre/post-F9 on BOTH the passthrough and the fallback path,
independently rebuilt rather than taken from the commit message; the fallback-path coverage now
exists and the reviewer mutation-proved it directly on the production file (RED with 9 named `FB-*`
assertions, clean revert, GREEN, clean `git diff --stat`); the perf gain held at ~41%. Both suites
55/0 and 90/0 in the lane. Nothing above is in question.

## [Critical] the lane is green and merged main is not — and the tests are not why

I attempted the merge into `~/Projects/leadv2` main (`42d3232`) and aborted it. Measured, same
machine, minutes apart:

```
in the lane   : test-status-surface.sh  90 passed, 0 failed
on merged main: test-status-surface.sh  85 passed, 5 failed
```

The five failures all show an unknown-status count leaking into the rendered surface:

```
FAIL: SwiftBar idle prefix                 (got: ❓7)
FAIL: R4-T2: widget title ❓1               (got: ❓8)
FAIL: R4-T3: priority                       (got: ❓8 · 🟢 0 / 🔴 1)
FAIL: R6-T1: 2 done + 1 dead -> 🔴 1        (got: ❓7 · 🟢 0 / 🔴 1)
FAIL: R6-T2: only done -> ✅ 2              (got: ❓7 · 🟢 0 / 🔴 0)
```

I checked the obvious explanation and it is **wrong**: forcing `LEADV2_LANES_ALL_REPOS=0` on merged
main still gives 85/5, so this is not the repo-scope pin.

What actually differs: `plugins/leadv2/scripts/leadv2-broad-status.sh` is **383 lines apart**
between this lane and merged main (main carries PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 round 3 plus
DISPATCH-CLOSE-GATE-01's canonical-fallback change), and `leadv2-status-collector.sh` is 8 lines
apart. This suite asserts the surface that those files render.

**Do not make the five assertions pass. Decide which side is right, with evidence, and say so in
`report.md`:**

- if merged main's `❓N` rendering is CORRECT — the surface genuinely cannot classify those lanes —
  then these five assertions encode a superseded expectation and must be rewritten against the
  current renderer, with the reasoning written down;
- if merged main's rendering is a REGRESSION — live lanes being rendered as unknown instead of
  running is the same false-dead disease the liveness prober has — then this suite is correctly
  catching it, and the finding belongs in `report.md` with the file:line, for the PULSE lane to fix.
  Do not paper over it here.

Whichever it is, prove it with a real render: point the surface at a known set of lanes, paste what
it renders on merged main and in this lane, and name the code path that produces `❓`.

Also check whether the suite reads live control-plane state rather than fixtures. A suite whose
result depends on how many lanes happen to be running is not a control — if that is the case here,
make it hermetic and say so.

## [High] `tests/run-all.sh` must be reconciled with main, not merged blind

The merge conflicts in `tests/run-all.sh`. This lane still carries the oldest `HEAD~1` fallback.
Main now carries HOOK-OUTPUT-CAP's **state-file-bounded** last-checked-SHA mechanism plus
DISPATCH-CLOSE-GATE's widened `scripts/*.sh|scripts/lib/*.sh|hooks/*.sh` glob, the
`freepool-arm.yaml` stem case, and several `EXTRA_SUITE_MAP` rows.

Keep main's block and re-apply this lane's two genuinely new pieces on top: the `test-*.sh`
self-selection case (a changed test file is its own suite) and the two
`leadv2-lane-status-line*.sh → test-statusline-readable.sh` map rows. Then prove: a docs-only HEAD
with unrelated dirt still selects this lane's suites, and a clean HEAD with one unrelated dirty file
selects only that file's own suite.

## [Low] carried

`LC_ALL` is still hard-exported in both scripts (it has an env override). The round-8 commit message
carries a minor count discrepancy. Fix or state in `report.md`; neither blocks the merge.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

`test-status-surface.sh` green **on top of merged main** with the `❓` question answered by evidence
rather than by editing assertions until they pass, a reconciled `tests/run-all.sh` with both
selection properties pasted, and both suites' counts from a run on the rebased lane.
