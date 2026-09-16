# Lead-authored brief — lane 510c9c4f (row `7ece7ffdc771`, GROUP-C-JOURNAL-HONOURS-THE-PINNED-ROOT-01)

This brief exists because the lane was killed mid-build by an explicit founder stop order on
2026-09-15, leaving its `build` phase at `status=running` with no `plan`/`gate1` prefix recorded.
It is not a re-plan: the plan was already settled by the Wave-0 diagnosis, and this records it.

## Subject and scope
One red suite — `plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh`, 4 of 6 cases
failing. One subject — `plugins/leadv2/scripts/leadv2-journal.sh`. Write set is those two files plus
the lane's report. Nothing else.

## The mechanism, already located with a control
Decision site `leadv2-journal.sh:48`. Precedence is `CLAUDE_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` →
`LEADV2_PROJECT_ROOT` → cwd, passed down to state-path at `:81-90`. At runtime an inherited
`CLAUDE_PROJECT_ROOT` beats an explicit `LEADV2_PROJECT_ROOT` pin. The Wave-0 probe controls it:
unsetting the two `CLAUDE_*` variables moves this face and no other. Full evidence:
`docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md`, Face 2.

## The decision the lane must make first
The suite is internally inconsistent about its own environment. Case `(b)` asserts a
`LEADV2_PROJECT_ROOT` pin is honoured but never clears the inherited `CLAUDE_*` variables; cases
`(a)` and `(a2)` are negative controls asserting the opposite — that the newer rung must not
override an explicit `CLAUDE_*` pin. The lane states the contract it is enforcing in one sentence at
the top of its report, then makes the suite assert exactly that contract.

Context that makes this non-academic: `persona-engine/.claude/settings.json` exports
`LEADV2_PROJECT_ROOT` in its `env` block, so every session started there carries that root into a
lane dispatched anywhere else.

A second, independent failure — the ephemeral key format versus the suite's old bare-key
expectation — needs its own negative control.

## Work already on the lane branch
`worktree-7ece7ffdc771` carries `1179c2aa test(GROUP-C): isolate journal root fixture` on top of the
anchor. It has not been reviewed and no negative control has been recorded for it. The resumed lane
owns both.

## Standing rules
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. In particular: never make the suite green by
deleting an assertion or loosening a matcher; one negative control per independent claim, run, with
both outputs pasted; every count carries its boundary.

## Acceptance
```
cd ~/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-journal-honours-the-pinned-root.sh >/dev/null 2>&1
```
Red at dispatch time.
