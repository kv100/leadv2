FOLLOW-UP to CODEX-CONFIG-GROWS-FOREVER-01 (lane 2f652446). The work is good and nearly done:
`leadv2-codex-config-prune.sh` (225 lines), the `leadv2-lane-worktree.sh` change, and a 144-line
suite are committed and 15 of 16 assertions are green. **One assertion is RED and it is the one
that encodes the actual requirement.**

REPO: ~/Projects/leadv2, branch `worktree-2f652446` (your own lane, already checked out).

## The red assertion

    plugins/leadv2/scripts/tests/test-codex-config-prune.sh:89
    FAIL: identical live aliases collapse to physical entry
      result.returncode == 0 and count() == 1
      and str(live.resolve()) in tomllib.loads(cfg.read_text())['projects']

Two `[projects."…"]` tables describe the SAME physical directory under two spellings (one through
a symlink alias, one the resolved real path) and carry the SAME policy. They must collapse to a
single table keyed by the resolved physical path. Today they do not, so the config still grows one
table per spelling — which is the whole defect the mission exists to kill. The adjacent
`conflicting live policies untouched` assertion is green and must STAY green: collapsing is only
allowed when the policies agree; a genuine conflict is retained and counted.

## What to do
1. Make `:89` pass without breaking the other 15. Resolve each live path before comparing, and key
   the surviving table by the resolved path.
2. Do not weaken the test to make it pass. If after investigating you believe the assertion itself
   is wrong, STOP and say so with the reasoning — do not edit the assertion and call it green.
3. Re-run the full suite and paste the final `test-codex-config-prune: N passed, M failed` line.

## Negative control (E2E-KILLRATE-01)
Inside the collapse function's body, drop the resolution step so the two spellings stay distinct.
The suite must go red on the COUNT of surviving tables (`count() == 1`) — the value that has never
varied — not on a log string. Insert INSIDE the body, never at top level. Show it red, restore,
show it green.

## Constraints
- Touch ONLY `plugins/leadv2/scripts/leadv2-codex-config-prune.sh` and, if strictly required,
  `plugins/leadv2/scripts/leadv2-lane-worktree.sh`. Nothing else.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-codex-config-prune.sh, plugins/leadv2/scripts/leadv2-lane-worktree.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-71878cb4" "<question>" \
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