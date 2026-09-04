verdict: APPROVE
next_action: continue

# HEAVY-TIER-VS-SAFETY-OPUS-01 — dispatch-d552b9ab developer report

## Status found at dispatch start

The lane worktree (`.claude/worktrees/HEAVY-TIER-VS-SAFETY-OPUS-01`, branch
`worktree-HEAVY-TIER-VS-SAFETY-OPUS-01`) already carried the full fix, committed
in two prior rounds on this same branch:

- `99b4f865` — round 1: split Heavy think-tier from tag-forced safety route.
- `97ea25aa` — lead adjudication doc for round 2 (`docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/fix-round-2.md`).
- `74f4cfcc` — round 2: hard-safety tag pin outranks the Heavy think tier; `arch` carved out.

`docs/handoff/dispatch-d552b9ab/` (this dir) did not exist before this dispatch —
no prior developer deliverable for this exact dispatch id. No uncommitted diff
existed in `plugins/leadv2/` at dispatch start (`git status --short -- plugins/leadv2/`
empty). This developer run is therefore a fresh verification + census pass, not
a re-implementation.

## (A) vs (B) — restated from the already-landed adjudication

Both failing assertions from the CI brief are **(B)**, not (A), per
`docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/fix-round-2.md` (the lead's round-2
ruling, itself grounded in `docs/model-routing.md:95` — "review/critic → Sonnet
critic (Opus if safety-touched)" — and `PLANNER-MODELS-DECISION-01` for the one
carve-out):

1. `Heavy -> Claude Opus` (plain Heavy, no tag): **(A)** — stale doctrine. Heavy
   as a class is the *think* tier now (`FABLE-THINK-TIER-01`), correctly fable.
   This assertion was already updated in round 1 and stays fable.
2. `high-risk tag blocks explicit Codex` (the actual failing case: Heavy class +
   a hard-safety tag): **(B)** — the suite was right that this must be opus.
   Round 1 initially routed it to fable (class check fired before the tag
   check); round 2 fixed the *routing*, not the assertion, by moving the
   safety-tag check above the class check in
   `plugins/leadv2/scripts/leadv2-session-route.sh` (now lines 225-262), with
   `arch` carved out because it names difficulty, not consequence, and
   `PLANNER-MODELS-DECISION-01` deliberately keeps Heavy architecture on the
   think tier.

This is a split, exactly as the brief anticipated: (A) for bare Heavy, (B) for
Heavy+hard-safety-tag.

## Fresh verification (this dispatch)

```
$ bash -n plugins/leadv2/scripts/leadv2-session-route.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-session-route.sh && echo OK
OK
$ bash plugins/leadv2/scripts/tests/test-session-route.sh
[TEST] PASS: router syntax
[TEST] PASS: routine Standard -> GLM (GLM-FIRST-01)
[TEST] PASS: Light -> GLM (GLM-FIRST-01)
[TEST] PASS: Heavy (think tier) -> Claude fable
[TEST] PASS: high-risk tag blocks explicit Codex
[TEST] PASS: Heavy + safety tag -> opus (safety outranks think tier)
[TEST] PASS: Heavy + arch tag stays think-tier (arch carve-out)
[TEST] PASS: Standard + safety tag pins opus
[TEST] PASS: Standard + arch tag pins opus
[TEST] PASS: Codex quota threshold -> Claude fallback (GLM+kimi unavailable)
[TEST] PASS: missing Codex CLI -> Claude fallback (GLM+kimi unavailable)
[TEST] PASS: explicit Claude override
[TEST] Results: PASS=12 FAIL=0
exit=0
```

