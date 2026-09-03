# DISPATCH-CLOSE-GATE-01 — round 9: one assertion left, and it is a small one

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-lib-source-guarded.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

HEAD is `1452937`. The lane is already rebased onto main (`42d3232`) and `tests/run-all.sh` is
reconciled — main's state-file bounding and widened glob are preserved and this lane's rows sit on
top. That part is done; do not touch `run-all.sh` again.

**Round 8 made real progress and it stays.** On a clean tree `test-lib-source-guarded.sh` is 5/0,
and the `BROAD_STATUS_ALARM_LIB` control correctly names
`plugins/leadv2/scripts/leadv2-broad-status.sh:112` when its canonical fallback is stripped.

## [High] one control still flips on someone else's violation

I ran the reviewer's own reproduction: appended one unrelated unguarded
`source "${SCRIPT_DIR}/lib/zz-unrelated-probe.sh"` to `leadv2-status-collector.sh` and re-ran.

```
clean tree                : SUMMARY: pass=5 fail=0
one unrelated violation   : SUMMARY: pass=4 fail=1
```

Round 7 had all three controls flip, so going from three to one is progress — but the requirement
has not changed: a control a stranger's commit can flip is not a control. Find the assertion that
still compares against the full finding set (or its position) rather than searching it for its own
`file:line`, and make it a containment check.

Then prove all of it in one run, pasted:

1. clean tree — GREEN with its count;
2. strip each of the guarded sources in turn — RED naming that specific file, each time;
3. append one unrelated unguarded `source` to `leadv2-status-collector.sh` — **still GREEN**;
4. remove it, `git diff --stat` empty.

That is the whole round. Nothing else is open on this lane.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production file, RED, revert, GREEN, clean
  `git diff --stat`. A suite that stays green with the fix removed is a failed control; a printed
  `RED control:` line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is
  not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop** — if you are running
  short on time, commit what works rather than leaving it on disk; three rounds were nearly lost
  that way today.

## Done means

The four runs above pasted, and this lane merge-ready into main at `42d3232`.
