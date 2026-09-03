# ANTI-SILENCE-STATUSLINE-01 — round 5 (review said fail / BLOCK, 3 Critical + 5 High)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-status-surface.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,plugins/leadv2/scripts/tests/test-status-surface.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

Full report: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r4.md`. Read it before touching
anything.

Fixed and kept: the three round-4 behaviour bugs (dead lane visible at W=20, the `9m` unit no longer
truncated to `9`, ANSI preserved at widths where it fits) and F7. Good work — but the protection
story got worse, not better, and that is the whole reason round 4 existed.

## [Critical] the new controls are self-satisfying — they pass *because* the fix is gone

This is a new and worse failure than round 3's decorative greps, so read it carefully.

The round-4 controls `sed` a **scratch copy** of the script and then assert that the copy renders
badly. When the real fix is already absent from production, the `sed` finds nothing, no-ops, and
the **already-broken production output satisfies the assertion**. The control reports PASS at
exactly the moment it should scream:

```
[PASS] MUT-W RED: fixed label cap truncates wide rendered identity
[PASS] MUT-V RED: tail dropped count no longer reconciles
```

MUT-U is worse still: it prints `AssertionError: MUT-U target missing` into its own log and passes
anyway.

A mutation control must (a) verify the mutation actually applied — a `sed` that matched zero lines
is a hard failure, not a skip — and (b) assert against the **production** code path, not a scratch
copy that has drifted from it. Rewrite every one of these on that basis.

## [Critical] MUT-R still survives — the founding incident is still unprotected

Fully reverting the rank fix at `leadv2-status-surface.sh:1681-1688` leaves
`test-status-surface.sh` at `69 passed, 22 failed` — **byte-identical to baseline** — and the F4
case still prints PASS with identical output. `grep -n "MUT-R\|rank=" plugins/leadv2/scripts/tests/*.sh`
returns nothing: no control was ever added for it.

F4 is the incident the founder actually reported — a dead lane losing its slot on the one status
surface that does not depend on me. It has now survived two rounds of "fixed". It needs a control
that goes RED on that revert, and `test-status-surface.sh` is red at baseline (22 failures) — so
fix the baseline too, or the suite can never grade anything.

## [Critical] MUT-B / MUT-Z / MUT-U / MUT-W still survive in production

Applied to the real script, `test-statusline-readable.sh` stays at `pass=41 fail=0 skip=1`,
identical to baseline. MUT-V goes red only via MUT-Z's control, not its own. Four of the six
mutations round 4 was dispatched to protect are still unprotected.

## [High] F5 unfixed, and the shipped proof demonstrates the bug

`leadv2-lane-status-line.sh:289` still does `_base_out="${_base_out_plain:0:$_base_visible_budget}"`
— a raw byte slice. Measured output: `O`, `Opu`, `Opus 5 `. And `render-proof.md` ships
`lanes 5: …·dead·9m O` **as its proof of correctness**. Fix the slice to be visible-width aware,
and regenerate a proof that does not contain the defect.

## [High] F9 — still 99.6 ms tail / 89.6 ms composer against a ~60 ms bar

Per-character forking is gone, but `$( )` per token remains. Bare bash floor is 5.1 ms, so the
budget is real. This runs on every render.

## [High] `--scope changed` selects one suite of two

`test-status-surface.sh` — the home of F4 and MUT-B — is not selected from the dirty lane, and is
red at baseline. Both must be fixed: selection, and a baseline that means something.

## Rules

- **A mutation control must fail when the mutation is applied to production.** Verify the mutation
  applied (zero-match `sed` = hard failure), assert against the production path, never a scratch
  copy. This one rule is what round 5 is for.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  ignores it).
- Every fix keeps a control you RUN: RED, revert, GREEN. Logs in
  `docs/handoff/ANTI-SILENCE-STATUSLINE-01/round5-red/`.
- Bash 3.2.57 only.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

MUT-R, MUT-B, MUT-Z, MUT-V, MUT-U and MUT-W each go RED under their own control **with the mutation
applied to production** (paste each RED and its GREEN); every control verifies its own mutation
landed; `test-status-surface.sh` green at baseline and selected by `--scope changed` from a dirty
tree; F5 fixed with a regenerated proof that does not itself show the bug; render time under
~60 ms.
