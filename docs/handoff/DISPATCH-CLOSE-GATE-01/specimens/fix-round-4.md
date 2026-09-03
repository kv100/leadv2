# ANTI-SILENCE-STATUSLINE-01 — fix round 4 (review said FAIL / do_not_merge)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/round4-red/,docs/handoff/ANTI-SILENCE-STATUSLINE-01/render-proof.md

Six commits, HEAD `981ca1b`. Full report:
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r3.md`.

**The behaviour is right now.** Confirmed by an independent run:
- **F4 is FIXED**: a dead lane is first at W=22..200, and the output is identical across three
  different input orders — the sort is total.
- **F3 is FIXED**: 35 of 35 Cyrillic tail renders reconcile `shown + N == total`. The
  `7 hidden, +3` from round 2 is gone.
- Suite: `pass=37 fail=0 skip=0`.

**The problem is that almost none of it is protected.** Nine mutations, four held, **five survived
green**. The suite grew from 17 to 37 assertions and most of the new ones cannot fail.

## [Critical] the controls are decorative — five fixes have no guard

| Mutation | What it breaks | Suite |
|---|---|---|
| MUT-R | the entire rank fix reverted | still PASS |
| MUT-B | marker length sweep | still PASS |
| MUT-Z | tail `+N` reservation | still PASS |
| MUT-V | tail dropped-count off-by-one | still PASS |
| MUT-U | ANSI strip before base clip | still PASS |
| MUT-W | `full_label_cap` | still PASS |

**MUT-R is the worst of these.** F4 — the founding incident, a dead lane losing its slot — can be
fully reverted and the suite still passes. The behaviour is correct today and completely
unprotected tomorrow.

The reason is visible in MUT-B's "control": it is `grep -q 'marker_len=${#marker}'` — an
assertion that the *source text contains a string*, while the runtime sweep result is computed and
thrown away. Break the behaviour, leave the literal in a comment, suite stays green, and W=20/21/34
render over budget.

**Every one of these must become a behavioural assertion**: run the renderer, read its output,
assert on what it produced. Then break the code each one guards and show it RED. A `grep` against
the script text is never a control — this is the third round that rule has been stated, and the
first time the reason is this concrete.

Held, for reference — these four are real and show the shape to copy: MUT-X (composer trailing
space), MUT-C (composer marker), MUT-Y (tail char-measure).

## [High] three new behaviour bugs

1. **`lanes 3: +3` with no dead lane at COLUMNS=20.** At the narrowest width every lane collapses
   into the counter and the dead one disappears — F4's own requirement, violated at the width
   where it matters most. Something must always be shown, even if it is only the urgency class.
2. **Value corruption**: the composer renders `·dead·9` for an age of `9m`. The unit is being
   cut off, so nine minutes and nine hours are indistinguishable.
3. **The no-user-command branch strips ALL ANSI at every width** — `vis=149` at W=200. Colour is
   the fastest signal for "something is wrong" on this line; do not strip it when it fits.

## [High] F5 / F7 / F8 are byte-identical to round 2, and F9 is worse

F5 (base raw-sliced mid-word, colour lost), F7 (width assertion allows slack by measuring ANSI
bytes), F8 (the inert skip) were not touched. F9 regressed: **139 ms tail / 122 ms composer**,
because `_surf_visible_len` now forks **twice per removed character**. This runs on every
statusline render. Compute visible length without a subprocess.

## [High] `--scope changed` selects neither statusline suite

The `HEAD~1..HEAD` fallback needs a fully clean tree, and a lane's control plane is always ~21
files dirty — so in a lane the selection silently degrades to nothing. That is not a mapping
problem, it is a fallback that cannot work where it is used. Make selection work from a dirty
tree, or select on the committed range explicitly.

## [Medium] artifacts

`round3-red/` was never created, and `render-proof.md` is untracked and stale (`pass=16`). Both
were required. `docs/handoff/` is gitignored, so copy the proof to the main checkout as well.

**Write set note (corrected):** the first dispatch of this round omitted the
`docs/handoff/ANTI-SILENCE-STATUSLINE-01/` artifact paths from LANE_WRITES while the brief
demanded artifacts there, and the worker correctly stopped and said so rather than writing out of
scope. That was the lead's error. Commit `e49441c` (narrow incident payloads) is already in the
lane and is kept — resume from it.

## Rules

- **A control is a behavioural assertion on rendered output.** No `grep` against script source.
  After writing each one, break the code it guards and confirm RED.
- Do not weaken an assertion to make a fix pass.
- No subprocess per character. This script runs on every render.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

All six mutations in the table above go RED under their own controls (paste every RED and GREEN,
logs under `round4-red/`), the three new behaviour bugs fixed with controls, F5/F7/F8 addressed or
disputed with evidence, render time back under ~60 ms, `--scope changed` selecting both statusline
suites from a dirty tree (output pasted), and `render-proof.md` regenerated and copied to the main
checkout.
