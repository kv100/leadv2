# ARM-PRODUCES-NOTHING-02 fix round 1 — architect design

## Headline: there is no flake. The premise of the mission is wrong.

The mission's blocker ("C5 passes in pass 1 and fails in pass 2, therefore flaky") rests on the
assumption that `test-lane-diff-single-repo.sh` "runs the case list twice" against the same target.
It does not. It runs the case list twice against **two different code trees**:

| block | line | `TARGET` | what it proves |
|---|---|---|---|
| 1st `PASS…` block | `test-lane-diff-single-repo.sh:255` | `${SELF_DIR}` — the live, edited worktree | post-fix: does the fix work |
| 2nd `PASS…` block | `test-lane-diff-single-repo.sh:270` | `${PREFIX_DIR}/plugins/leadv2/scripts`, extracted by `git archive HEAD` at line 266 | red-first: was the case RED before the fix |

`FAIL C5-registered-arm-silent` in the **second** block is therefore not a failure — it is the
**required red-first evidence** that C5 genuinely discriminates. C5 exercises
`cause=arm_produced_nothing`, which exists only in the uncommitted diff; against `HEAD` it cannot
fire, so C5 must be red there. The harness header says so explicitly at lines 20-22.

### Verified, not asserted

Run in `.claude/worktrees/99bf56d6`, 2026-08-04T23:04Z:

```
[TEST] PASS C1 … PASS C5-registered-arm-silent      <- block 1, live tree
[TEST] PASS C1 … FAIL C5-registered-arm-silent      <- block 2, git archive HEAD

Results (post-fix, live tree): 5 passed, 0 failed
red-first: 1/5 post-fix-passing cases RED against pre-fix
GREEN-PRE-FIX (not evidence): C1-tracked-mod / C2-untracked-new / C3-clean-anti-rescue / C4-handoff-only-dirt
pre-fix-could-not-run: 0
```

Exit code `0` (line 302 gates only on `POST_FAIL_COUNT`). C3-clean-anti-rescue is green in both
blocks — the hard requirement is intact. C1/C2/C3/C4 are `GREEN-PRE-FIX` because the lane-diff
scoping fix they cover is already committed at `HEAD`; only C5's feature is uncommitted, hence
`red-first: 1/5`.

**The single cause named in one sentence:** the two blocks run against different trees (live vs
`git archive HEAD`), and `run_case` (line 205) emits an identical, unlabelled `[TEST] …` line for
both, so the red-first block is indistinguishable from a re-run and its expected red reads as a
flake.

Ruled out, by inspection, the three candidates the mission proposed:
- **Shared state between blocks** — each case builds its own `mktemp -d` repo via `new_repo`
  (line 41), its own `mktemp -d` resolver dir, and `rm -rf`s both at case exit. `arm-registered`
  is written under `${root}/docs/handoff/` (line 189-190), inside that per-case temp root. Nothing
  survives a case, let alone a block.
- **Ordering / timing** — cases are sequential with no sleeps, locks, or background work.
- **A check reading a real path instead of the fixture's** — the only real path read is
  `${LEADV2_REPO}` for the `git archive` at line 266, which is the intended pre-fix source.

## Layers affected

Test harness only (`plugins/leadv2/scripts/tests/`). **No change to
`leadv2-dispatch-code.sh` or `leadv2-dispatch-product-close.sh`.** Their 349 insertions are correct
as-is: C5 green post-fix, C3 green in both trees.

## Change design

### P1 — label the two blocks (this is the whole fix)

The defect is that a correct harness produces output a careful reader misdiagnoses. Two edits:

1. **Thread a pass label through `run_case`.** Introduce a script-global `PASS_LABEL` set alongside
   `TARGET` (`post-fix` before line 255, `pre-fix` before line 270, `single` in the `--pre-fix`
   branch at line 244). `run_case` prints `[TEST][${PASS_LABEL}] PASS C1-tracked-mod`.

2. **Reframe an expected-red as evidence, not failure.** In the `pre-fix` block, a case that failed
   pre-fix and passed post-fix is the goal. `run_case` must render it as
   `[TEST][pre-fix] RED-AS-EXPECTED C5-registered-arm-silent` rather than `FAIL`. Concretely:
   when `PASS_LABEL == pre-fix`, `rc != 0`, and the same index passed post-fix
   (`POST_RCS[$i] -eq 0`), print `RED-AS-EXPECTED`; a pre-fix case that is red *and* red post-fix
   is a genuine `FAIL` and still prints as such.

   This requires `POST_RCS` to be readable from `run_case`, which it is — it is captured at
   line 256 before the pre-fix block runs. Guard the lookup with `${POST_RCS[$i]:-}` so the
   `--pre-fix` standalone branch (which never populates `POST_RCS`) is unaffected.

