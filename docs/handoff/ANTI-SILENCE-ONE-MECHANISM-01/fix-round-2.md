# ANTI-SILENCE-ONE-MECHANISM-01 — round 2: the beat is still fully silent on merged main

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-ONE-MECHANISM-01/

**Round 1 is merged as `b2175f6`. Rebase this lane onto current main before doing anything** —
your branch point is older than main's `leadv2-broad-status.sh`, and that is the whole problem
this round is about.

Round 1's `_live_lane_facts` is right and stays. I proved it: replacing `lane_facts="$(_live_lane_facts)"`
with `lane_facts=""` turns your suite red, restoring it turns it green.

## [Critical] the same suite fails on merged main

```
test-beat-stamp-agreement: 5 passed, 1 failed
FAIL: T3a: stamp mismatch: at= line1=
```

Both values are **empty** — not mismatched, absent. No ready line, no artifact.

Your lane branched before main's bash-3.2 heredoc fix (`67f8b8d`), which replaced
`RENDER_JSON="$(python3 - ... <<'PY' ... )"` with `cat >"$RENDER_TMPDIR/render.py" <<'PY'`. Main
kept its (correct) version through the merge, so round 1's fix landed on a render path it was
never tested against.

I reproduced it directly against merged main with a collector that prints non-JSON:

```
Traceback (most recent call last):
  File ".../render.py", line 17, in <module>
    snapshot = json.load(open(snapshot_path, encoding="utf-8"))
FileNotFoundError: [Errno 2] No such file or directory: '.../repo/docs/leadv2/status-snapshot.json'
--- artifact ---
NO ARTIFACT
```

A beat fired, the render died, and **nothing was written at all** — no degraded artifact, no
ready line, no failure line. That is the founder's complaint, alive on main today: a beat that
fires and says nothing is indistinguishable from a beat that never fired.

Note that `leadv2-broad-status.sh:1293-1301` *looks* like it handles this — it logs
`render failure: table unavailable` and calls `_write_degraded_status` then `_emit_ready_line`.
It did not run, or it ran and wrote nothing. Find out which, from the runtime, not by reading:
re-run the reproduction above with stderr visible and trace the actual exit path. Do not fix a
hypothesis.

Two things to correct once you know:

1. every abort path — collector garbage, missing snapshot, render traceback, unwritable
   artifact — must leave either a degraded artifact plus a ready line, or a failure line with
   no `path=` token. Never nothing;
2. `:1293` stamps the log line with `$(_now_iso)` rather than `$BEAT_AT`. Round 1 unified the
   artifact's line 1; this line is still on the other clock.

## [Medium] the suite must run against main's render path

Your fixtures pass on the old path and miss on the new one. After rebasing, T3a must fail
before your fix and pass after — show both.

## Rules

- Mutation INSIDE the production function body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- A kill counts only if **this suite alone** goes red.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- Do not weaken round 1: `lane_facts=""` must still turn the suite red.
- Do not reintroduce the heredoc-in-command-substitution form; main's `cat > render.py` version
  is the fix for a real bash-3.2 parse failure.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

On merged main, a collector that returns garbage still produces a truthful degraded beat, the
suite is green there, and a mutation removing the abort-path artifact turns it red with the exit
code following.
