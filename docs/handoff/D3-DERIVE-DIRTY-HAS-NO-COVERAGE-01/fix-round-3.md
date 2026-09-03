# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — fix round 3: your coverage found a real product defect

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-ledger.sh, plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh, docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01/

Fix round 2 is accepted — commit `484dd7a2`. The setup guards are right, and I read them: `sha` now
comes from the same path-scoped lookup the function performs, and `setup_error` fires distinctly
from an assertion failure. Do not redo any of that.

**The remaining red is not yours. It is the product's, and your coverage is what found it.**

## The measurement

I ran your suite 13 times on this machine. Eleven were `21 passed, 0 failed`. Two were:

```
[TEST] FAIL: C8b: expected landed with sha 87e049d2429e991fe8c61e5077c9ec96d0bf75d7, got: deadnoneunknown
```

Note what that means with your guards in place: the fixture **proved** the path-scoped commit exists
before calling the function — `sha` is non-empty, otherwise `setup_error` would have fired and the
line would say `setup_error`, not `FAIL: C8b`. So the commit is there, and
`_dl_derive_lane_state` still reported no commit.

I ruled out the obvious suspect separately: `--since=@0` does not lose the commit. In a scratch
repo, `git log --since=@0 --pretty=%H -n 1 -- work.txt` returns the same sha as the unfiltered
lookup. Do not spend time re-deriving that.

## The defect

`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`, inside `_dl_derive_lane_state`:

```
found="$(git -C "${repo}" log ${since_arg} --pretty=%H -n 1 -- "${pathspec[@]}" 2>/dev/null || true)"
...
st="$(git -C "${repo}" status --porcelain -uall -- "${pathspec[@]}" 2>/dev/null || true)"
```

Both swallow stderr and coerce **failure** to **empty**, and both are then tested only for
emptiness. A `git` that failed — under load, a transient fork failure, an index lock, anything — is
indistinguishable from a `git` that found nothing. `commit_sha` stays `none`, `dirty` stays `0`, and
the function goes on to emit a **terminal** verdict derived from a measurement that never happened.

That is the exact disease this lane exists to fight, sitting inside the function the D3 merge just
fixed. It is filed as `DERIVE-COERCES-GIT-FAILURE-TO-NO-COMMIT-01`, priority 0.

## Your task

**You are now authorised to edit `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`** — that
prohibition applied to round 2 and is lifted for this narrow change only. Do not touch anything in
that file beyond what is below.

1. Capture each `git` invocation's exit status separately from its output. On non-zero:
   - do **not** treat it as "no commit" or "clean tree";
   - the function must yield an **`unknown`**-shaped result rather than any terminal verdict;
   - the failure must say which command failed and carry git's stderr, not discard it.
2. Apply the same treatment to both call sites — the commit lookup and the dirty probe. Fixing only
   the one your test catches leaves the other to fail silently, and the dirty probe is the one that
   decides whether real uncommitted work gets rescued.
3. Do not widen the lookup. The comment above the commit lookup explains why there is deliberately
   no unscoped fallback — a cross-repo run once stamped `landed` plus the newest commit onto 137
   unrelated lanes. Keep that property; you are changing failure handling, not scope.

## Prove it — the control is the deliverable

Add a suite case that makes `git` fail for the lookup (a `PATH` shim whose `git` exits non-zero is
the clean way, since it needs no privileges and no timing) and asserts the verdict is `unknown`,
**never** `dead`, `no_work`, or `landed`. Then a negative control via the real tool:

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh \
  plugins/leadv2/scripts/leadv2-dispatch-ledger.sh \
  '<mutation restoring `2>/dev/null || true` on the commit lookup>' \
  docs/handoff/D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01
```

`baseline_rc=0`, `mutated_rc=1`, tool exit 0. A second control for the dirty probe, same shape.

Then run the suite **ten** times and paste all ten count lines. Ten, not five: the defect appeared
twice in thirteen, so five runs can come back clean by luck and prove nothing.

## Constraints

- Do NOT touch `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh`, or `tests/run-all.sh` — all
  held by another session.
- No assertion is weakened; nothing goes into `tests/known-red-suites.txt`. In particular, do not
  make C8b tolerant of `dead` — the whole point is that it correctly refuses to.
- Do NOT touch `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, or `docs/handoff/dispatch-nw*`.
- Commit the ledger fix and the new suite case separately.

## Report

The ten suite count lines, both control pairs with their red lines, and the commit shas. Nothing
else.