3. **Print a one-line header before each block** so the boundary is visible even in truncated
   `tail -N` output:
   `=== pass 1/2: post-fix (live tree: ${TARGET}) ===` and
   `=== pass 2/2: red-first pre-fix (git archive HEAD) — reds here are EVIDENCE ===`.

No case logic, no assertion, no tolerance change. C5's assertion stays exactly as written
(lines 197-199: both `terminal=no_work` **and** `cause=arm_produced_nothing`). The mission's
prohibitions — "do not make the case tolerant of both outcomes", "do not run it only once" — are
respected: both blocks still run, and both assertions stay strict.

### P2 — narrow the tripwire (same class of false alarm, adjacent, cheap)

Line 288 flags `find "${ORIG_HOME}/.claude" -maxdepth 2 -newer "${STAMP}"`. The live run above
tripped on `~/.claude/cache/status-surface` and `~/.claude/.claude.json` — background runtime state
written by the surrounding Claude session, not by this suite. That surfaces a `TRIPWIRE:` alarm on
every clean run, which is the identical failure mode as P1 (harness cries wolf, reader loses the
signal). Prune `-path '*/.claude/cache/*'`, `-name '.claude.json'`, and `-path '*/.claude/todos/*'`
from the `${ORIG_HOME}/.claude` arm. The `${LEADV2_REPO}/plugins` arm — the one that actually
guards the source tree — is left untouched.

Include only if it does not delay P1. If the implementer judges it out of budget, drop it and say
so; P1 alone satisfies the mission.

## Risks

| risk | mitigation |
|---|---|
| Suppressing a real pre-fix regression by relabelling it | Relabel only when the *same index* passed post-fix. Red-pre-fix + red-post-fix stays `FAIL` and still increments `POST_FAIL_COUNT` via the post-fix block. |
| `POST_RCS` unset in the `--pre-fix` standalone branch (line 244) → `set -u` abort | `${POST_RCS[$i]:-}` with an empty-string default; label falls back to `FAIL`. |
| Someone later reads the new `RED-AS-EXPECTED` as "case disabled" | The trailing summary already prints `red-first: N/M post-fix-passing cases RED against pre-fix`; keep it, it is the authoritative count. |
| Editing the harness masks that nothing was actually broken in the gate | Report must state plainly: no product-code change was needed; the gate was correct. |

## Non-goals — the implementer must NOT do these

- Do **not** touch `leadv2-dispatch-code.sh` or `leadv2-dispatch-product-close.sh`. They are correct.
- Do **not** weaken, split, or make-tolerant C5's assertion.
- Do **not** remove the pre-fix block or run the case list once.
- Do **not** touch `case_c3_clean_anti_rescue`.
- Do **not** run `run-core-offline.sh` (codex lockout until 2026-08-08 — unrelated).
- Do **not** commit or push. The lead merges.
- `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` (untracked, present in the worktree) is
  out of scope for this round; leave as-is.

## acceptance:

```yaml
acceptance:
  - surface: rendered_line
    observable: >
      Running plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh prints two clearly
      separated blocks. The first is headed as the post-fix live-tree pass and shows all five
      cases, C1 through C5-registered-arm-silent, marked PASS. The second is headed as the
      red-first pre-fix pass and shows C5-registered-arm-silent marked RED-AS-EXPECTED rather
      than FAIL, with C3-clean-anti-rescue still shown as passing in both blocks. A reader
      scanning the output cannot mistake the second block for a re-run of the first.
    authored_at: 2026-08-04T23:04:31Z
  - surface: rendered_line
    observable: >
      The summary at the end of the same run reads "Results (post-fix, live tree): 5 passed,
      0 failed" and "red-first: 1/5 post-fix-passing cases RED against pre-fix", and no line
      beginning with FAIL: appears anywhere in the output.
    authored_at: 2026-08-04T23:04:31Z
  - surface: rendered_line
    observable: >
      The same run emits no TRIPWIRE block naming paths under the user's ~/.claude/cache or
      ~/.claude/.claude.json. (P2; drop this acceptance line if P2 is dropped.)
    authored_at: 2026-08-04T23:04:31Z
```

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh

DELIVERABLE_COMPLETE
