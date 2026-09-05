# LANE-WRITESET-REGISTRY-01 — FIX ROUND 1. Review returned FAIL: 5 High, 9 Medium.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.
Binding plan: `docs/handoff/LANE-WRITESET-REGISTRY-01/context.yaml` (D1–D9).
Review verdict: `docs/handoff/dispatch-533daa27/review-gate.md` — read it, it has the finding lines.

The feature is built (commits `09a5fca`, `a10f767`, `2db03c1`) and its own suite is green. The
review found the suite is green for the WRONG REASON: it exercises registry internals and never
touches the live wires. Fix the wires, then make the suite able to catch them.

## H1 — the whole point of the task is currently defeated. Fix this first.
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`: registration is TWO-PHASE. The row is appended
at ~:5859 with `writes=None`, and the write set only lands at ~:6005 via a later call, after the
architect prepass. Between those two points the lane is ALIVE with an EMPTY write set, so a
concurrent lead checking for a conflict legitimately sees "no conflict" and admits — which is
exactly the TOCTOU window D3 exists to close, reproduced in the new code. The plan called this
out explicitly as the flaw of fanout's `register`-then-`set_writes` pattern.

Make the declared `writes` reach `register` in the SAME call that appends the row. If the value
genuinely is not known until after the prepass, then the row must not be appended as alive until
it is — say which shape you chose and why. Do not paper over it with a second lock.

## H2 — `leadv2-dispatch-product-close.sh` ~:2113
The drift detector uses bare `git diff --name-only` with no `add -N` temp index (unlike the
neighbouring `_pc_git_diff`), so untracked NEW files are invisible: neither scope-widened nor
flagged. An undeclared brand-new file is precisely the drift case that matters.

## H3 — `leadv2-dispatch-product-close.sh` ~:2220
The landed-foreign escape clears `blocked_reason` and exits 0 `status: passed` for ANY reason
other than `partial_diff`, which swallows `writeset_drift_conflict`. D6's single BLOCK becomes a
pass. Narrow the escape to the reason it was written for.

## H4 — `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh`
The suite covers only registry-internal functions; there is ZERO coverage of the four live wires
this task installs. An arg-order typo at `dispatch-code:6008` passes green today. Add cases that
drive the REAL entry points (dispatch-code registration, product-close drift, phase8-close
notify) with only the layer below faked. Keep the existing cases.

## Also
Work the 9 Medium findings in `review-gate.md` after the Highs. If you judge one wrong, say so
in one line with your reason rather than silently skipping it.

## Proof required — do not report green without these
1. The suite RED before your wire fixes and GREEN after (the new live-wire cases must be the
   ones that flip). Paste both runs.
2. Re-run the declared negative control: `return False` INSIDE `_lv2_ws_overlaps`'s body in a
   scratch copy — suite must go RED. Paste it.
3. A case that fails if H1 regresses: two registrations racing where the write set arrives late.
4. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite is selected.

## Constraints unchanged
`leadv2-writes-overlap.sh` frozen (read-only). `test-writes-overlap.sh` append-only.
`LEADV2_WRITESET_ENFORCE` stays `warn` by default. `LEADV2_WRITES_CONFLICT_NOTIFY=0` must never
turn the gate green. Never edit through a consuming repo.

Return `PASS|PARTIAL|FAIL|BLOCKED` + changed paths + commit SHA + raw test output.