No Python files in the lane's changed scope (`git diff --stat c528a137..74f4cfcc
-- plugins/leadv2/` — only `leadv2-session-route.sh` and
`tests/test-session-route.sh`), so no `py_compile` needed.

Linux-container green (python:3.12-slim, GNU bash 5.2.37, Python 3.12.14,
PASS=12 FAIL=0 exit=0) and the negative-control mutate/revert (reverting the
reorder → PASS=11 FAIL=1 on Heavy+safety; dropping the `arch` carve-out →
PASS=11 FAIL=1 on Heavy+arch; both reverted back to green) were already run and
recorded in round 2 — see commit message `74f4cfcc` and
`docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/report.md` lines 60-72. Not re-run
here since the routing code has not changed since that evidence was captured
(verified via the `bash -n`/test run above, byte-identical result).

Lane-scope diff (unchanged from round 2, re-confirmed clean):

```
$ git diff --stat c528a137..74f4cfcc -- plugins/leadv2/
 plugins/leadv2/scripts/leadv2-session-route.sh     | 48 +++++++++++++++-----
 plugins/leadv2/scripts/tests/test-session-route.sh | 51 ++++++++++++++++++++--
 2 files changed, 86 insertions(+), 13 deletions(-)
```

## Census (item 5) — extended this dispatch

Round 2's report already found one second instance
(`leadv2-admission-class.sh:57-77`, class-check-instead-of-tag-check shape;
flagged, not fixed, cross-lane surface). Re-running the census this dispatch
(grepping for other callers that resolve a safety decision through anything
other than the tag-based safety pin) turned up a **third** instance, of a
different shape — a correctly-firing tag check that still lands on the wrong
model:

`plugins/leadv2/scripts/leadv2-route-bandit.sh:561` and `:565`
(`cmd_select_for_workflow`, the live `select-for-workflow` subcommand called
from `plugins/leadv2/hooks/leadv2-bandit-preflight.sh` and documented as a
real pre-spawn model chooser in `skills/leadv2-plan/SKILL.md` and
`skills/leadv2-review/ref/route-bandit-step0.md` — not dead code):

```
[[ "$safety" == "true" ]] && default_critic="${think_model:-sonnet}"
```

`think_model` resolves through the same `lib/leadv2-think-model.sh` as
`CLAUDE_HEAVY_MODEL` (fable; opus only on the resolver's own failure). So a
plan/review phase invoked with `--safety true` picks the critic's *default*
arm from the think tier rather than pinning opus — contradicting
`docs/model-routing.md:95`: "review/critic → Sonnet critic (Opus if
safety-touched)". Full writeup appended to
`docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/report.md` ("Round-3 addendum").

Two of three known instances now share the same failure mode (safety-tagged
decision defaults to the think tier instead of Opus) in two different files —
that is a pattern, not a one-off, and per the brief the census belongs in the
report rather than an uncoordinated fix. **Not fixed here**: `leadv2-route-bandit.sh`
has its own test suite (`tests/test-leadv2-route-bandit.sh`) and two live
skill-level callers; this task's brief scopes the code fix to
`leadv2-session-route.sh`'s two failing assertions specifically. Recommend the
lead consider a shared "safety pins opus, `arch` excepted" helper both scripts
call, instead of each caller re-deriving the rule (as already suggested for the
admission-class.sh finding).

## What was and wasn't changed this dispatch

- Changed: appended the round-3 census addendum to
  `docs/handoff/HEAVY-TIER-VS-SAFETY-OPUS-01/report.md` (not a runtime-state
  path; not `docs/handoff/dispatch-nw*`).
- Not changed: `plugins/leadv2/scripts/leadv2-session-route.sh`,
  `tests/test-session-route.sh` — already correct and green from round 2, no
  further fix needed for the DoD's two failing assertions.
- Not changed: `leadv2-route-bandit.sh`, `leadv2-admission-class.sh` — both
  flagged findings, deliberately left for the lead per the reasoning above.

## Self-check (MD-01..MD-05)

- MD-01: multi-step mission, full detail is in this file, not the 50-word summary. OK.
- MD-02: no `context.yaml` exists for this task id (checked, absent) — nothing to cite/contradict.
- MD-03: not a prompt paste-back — this documents fresh verification + a new finding.
- MD-04: `git diff` for the DoD-relevant scope pasted above (clean, matches round 2).
- MD-05: `leadv2-route-bandit.sh:561,565`, `docs/model-routing.md:95`,
  `leadv2-bandit-preflight.sh` all grep-verified to exist before being cited above.

## Commit

Committed the report addendum on this lane branch
(`worktree-HEAVY-TIER-VS-SAFETY-OPUS-01`) before ending this session — see git
log for the commit hash following this deliverable.

DELIVERABLE_COMPLETE
