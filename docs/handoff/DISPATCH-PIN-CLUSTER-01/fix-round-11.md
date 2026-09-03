# DISPATCH-PIN-CLUSTER-01 — round 11: one assertion, and it closes the lane

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

HEAD is `6cd8ef8`. Main is `cf1349e`. This is the last open item on the lane.

**Everything else is done and verified — do not touch it.** Four `MUTATE_LOADER` controls exit 1
each naming their own loader, the clean run exits 0, `test-dirty-lane-never-lands.sh` passes,
`lib/leadv2-admission-class.sh` resolves in a no-lib farm, and `tests/run-all.sh` carries the
`EXTRA_SUITE_MAP` row so CI selects the farm suite.

## [Critical] the fail-closed proof passes for the wrong reason

`exercise_close_gate "${T}/no-canonical-root" dirty` plus the assertions at
`test-consumer-symlink-farm.sh:178-181` are meant to prove that a lane guard which cannot be
found makes the close gate treat the lane as dirty, so a dirty lane can never record `landed`.

It does not test that. I flipped the production stub at
`leadv2-dispatch-product-close.sh:91` from

```bash
lv2_lane_dirty() { return 0; }   # unknown guard state => treat lane as dirty
```

to the original fail-OPEN form:

```bash
lv2_lane_dirty() { return 1; }
```

confirmed the edit landed (`grep -n 'lv2_lane_dirty() { return'` shows `return 1` on line 91), and
re-ran the suite:

```
rc=0
PASS: all four consumer-farm loaders resolve via canonical fallback
```

Green with the guarantee removed. The reason is structural: inside the fixture farm the canonical
fallback still resolves `_LANE_GUARD_SH`, so the `else` branch at `:88-94` never executes and the
stub never runs. The assertion passes because the lane was clean by other means, not because the
fail-closed stub did its job.

Make the fixture actually unable to find the guard — remove it from the local path **and** from
whatever the canonical fallback resolves to inside the sandbox (point `LEADV2_CANONICAL_ROOT` at a
directory that has no `lib/leadv2-lane-guard.sh`). Then assert three things on the persisted
terminal record, never on source text:

1. the terminal is `pass_unlanded`, not `landed`;
2. stderr carries `[leadv2-dispatch-product-close] ERROR: lane guard unavailable`;
3. with the guard present and the lane clean, the terminal IS `landed`.

Then mutation-prove it exactly as I did: flip line 91 to `return 1`, show the suite RED naming that
assertion, revert, show GREEN, and paste a clean `git diff --stat`. If your control does not go red
on that flip, it is the same non-diagnostic shape and the round is not done.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  **A suite that stays green with the fix removed is a failed control.** A printed `RED control:`
  line that does not change the exit code is not an assertion.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The fail-closed assertion goes RED when line 91 is flipped to `return 1` and GREEN when it is not,
both pasted. Then this lane is merge-ready into main at `cf1349e`.
