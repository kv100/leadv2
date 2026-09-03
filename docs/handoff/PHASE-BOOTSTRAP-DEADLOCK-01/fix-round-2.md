# PHASE-BOOTSTRAP-DEADLOCK-01 — round 3: your own suite is red, and the lane is littered

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**.

## Where round 2 stopped

```
status: blocked
reason: selfcheck_failed
failed: falsification:plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh:test_failed
```

The fix (`fdaa9352 fix: admit phase bootstrap before classify`) and the reproduction are committed
and stand. **The suite that is supposed to prove them fails.** That is the whole of this round.

Also: four scratch files were left untracked in the lane worktree —

```
?? debug_p4.sh  ?? test_p4_correct.sh  ?? test_p4_final.sh  ?? test_p4_fixed.sh
```

Delete them. Scratch work goes in `mktemp -d`, never in the worktree; a file named `test_p4_final.sh`
sitting next to the real suite is how a repo grows a second, unowned test surface.

## Deliver

1. **Make `test-phase-precondition-bootstrap.sh` pass, or say why the fix is wrong.** Run it, read
   the actual failure, and paste it before changing anything. Two outcomes are acceptable and no
   third: either the suite had a bug and now passes against the committed fix, or the suite is right
   and the fix is incomplete — in which case fix the fix and say so plainly. Do not weaken an
   assertion to get green; that is the one move that fails this round outright.
2. **Both cases still required, both pasted:** a brand-new task id at class Standard passes the phase
   gate on its first dispatch; a task id that falsely claims a verified plan still refuses.
3. **Negative control.** Restore the original ordering in a mktemp FULL copy of the tree (including
   `lib/`) whose baseline is proven green → case 1 goes red. Paste baseline and mutant runs. Insert
   the mutation INSIDE the function body.
4. **The Heavy path, answered honestly.** A live Heavy dispatch refused today at
   `lane_plan_missing reason=source_absent` after `class_escalated ... because=subsystems_touched:5`.
   Show what a first-time Heavy dispatch must now produce before build. If it still demands a plan
   record it cannot have, say the fix is incomplete for Heavy — do not close on the Standard case
   alone.
5. **Clean tree.** No untracked scratch left behind.

## Known-red note
`run-all.sh` on this lane's base now applies the known-red allow-list to granular nested suite names
(landed on the CI lane as `199f2692`). If a suite from `tests/known-red-suites.txt` still blocks you,
say so — that would mean the allow-list plumbing has a gap, and that is worth more than this round.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.

## Done when
The bootstrap suite is green against the committed fix without any assertion weakened; both cases
pasted; negative control red against a green baseline; the Heavy answer is explicit; the worktree
has no untracked scratch.
