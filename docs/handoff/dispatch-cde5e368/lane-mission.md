LANE-LIVENESS-ARTIFACTS-FORCE-A-95-SUITE-RUN-01. This is the root cause of every close-gate
timeout on 2026-09-07/08 — four in a row, on three different lanes, which I misdiagnosed three
times before measuring it. Two real fixes landed chasing it (`3cb4c49f`, `cd45ceb7`); neither was
this.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T07:0x-07:2xZ.

## The measurement

Lane worktrees accumulate untracked runtime artifacts in TWO places:

    docs/leadv2/.lane-liveness-share/<hash>/{rc,result,ts}
    plugins/docs/leadv2/.lane-liveness-share/<hash>/{rc,result,ts}      <-- the problem

The scope selector in `plugins/leadv2/scripts/tests/run-core-offline.sh` excludes housekeeping with
`case "$f" in *.md|docs/*) continue ;; esac` — and that pattern anchors at the START of the path.
`plugins/docs/leadv2/...` therefore does NOT match, the three files count as UNMAPPED, and a single
unmapped file trips the safety net:

    unmapped_files (3 of 7 changed files selected no suite) — cannot prove the diff is covered
    -> selected=95 total=95   -> 900s ceiling -> verdict=timeout rc=124

Same worktree (`d2823c51e670`), same command, artifacts removed by hand:

    with artifacts:  7 changed, 3 unmapped, selected=95    (900s, rc=124, no verdict)
    without them:    4 changed, 0 unmapped, selected=3     (164s, verdict=pass)

The safety net is CORRECT and must stay. Its input was lying to it.

## Two halves — do both, and say which is which in the commit

1. **The writer.** `plugins/docs/leadv2/.lane-liveness-share/` should not exist at all. It reads
   like `${ROOT}/plugins` concatenated with a path that already begins `docs/` — find the writer,
   prove the concatenation (paste the line), and make it write to the one intended location. If
   both locations turn out to be intentional, say so with the evidence and fix only half 2.
2. **The exclusion.** Housekeeping must be excluded wherever it sits, not only at the path root.
   Match the `.lane-liveness-share` artifact directory (and `docs/` at any depth) rather than only
   a leading `docs/`. Keep it narrow: this must not become "ignore anything with docs in the name",
   which would let a real source file under some future `plugins/docs-tool/` slip past the coverage
   proof. The whole value of that safety net is that it refuses to guess.

Fixing only half 2 leaves stray files being written forever, and one day they will land somewhere
the pattern does not cover. Fixing only half 1 leaves the selector still blind to nested docs.

## Acceptance
acceptance:
  surface: command_output
  observable: in a lane worktree where the artifacts are PRESENT (do not delete them — that is the
    workaround, not the fix),
    `LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed`
    prints `unmapped=0` and a small `selected=`, not `selected=95 … reason=unmapped_files`. Paste the
    SCOPE_RESULT line. Separately show that a genuine unmapped SOURCE file still forces the
    full-set fallback — add one, show `selected=95`, remove it. Without that second half the fix
    cannot be distinguished from breaking the safety net.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the body of the function you changed, restore the leading-anchor exclusion. The suite
   must go red on `SCOPE_UNMAPPED_COUNT` / `selected=` — the values under test — not on a log
   string.
2. Inside the same body, widen the exclusion to swallow everything (e.g. skip every path). The
   suite must go red on the genuine-unmapped-source case: a selector that never falls back has
   stopped proving coverage, which is worse than the bug.
Insert each mutation INSIDE the function body, never at top level. Self-register with
`# run-all-triggers: run-core-offline` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`.

## Constraints
- Touch `plugins/leadv2/scripts/tests/run-core-offline.sh`, the artifact writer you identify, and
  your new suite. Nothing else.
- Do NOT touch `tests/run-all.sh`, `leadv2-phase8-e2e-gate.sh`,
  `tests/test-status-surface-single-lead.sh` (a sibling lane owns that one),
  `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`.
- Do NOT change the fallback POLICY — "cannot prove coverage ⇒ run everything" stays exactly as it
  is. You are fixing what counts as a coverable file, nothing else.
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-cde5e368" "<question>" \
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