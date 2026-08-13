# ARM-PRODUCES-NOTHING-01 — fix round 1: the probe is never defined at call time

**Repo: `~/Projects/leadv2`. Resume the EXISTING work in lane worktree
`.claude/worktrees/621328a0` — do not start over, the design is right and the tests are
right.** Branch only, no commit to main, no push, no merge.

## What is wrong (measured, not theorised)

Your own suite `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` fails, and the
reason is in its output verbatim:

```
leadv2-dispatch-product-close.sh: line 1267: pc_silent_arm_probe: command not found
```

`pc_silent_arm_probe()` is defined at **line 991** and called at **line 1267**, both at top
level of the same file, so plain top-to-bottom sourcing would have defined it. It is not
defined at the moment of the call — so the call at 1267 is NOT running in the same shell
pass that reads line 991. Find out why before changing anything. Likely candidates, in the
order worth checking:

1. The script re-executes or re-enters itself for the gate stage (a second `bash "$0"`, an
   `exec`, or a subshell that reads only part of the file), so the call happens in a context
   where the later definition was never sourced.
2. There is an early `exit` / `return` on the path that reaches 1267, and 1267 is reached by
   a different entry point than the one that passes 991.
3. The call site sits in a block that runs while the file is being read in a mode that stops
   short (e.g. a `sourced` guard).

State in your deliverable WHICH of these it actually is, with the line numbers. Do not
"fix" it by moving the definition higher and leaving the cause unknown — if the call site
runs in a re-entered context, other helpers you rely on (`_pc_stat_mtime`,
`_pc_next_arm_in_chain`) have the same problem and will fail the moment the probe returns
rc0.

## Current failures to turn green

- Case 1: expects `arm_produced_nothing`, gets `no_work / empty_diff`.
- Case 2: expects `landed`, gets `refused / unscoped_lane_work` — a lane with REAL work is
  being blocked. This one matters most: it means the probe path is interfering with the
  healthy case.
- Case 4: stale stream should classify as silent, does not.

## Keep

The design in the existing diff is correct and reviewed: rc0 requires all three of
(no stream / zero assistant events) AND (stream not fresh, `LEADV2_PC_SILENT_GROWTH_S`
default 60s) AND (lane worktree clean), and any inability to prove silence fails OPEN. Do
not weaken any of the three, and do not weaken a fixture to get green.

## Rules

- bash 3.2. No `declare -A`, no `${var^^}`, no `mapfile`, no `<<<`.
- Symlinked into three repos — a regression breaks dispatch everywhere.
- `.env` READS only. No commit, no push.

## Done means

- `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` fully green, pasted in
  full.
- `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` still green (the
  unscoped-lane-work path shipped this morning must be untouched) — paste it.
- `bash -n` and `/bin/bash -n` clean on both scripts.
- Do NOT run `run-core-offline.sh`.
