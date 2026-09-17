# RESUME-AND-PLACEMENT-GROUP-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**Two filed rows, one lane**, because both edit the placement/resume path in
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` and cannot run in parallel:

- `LANE-PLACEMENT-PIN-RESUME-CWD-AND-PROMPT-PIN-STILL-RED-01` — the half `GROUP-A1` left behind;
- `RESUME-LANE-REJECTS-AN-ABSOLUTE-MISSION-PATH-01` (`bbcaf87297fc`).

Read `docs/handoff/GROUP-A1-ABSOLUTE-MISSION-PATH-AND-LANDED-AT-SPAWN-01/` first. A1 rewrote
`_resolve_pinned_placement` (`:1286-1330`) and touched `_resume_mission_visibility_preflight`, landed
as leadv2 `2b7cb123`, and fixed only its sibling suite. **Do not re-derive what A1 already
established, and do not undo it** — its other suite, `test-landed-at-spawn`, is green on main and
must stay green. Run it before and after as a regression check, and paste both.

## Row one — placement pin, three cases still red

Measured on main at `2b7cb123` (not in a lane): `test-lane-placement-pin.sh` rc=1, pass=28 fail=3.

```
[TEST] FAIL: P-b: dispatch exited 3 (expected 0)
[TEST] FAIL: P-b: worker cwd='' != RESUME='/private/tmp/leadv2-lpp-*/target/.claude/worktrees/RESUME-ME-01'
[TEST] FAIL: P-h(b): prompt pin line MISSING with --worktree
```

The second one carries the diagnosis if you read it precisely: the worker's cwd is **empty**, not
wrong. A wrong path means placement was computed and misapplied; an empty one means it was never
applied. Those need different fixes, and the distinction survives only if you keep reading it that
way — do not summarise it as "wrong cwd".

`P-b` fails twice (exit 3, then the cwd), so establish whether the empty cwd is the *cause* of exit
3 or its *consequence* before touching either.

## Row two — resume refuses an absolute mission path

With `--resume-lane`, an `@mission` given as an **absolute** path is refused as *"is absent from both
lane worktree=… and main"* while the file demonstrably exists on disk in the lane worktree, in the
lane branch (`git cat-file -e HEAD:<rel>`), and on main. The resolver evidently joins the absolute
path onto the worktree root instead of detecting that it is already absolute.

Measured 2026-09-15: two resumes (`6be47851`, `7344367e`) refused identically and cost ~30 minutes of
lane time each; both proceeded once the same mission was passed repo-relative. **The non-resume
dispatch path accepts the absolute form**, so the two entry points disagree — which makes "which one
is right?" a question you must answer explicitly rather than making them agree in whichever
direction is easier.

Related trap, already paid for: `--resume-lane` takes a value (`_LV2_PIN_NEEDS_VALUE=1` at `:413`),
so passing it bare swallows the next argument silently. If your fix touches argument parsing, a bare
`--resume-lane` must fail loudly rather than eat its neighbour.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A case that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do **not** touch `plugins/leadv2/scripts/leadv2-active-registry.sh` or
  `plugins/leadv2/scripts/leadv2-review-run.sh` — other lanes hold both.
- `test-landed-at-spawn` is green on main. Making it red is a failure of this lane regardless of
  what else turns green.

## Controls

Two independent claims → **two** negative controls, each RUN, both outputs pasted. The second one
must prove the absolute-path resolution specifically: mutate the is-absolute detection and confirm
the resume refusal returns. Apply each mutation inside the function body **in the lane worktree**,
never a scratch copy. Assert the mutation target string is present before running, so a control
cannot rot into a permanent green.

## Deliverable

`docs/handoff/RESUME-AND-PLACEMENT-GROUP-01/report.md` — the cause/consequence verdict on `P-b`,
which entry point you made authoritative for absolute mission paths and why, before/after counts for
both suites **plus** `test-landed-at-spawn` as a regression check, with their boundary (counts,
ceiling, platform, commit), both controls with pasted output, and any case left red with its cause.
