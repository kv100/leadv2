# ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01 — diagnosis only, no production fix

Row `bf0dd16f7c9e`. This is a **diagnosis lane**. You are forbidden from changing any production
script in this lane. Your deliverables are a report and a re-runnable probe script. A lane that
"fixed it along the way" has destroyed the measurement it was dispatched to take.

## The question, in one sentence
Four independent failures observed in a single day all smell like "which root/path is this?" —
**are they one defect with four faces, or four separate causes that happen to share a vocabulary?**

The answer decides how twelve red suites get fixed: one lane, or three. Either answer is a result.
"Probably related" is not an answer; "they are four causes, here is each mechanism at file:line" is.

## The four faces, with what is already known about each

### Face 1 — `--resume-lane` refuses an ABSOLUTE `@mission` path
Reproduced twice today, cost ~30 minutes. Dispatching a resume with
`@/Users/.../Projects/leadv2/docs/handoff/X/mission.md` is refused with
`mission is absent from both lane worktree and main`, while the file exists **on disk, in the lane
branch, and on main**. Passing the same path **repo-relative** works. The dispatcher appears to join
the given path onto the worktree root unconditionally.
Owning row: `RESUME-LANE-REJECTS-AN-ABSOLUTE-MISSION-PATH-01`. Suite: `test-lane-placement-pin.sh`.

### Face 2 — the journal does not honour the pinned root
Suite `test-journal-honours-the-pinned-root.sh`, red on main. Subject `leadv2-state-path.sh`.

### Face 3 — `landed-at-spawn` / target-repo keying
Suite `test-landed-at-spawn.sh`, red on main. Same subject file as Face 2.

### Face 4 — refusals that mismatch inside a FOREIGN project root
`test-stop-gate.sh` fails on the named case `foreign-repo-journaled`.
`test-dispatch-refusal-truth.sh` D2 still mismatches inside a foreign root (row
`DISPATCH-REFUSAL-D2-STILL-MISMATCHES-INSIDE-A-FOREIGN-ROOT-01`). Subjects:
`leadv2-dispatch-product-close.sh`, `leadv2-dispatch-code.sh`.

### The macOS wrinkle that may or may not be a fifth face
`mktemp -d` returns `/var/folders/...` while `realpath` of the same directory returns
`/private/var/folders/...`. They are the SAME directory. Any comparison that pits a raw `mktemp`
path against a `realpath`-normalised one reads "different root" for a path that is not different.
**Do not assume this is the cause.** Prove it fires on a specific comparison, or rule it out.

## Prior art you must read before forming a hypothesis
"Which repository am I in" already has a measured answer in this codebase, from 2026-09-06: it is
answered by **four independent authorities**, not one.

1. **Phase store** — `leadv2-phase-record.sh`, reads `LEADV2_PROJECT_ROOT`.
2. **Journal** — `leadv2-journal.sh:14`, reads `CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR`.
3. **Event log** — `leadv2-event.sh:17`, reads `LEADV2_EVENT_LOG_DIR`, defaulting to the LIVE path,
   so the fail-open lives in the default rather than in a missing variable.
4. **The lane worktree / registry pin** — obeys none of the three.

`persona-engine/.claude/settings.json:73` exports `LEADV2_PROJECT_ROOT` in its `env` block, so every
session started in persona-engine carries that root into a lane dispatched anywhere else.

This is your starting map, not your conclusion. The useful question is: **does each of the four
faces resolve its root through a DIFFERENT one of these authorities, or do several go through the
same one?** Two faces sharing an authority is evidence for "one defect". Four faces on four
authorities is evidence for "four defects".

## Method — non-negotiable order
1. **Reproduce each face independently, from main, before reading any fix-shaped code.** A face you
   cannot reproduce is reported as not-reproduced, with the command and the output. It does not get
   a cause.
2. For each reproduced face, **find the exact line that makes the wrong decision** and quote it as
   `file:line`. Not the function, not the file — the line, with the comparison it performs and the
   two values it compares at runtime. Add a temporary trace if you need one; strip it before you
   finish, and say in the report that you did.
3. **Then, and only then**, ask whether two faces meet at the same line or the same authority.
4. Write a **probe script** `plugins/leadv2/scripts/tests/probe-root-path-resolution-census.sh`
   that reproduces every face you reproduced, one named case per face, printing `FACE-n RED` or
   `FACE-n GREEN` with the two values that were compared. It must be re-runnable by the next lane
   as its before/after instrument. Sandbox everything it touches; it must never write into a real
   `~/.claude/leadv2-state/` directory or a real repo.

## Negative controls
**One control per independent claim, not one for the whole report.**
- If you claim "Face 1 is caused by path joining at `X:NNN`", the control is: make that join a no-op
  in a scratch copy, show the refusal disappears, revert. Paste both outputs.
- If you claim "the `/var` vs `/private/var` divergence does NOT fire here", the control is a case
  that WOULD fire if it did — show it staying green.
- If you claim two faces share a cause, the control is that a single mutation at the shared line
  moves BOTH faces, and that a mutation at a line unique to one face moves only that one. That
  double-ended control is the whole point of this lane; without it "one defect" is a hunch.

## What counts as failure of this lane (and is acceptable)
- "I reproduced 2 of 4; the other 2 do not reproduce on macOS at this ceiling" — a real result.
- "They are four causes" — a real result, and the more expensive one for the plan. Report it
  plainly; do not shade toward "one defect" because one defect is cheaper for us.
- Silently making a suite green. That is the one outcome that makes this lane worthless.

## Boundaries
- **No production script may be modified.** `git status` at the end must show only your report and
  your probe script. If you needed a scratch mutation, it happened in a copy under `/tmp` or in a
  scratch worktree, and it is reverted.
- Every count in the report carries its boundary: how many faces, of how many, at what ceiling, on
  which platform (macOS Darwin 25.6.0), from which commit.
- The census this comes from is `docs/handoff/MAIN-RED-SUITES-CENSUS-01/report.md` (27 red of 93
  selected, 120s ceiling, macOS) and the plan is `fix-plan.md` beside it. Read both.

## Deliverables
1. `docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` — the verdict, one section
   per face, each with: reproduction command, observed output, mechanism at `file:line`, the two
   runtime values compared, the authority it resolves through, and its negative control with both
   outputs pasted. Then a closing section: **one defect or four**, with the double-ended control.
2. `plugins/leadv2/scripts/tests/probe-root-path-resolution-census.sh` — the re-runnable instrument.

The report's last line must be one of exactly these, and nothing else:
`VERDICT: ONE DEFECT` / `VERDICT: N DEFECTS (n=<number>)` / `VERDICT: INCONCLUSIVE (<what is missing>)`.
